---@module 'lib.nvim.docmap.serve'
--- A minimal HTTP server for the generated map, so the History tab can load
--- commit data on demand instead of having it baked in.
---
--- ## Why this exists at all
---
--- docmap's whole self-image up to here was "produces files, has no runtime".
--- This breaks that deliberately, for a reason that is not a preference:
--- a page opened as `file://` gets an **opaque origin** in Chrome and Firefox,
--- and `fetch()` refuses the `file:` scheme for CORS requests outright
--- (Firefox additionally isolates file origins via `privacy.file_unique_origin`
--- since FF68). `:LibMap open` opens exactly that way. So "load it when the
--- user clicks" cannot mean "read a neighbouring file" — it has to mean a
--- server, where the origin is ordinary `http://127.0.0.1:PORT` and the other
--- end can call `git` directly.
---
--- What that buys is laziness. Analysing one historical commit costs ~0.3s
--- (two `git show` reads of the committed artifact plus the pure analysis);
--- precomputing all ~90 of this repo's commits would cost 25-50s and be stale
--- the moment anything is committed. On demand, it is 0.3s per commit the
--- reader actually opens, and never stale, because git is asked at request
--- time.
---
--- ## Security posture
---
--- Small surface, but a real one — a socket and a subprocess. Three rules,
--- all enforced below rather than documented and hoped for:
---
--- 1. **Bind `127.0.0.1`, never `0.0.0.0`.** This is a personal tool on a
---    personal machine; there is no case where the network needs it.
--- 2. **Validate every `<sha>` against `^[0-9a-f]{7,40}$` before it reaches
---    git.** Without that, a request path is argument injection into a
---    subprocess. The check is a whitelist, not an escape.
--- 3. **No path parameter can leave `out_dir`.** Static serving takes a bare
---    filename, and anything containing a separator or a dot-dot is rejected
---    before it becomes a path.
---
--- Plus a lifecycle rule: the server is torn down on `VimLeavePre`, so
--- quitting the editor cannot leave a listening socket behind.
---
--- ## Why the handlers run through `vim.schedule`
---
--- libuv read callbacks are a fast-event context: `vim.system():wait()` — and
--- anything else built on `vim.wait` — cannot run there. Every request is
--- therefore parsed in the callback but *handled* on the main loop, which is
--- also what makes it safe to touch the IR and call git at all.

local M = {}

local uv = vim.uv or vim.loop

---The single running server, if any. Module-level state, which this file is
---the only owner of — the alternative (a handle the caller stores) would put
---lifecycle management on every call site for a thing there is only ever one
---of per editor session.
---@type { server: userdata, port: integer, cfg: table, clients: table<userdata, boolean>, augroup: integer? }|nil
local current = nil

---@param code integer
---@return string
local function status_text(code)
  return ({
    [200] = "OK",
    [400] = "Bad Request",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [500] = "Internal Server Error",
  })[code] or "OK"
end

---Write one response and close. `Connection: close` on purpose: keep-alive
---would need a state machine per socket to know where one request ends and
---the next begins, and this serves a handful of requests per session.
---@param client userdata
---@param code integer
---@param content_type string
---@param body string
local function respond(client, code, content_type, body)
  if not client or client:is_closing() then
    return
  end
  local head = table.concat({
    ("HTTP/1.1 %d %s"):format(code, status_text(code)),
    "Content-Type: " .. content_type,
    "Content-Length: " .. #body,
    -- The map is local and private; no proxy or browser should keep a copy of
    -- an answer that is only true for the current working tree.
    "Cache-Control: no-store",
    "Connection: close",
    "",
    "",
  }, "\r\n")
  client:write(head .. body, function()
    if not client:is_closing() then
      client:close()
    end
  end)
end

---@param client userdata
---@param code integer
---@param message string
local function respond_error(client, code, message)
  respond(client, code, "application/json", vim.json.encode({ error = message }))
end

---Run git in the repo and return stdout, or nil plus stderr.
---
---Only ever called from a `vim.schedule`d handler — `:wait()` is `vim.wait`
---underneath and would fail in the libuv callback the request arrives on.
---@param cfg table
---@param args string[]
---@return string|nil stdout
---@return string|nil err
local function git(cfg, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local proc = vim.system(cmd, { cwd = cfg.root, text = true }):wait()
  if proc.code ~= 0 then
    return nil, vim.trim(proc.stderr or "git failed")
  end
  return proc.stdout or ""
end

---A commit-ish the caller supplied, or nil if it is not one.
---
---Whitelist, deliberately not an escape or a quoting helper: the value is
---about to become an argument to a subprocess, and the only safe answer to
---"is this a sha" is a shape check that rejects everything else — including
---the `--upload-pack=…`-style arguments that make argument injection into git
---interesting in the first place. Even `HEAD` is refused: it is a perfectly
---good revision but not what this route accepts, and a whitelist that starts
---making exceptions stops being one.
---
---Exported because it is the security property of this module, and a
---security property that cannot be tested without opening a socket does not
---get tested.
---@param s string
---@return string|nil
function M.safe_sha(s)
  return (type(s) == "string" and s:match("^%x%x%x%x%x%x%x+$") and #s <= 40) and s or nil
end

---Read a committed artifact and rehydrate it into an IR.
---
---Absence is a normal outcome, not an error: a revision older than the map
---itself simply has none, and `history.analyze` accepts `nil` for exactly
---that reason.
---@param cfg table
---@param rev string Already validated.
---@return Lib.Docmap.IR|nil
local function ir_at(cfg, rev)
  local rel = (cfg.out_dir or "docs/map") .. "/module_map.json"
  local out = git(cfg, { "show", ("%s:%s"):format(rev, rel) })
  if not out or out == "" then
    return nil
  end
  local ok, doc = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
  if not ok or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
    return nil
  end
  return require("lib.nvim.docmap.browse.source").rehydrate(doc)
end

---`GET /api/commits?n=N` — the list the History tab opens with.
---@param cfg table
---@param client userdata
---@param query string
local function route_commits(cfg, client, query)
  local n = tonumber(query:match("[?&]n=(%d+)")) or 50
  n = math.max(1, math.min(n, 500))

  -- Unit/record separators rather than a printable delimiter: a commit
  -- subject can contain anything, including whatever character looked safe.
  local fmt = "%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"
  local out, err = git(cfg, { "log", "-n", tostring(n), "--date=short", "--format=" .. fmt })
  if not out then
    return respond_error(client, 500, err or "git log failed")
  end

  local commits = {}
  for record in out:gmatch("([^\30]+)") do
    local rec = vim.trim(record)
    if rec ~= "" then
      local f = vim.split(rec, "\31", { plain = true })
      if #f >= 5 then
        commits[#commits + 1] =
          { sha = f[1], short = f[2], author = f[3], date = f[4], subject = f[5] }
      end
    end
  end

  respond(client, 200, "application/json", vim.json.encode({ commits = commits }))
end

---`GET /api/commit/<sha>` — the analysis for one commit, plus its diff text.
---@param cfg table
---@param client userdata
---@param sha string Already validated by the caller.
local function route_commit(cfg, client, sha)
  local out_dir = cfg.out_dir or "docs/map"

  local meta, meta_err = git(cfg, {
    "show",
    "-s",
    "--date=short",
    "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1f%b",
    sha,
  })
  if not meta then
    return respond_error(client, 404, meta_err or "no such commit")
  end
  local mf = vim.split(vim.trim(meta), "\31", { plain = true })

  -- `git show` rather than `git diff <sha>^ <sha>`: it produces the same diff
  -- and additionally handles the root commit, which has no parent to name.
  -- The out_dir exclusion is not cosmetic — measured here, one commit's full
  -- diff is 4.8 MB of which all but ~16 KB is the regenerated map.
  local diff_text, diff_err = git(cfg, {
    "show",
    "--unified=0",
    "--format=",
    sha,
    "--",
    ".",
    (":(exclude)%s"):format(out_dir),
  })
  if not diff_text then
    return respond_error(client, 500, diff_err or "git show failed")
  end

  local ir_after = ir_at(cfg, sha)
  -- A root commit has no parent; `git show` above already handled that, and
  -- here the absent parent IR is simply nil, which `analyze` accepts.
  local ir_before = ir_at(cfg, sha .. "^")

  local history = require("lib.nvim.docmap.history")
  local impact = history.analyze(diff_text, ir_after, ir_before)

  -- Module display names are resolved here rather than in the browser: the
  -- page has the *current* IR embedded, and a commit can name nodes that no
  -- longer exist, so only this side can label them correctly.
  local names = {}
  local function name_of(id)
    if names[id] then
      return names[id]
    end
    local n = ir_after and ir_after.nodes[id]
    names[id] = (n and (n.module or n.path)) or id
    return names[id]
  end
  for _, t in ipairs(impact.touched) do
    name_of(t.node)
    for _, c in ipairs(impact.callers[t.node .. "#" .. t.fn] or {}) do
      name_of(c.node)
    end
  end
  for _, id in ipairs(impact.calling_modules) do
    name_of(id)
  end
  for _, id in ipairs(impact.impacted_modules) do
    name_of(id)
  end

  respond(
    client,
    200,
    "application/json",
    vim.json.encode({
      commit = {
        sha = mf[1] or sha,
        short = mf[2] or sha:sub(1, 7),
        author = mf[3] or "",
        date = mf[4] or "",
        subject = mf[5] or "",
        body = vim.trim(mf[6] or ""),
      },
      impact = impact,
      names = names,
      diff = diff_text,
      -- Said explicitly rather than inferred from an empty list: "the map did
      -- not exist yet at this revision" and "this commit touched no function"
      -- are different answers and the UI must not merge them.
      has_map = ir_after ~= nil,
    })
  )
end

---Serve a file out of `out_dir`.
---
---`name` is a bare filename by contract — the caller has already rejected
---anything containing a separator — so this cannot be walked out of the
---directory. Kept as a check here too rather than trusting the caller,
---because that is the whole security property of this route.
---@param cfg table
---@param client userdata
---@param name string
local function route_static(cfg, client, name)
  if name == "" then
    name = "index.html"
  end
  if name:find("[/\\]") or name:find("%.%.") then
    return respond_error(client, 400, "bad path")
  end

  local path = ("%s/%s/%s"):format(cfg.root, cfg.out_dir or "docs/map", name)
  local fd = io.open(path, "rb")
  if not fd then
    return respond_error(client, 404, "not found: " .. name)
  end
  local body = fd:read("*a")
  fd:close()

  local ext = name:match("%.(%w+)$") or ""
  local ctype = ({
    html = "text/html; charset=utf-8",
    json = "application/json",
    svg = "image/svg+xml",
    md = "text/plain; charset=utf-8",
    css = "text/css",
    js = "text/javascript",
  })[ext] or "application/octet-stream"

  respond(client, 200, ctype, body)
end

---Dispatch one parsed request. Runs on the main loop (see the module header).
---@param cfg table
---@param client userdata
---@param method string
---@param target string
local function handle(cfg, client, method, target)
  if method ~= "GET" then
    return respond_error(client, 405, "only GET is served")
  end

  local path, query = target:match("^([^?]*)(.*)$")
  path = path or "/"
  query = query or ""

  if path == "/api/commits" then
    return route_commits(cfg, client, query)
  end

  local sha_part = path:match("^/api/commit/(.+)$")
  if sha_part then
    local sha = M.safe_sha(sha_part)
    if not sha then
      -- Deliberately not echoed back into the message: refusing to repeat an
      -- unvalidated value is free, and this is the one input that would
      -- otherwise reach a subprocess.
      return respond_error(client, 400, "not a commit hash")
    end
    return route_commit(cfg, client, sha)
  end

  if path:match("^/api/") then
    return respond_error(client, 404, "no such endpoint")
  end

  return route_static(cfg, client, path:gsub("^/", ""))
end

---@param cfg table
---@param client userdata
local function on_connection(cfg, client)
  local buf = ""
  client:read_start(function(err, chunk)
    if err or not chunk then
      if not client:is_closing() then
        client:close()
      end
      return
    end

    buf = buf .. chunk
    -- Wait for the full header block. Only GET is served, so there is no body
    -- to read past it — the headers are the whole request.
    if not buf:find("\r\n\r\n", 1, true) then
      -- A client that never completes a request must not be able to grow this
      -- without bound.
      if #buf > 64 * 1024 then
        client:close()
      end
      return
    end

    local method, target = buf:match("^(%u+)%s+(%S+)%s+HTTP/")
    client:read_stop()

    vim.schedule(function()
      if not method then
        return respond_error(client, 400, "malformed request")
      end
      local ok, herr = pcall(handle, cfg, client, method, target)
      if not ok then
        respond_error(client, 500, tostring(herr))
      end
    end)
  end)
end

---@return boolean
function M.is_running()
  return current ~= nil
end

---@return { port: integer, url: string }|nil
function M.info()
  if not current then
    return nil
  end
  return { port = current.port, url = ("http://127.0.0.1:%d/"):format(current.port) }
end

---Start the server. Idempotent: an already-running server is returned as is
---rather than replaced, so a second `:LibMap serve` does not silently orphan
---the first socket.
---@param cfg table A resolved `Lib.Docmap.Opts`.
---@return string|nil url
---@return string|nil err
function M.start(cfg)
  if current then
    return M.info().url
  end

  local server = uv.new_tcp()
  if not server then
    return nil, "could not create a TCP handle"
  end

  -- Port 0 lets the OS pick a free one, which avoids both a hardcoded port
  -- colliding with something else and a retry loop looking for a free one.
  local ok_bind, bind_err = pcall(function()
    -- 127.0.0.1 only. Never 0.0.0.0: this is a personal tool on a personal
    -- machine, and binding wider would expose the repo's source to the
    -- network for no gain whatsoever.
    assert(server:bind("127.0.0.1", 0))
  end)
  if not ok_bind then
    server:close()
    return nil, "bind failed: " .. tostring(bind_err)
  end

  local name = server:getsockname()
  local port = name and name.port
  if not port then
    server:close()
    return nil, "could not determine the bound port"
  end

  local ok_listen, listen_err = pcall(function()
    assert(server:listen(64, function(lerr)
      if lerr then
        return
      end
      local client = uv.new_tcp()
      if not client then
        return
      end
      server:accept(client)
      on_connection(cfg, client)
    end))
  end)
  if not ok_listen then
    server:close()
    return nil, "listen failed: " .. tostring(listen_err)
  end

  -- Quitting the editor must not leave a listening socket behind. This is the
  -- lifecycle obligation that comes with having a runtime at all, so it is
  -- wired at start rather than left to the user remembering `serve stop`.
  local augroup = vim.api.nvim_create_augroup("lib_docmap_serve", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      M.stop()
    end,
    desc = "lib.nvim.docmap.serve: close the map server on exit",
  })

  current = { server = server, port = port, cfg = cfg, augroup = augroup }
  return M.info().url
end

---Stop the server. Idempotent — stopping twice, or when none ever ran, is a
---no-op rather than an error, matching `uninstall()`'s tolerance elsewhere in
---this module.
---@return boolean stopped True when a server was actually running.
function M.stop()
  if not current then
    return false
  end
  local c = current
  current = nil

  if c.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, c.augroup)
  end
  if not c.server:is_closing() then
    c.server:close()
  end
  return true
end

return M
