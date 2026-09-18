---@module 'lib.nvim.net.curl'
--- Async (and blocking) HTTP-via-curl helper, three tiers (JSON, raw,
--- download-to-file).
---
--- Builds a `curl` argv from `opts` (method, headers, bearer token, query
--- string, body, form fields, basic auth, proxy, HTTP version, raw
--- passthrough args), spawns it through `vim.system` (requires Neovim
--- 0.10+). No `jobstart` fallback — this is a new, opt-in module, so
--- `vim.system` is a hard requirement.
---
--- `fetch_json`/`fetch_json_blocking` decode the response body as JSON for a
--- caller that already knows the answer is JSON. `fetch_raw`/
--- `fetch_raw_blocking` return the response verbatim instead — status,
--- headers, body, undecoded — for a caller that needs to *show* the
--- response (a request-runner UI, say) or whose content type is not JSON at
--- all. Neither is a special case of the other: `fetch_json` never sees a
--- status code or headers at all (curl's own process exit code says
--- nothing about the HTTP status — it is `0` for a successful *request*
--- regardless of whether the server answered `200` or `404`), and
--- `fetch_raw` never assumes the body parses as anything in particular.
--- `download`/`download_blocking` are a third tier: the body is written
--- straight to a file (`-o`) instead of buffered in memory, for responses
--- too large — or simply not needed — to hold as a Lua string.
--- `fetch_stream` is a fourth: no `_blocking` counterpart (streaming and
--- blocking are contradictory), it calls `on_chunk` once per line of raw
--- response body as it arrives instead of buffering the whole thing — for a
--- response that takes multiple seconds and whose caller wants to render it
--- incrementally (SSE `data: ...` lines, NDJSON lines). It returns the
--- underlying `vim.SystemObj` so a caller can `:kill()` an in-progress
--- stream; parsing what a line *means* is left to the caller, same
--- "bytes in, bytes out" split `lib.nvim.cross.uv.spawn_stream` keeps for
--- process output.
---
--- `opts.secret_headers` sends header values through the same `-K -`
--- config-file path already used for `bearer_token`/`opts.auth`/the
--- hardcoded credential header names in `is_secret_header` — but for header
--- *names* that carry a credential only for a specific API (Anthropic's
--- `x-api-key`, say) and so cannot be recognized generically. Anything in
--- `opts.headers` is still sent via `-H` in argv, which is visible to any
--- other process on the machine for the lifetime of the request (Process
--- Explorer/WMI on Windows, `ps` on POSIX) — `secret_headers` is the escape
--- hatch for exactly the header names that must not be.
---
--- `opts.query` is NOT covered by any of this: it is appended straight onto
--- the URL, itself a plain argv element, same as `opts.body`. Do not put a
--- credential in `query` — use a header instead, even for an API that also
--- accepts the credential as a query parameter. See the README's
--- "Not covered either" section; pinned in TESTS/curl_spec.lua, not fixed.
---
--- Usage:
--- ```lua
--- local curl = require("lib.nvim.net.curl")
---
--- curl.fetch_json("https://api.example.com/items", {
---   method = "GET",
---   query = { limit = "10" },
---   bearer_token = "abc123",
--- }, function(ok, data, raw)
---   if ok then
---     vim.print(data)
---   else
---     vim.notify("fetch failed: " .. data, vim.log.levels.ERROR)
---   end
--- end)
---
--- local ok, data, raw = curl.fetch_json_blocking("https://api.example.com/items")
---
--- local ok2, resp = curl.fetch_raw_blocking("https://api.example.com/items")
--- if ok2 then
---   print(resp.status, resp.status_text, resp.headers["content-type"])
---   print(resp.body)
--- end
---
--- local ok3, resp3 = curl.download_blocking("https://example.com/big.zip", "/tmp/big.zip")
--- if ok3 then
---   print(resp3.status) -- resp3.body is "" -- the body went to /tmp/big.zip
--- end
--- ```

require("lib.nvim.net.curl.@types")

local nvim_json = require("lib.nvim.json")
local line_stream = require("lib.nvim.system.lines")

local M = {}

---@internal
---Percent-encode `s` for safe use in a URL query component.
---@param s string
---@return string
local function url_encode(s)
  return (
    s:gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
  )
end

---@internal
---Build the `?k=v&...` query string (with leading `?`) for `query`, or `""`.
---@param query table<string, string>|nil
---@return string
local function build_query_string(query)
  if not query or next(query) == nil then
    return ""
  end
  local parts = {}
  for k, v in pairs(query) do
    parts[#parts + 1] = url_encode(tostring(k)) .. "=" .. url_encode(tostring(v))
  end
  return "?" .. table.concat(parts, "&")
end

---Escape `value` for a curl config file's quoted-string form.
---
---Public because a caller that builds its own curl argv needs the same two
---helpers, and a second copy of them is a second thing to get wrong. curl
---unescapes `\\`, `\"`, `\t`, `\n`, `\r` and `\v` there; a raw newline (or
---tab/CR/vertical-tab) ends the option early otherwise, so all six are
---escaped to curl's own two-character sequences here -- a credential with a
---trailing newline (a common shape for a key read from a file or `.env`
---loader) must round-trip intact, not silently truncate the config line.
---@param value string
---@return string
function M.config_quote(value)
  local escaped = value
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\t", "\\t")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\v", "\\v")
  return '"' .. escaped .. '"'
end

---Whether a header name carries a credential and therefore must not reach
---argv. Matched case-insensitively, since header names are.
---
---`private-token` is on this list even though it was introduced by one API
---(GitLab's): unlike `x-api-key`, whose value is a public client identifier for
---some services, the name states outright that its value is a secret, so
---treating it as one cannot be wrong for any caller. Header names that only
---carry a credential for a specific API still belong in `opts.secret_headers`.
---@param name string
---@return boolean
function M.is_secret_header(name)
  local lower = name:lower()
  return lower == "authorization"
    or lower == "proxy-authorization"
    or lower == "cookie"
    or lower == "private-token"
end

---@internal
---Build the curl argv table for `url`/`opts`.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts
---@param include_headers boolean? Add `-i`, so the response headers precede
---the body in stdout — what `fetch_raw`/`fetch_raw_blocking` need to parse
---status and headers out; `fetch_json`/`fetch_json_blocking` leave this
---unset, since a header block would break their JSON decode.
---@param download_dest string? Set by `download`/`download_blocking`: the
---body goes to this file (`-o`) instead of stdout, headers are dumped to
---stdout separately (`-D -`) since `-i` and `-o` don't compose the way
---`fetch_raw` needs (with `-o`, `-i` would write headers into the file
---too). Mutually exclusive with `include_headers`.
---@return string[] argv
---@return string|nil stdin  curl config for the credential-bearing options,
---to be fed to the process; nil when there are none.
local function build_argv(url, opts, include_headers, download_dest)
  local argv = { "curl", "-sS", "-X", opts.method or "GET" }

  -- Anything carrying a credential goes into a config curl reads from stdin,
  -- never into argv. A process's command line is readable by any other
  -- process on the machine -- `ps` on Unix, Win32_Process on Windows --
  -- verified here with a real token, which showed up in full in the process
  -- list for the lifetime of the request. `-K -` is curl's own answer to
  -- exactly this.
  local config = {}
  if include_headers then
    argv[#argv + 1] = "-i"
  elseif download_dest then
    argv[#argv + 1] = "-D"
    argv[#argv + 1] = "-"
    argv[#argv + 1] = "-o"
    argv[#argv + 1] = download_dest
  end

  if opts.insecure then
    argv[#argv + 1] = "-k"
  end

  if opts.max_bytes then
    argv[#argv + 1] = "--max-filesize"
    argv[#argv + 1] = tostring(opts.max_bytes)
  end

  if opts.http_version == "1.0" then
    argv[#argv + 1] = "--http1.0"
  elseif opts.http_version == "1.1" then
    argv[#argv + 1] = "--http1.1"
  elseif opts.http_version == "2" then
    argv[#argv + 1] = "--http2"
  end

  if opts.proxy then
    argv[#argv + 1] = "-x"
    argv[#argv + 1] = opts.proxy
  end

  if opts.auth then
    config[#config + 1] = "user = "
      .. M.config_quote((opts.auth.user or "") .. ":" .. (opts.auth.pass or ""))
  end

  -- Header names are case-insensitive, so a caller setting the same one in
  -- both `opts.headers` and `opts.secret_headers` (e.g. by mistake, or a
  -- future provider copy-pasting an existing one) must not have it sent
  -- twice -- once safely via `-K`, once in plaintext argv via `-H`. The
  -- explicit `secret_headers` entry always wins; skip it here instead.
  ---@param key string
  ---@return boolean
  local function has_secret_header(key)
    if not opts.secret_headers then
      return false
    end
    local lower = key:lower()
    for secret_key in pairs(opts.secret_headers) do
      if secret_key:lower() == lower then
        return true
      end
    end
    return false
  end

  for key, value in pairs(opts.headers or {}) do
    if not has_secret_header(key) then
      local header = key .. ": " .. value
      if M.is_secret_header(key) then
        config[#config + 1] = "header = " .. M.config_quote(header)
      else
        argv[#argv + 1] = "-H"
        argv[#argv + 1] = header
      end
    end
  end

  if opts.bearer_token then
    config[#config + 1] = "header = "
      .. M.config_quote("Authorization: Bearer " .. opts.bearer_token)
  end

  -- Unlike `opts.headers`, everything here goes through the config-file path
  -- unconditionally — the caller is asserting "this name carries a
  -- credential", `is_secret_header` does not need to already know the name.
  for key, value in pairs(opts.secret_headers or {}) do
    config[#config + 1] = "header = " .. M.config_quote(key .. ": " .. value)
  end

  -- A value starting with "@" is curl's own file-upload syntax (-F
  -- "field=@/path/to/file") and works unchanged — no separate file-upload
  -- option needed.
  for key, value in pairs(opts.form or {}) do
    argv[#argv + 1] = "-F"
    argv[#argv + 1] = key .. "=" .. value
  end

  if opts.body then
    argv[#argv + 1] = "-d"
    argv[#argv + 1] = opts.body
  end

  for _, raw in ipairs(opts.raw_args or {}) do
    argv[#argv + 1] = raw
  end

  argv[#argv + 1] = url .. build_query_string(opts.query)

  if #config == 0 then
    return argv, nil
  end

  -- `-K -` has to precede the URL for curl to still treat the URL as the URL,
  -- and it is inserted rather than appended for that reason.
  table.insert(argv, 2, "-K")
  table.insert(argv, 3, "-")
  return argv, table.concat(config, "\n") .. "\n"
end

---@internal
---Decode a completed curl `obj` into the `(ok, data_or_err, raw_obj)` contract.
---@param obj vim.SystemCompleted
---@return boolean ok
---@return any data_or_err
local function decode_result(obj)
  if obj.code ~= 0 then
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err
  end

  local decoded, err = nvim_json.decode(obj.stdout)
  if err then
    return false, "invalid JSON response"
  end
  return true, decoded
end

--- Every `parse_raw_response` failure sets an `err`, but that pairing lives
--- in prose rather than in the two return slots -- this is what the four
--- call sites fall back to instead of forwarding a `nil` message.
local UNPARSEABLE = "unparseable curl output"

---@internal
---Best-effort delete of a `download`/`download_blocking` destination after
---curl itself failed (non-zero exit -- a network error, a timeout, `-D -`
---getting killed mid-transfer). curl's `-o` writes as it streams, so a
---failed transfer routinely leaves a truncated file behind; silently
---keeping it around would let a caller that doesn't check `ok` mistake a
---partial file for a complete one. Never called after a *parse* failure
--- (curl exited 0, i.e. the transfer itself completed) -- only a failed
---request discards what it wrote.
---@param dest_path string
local function remove_partial(dest_path)
  pcall(os.remove, dest_path)
end

---@internal
---Parse curl `-i` output (response headers, then a blank line, then the
---body) into status/headers/body. curl's own process exit code says nothing
---about the HTTP status — it is 0 for a successful *request* regardless of
---whether the server answered 200 or 404 — so this is the only way to learn
---what actually came back.
---
---Loops past any informational response (a `100 Continue` preamble, or a
---redirect hop if the caller ever passes `-L`, which `build_argv` does not
---today): each 1xx/redirect response is itself a complete
---"status line + headers + blank line" block, immediately followed by
---another one, so the loop keeps unwrapping blocks until it finds one not
---followed by a further `HTTP/` line — that one is the real, final response.
---@param output string Raw stdout from a curl invocation built with `include_headers = true`.
---@return Lib.Net.Curl.RawResponse? response `nil` on unparseable output.
---@return string? err Set only when `response` is `nil`.
local function parse_raw_response(output)
  while true do
    if not output:match("^HTTP/") then
      return nil, "no HTTP status line in curl output"
    end
    local sep_s, sep_e = output:find("\r?\n\r?\n")
    local block, rest
    if sep_s then
      block, rest = output:sub(1, sep_s - 1), output:sub(sep_e + 1)
    else
      -- Headers with no blank-line terminator at all (a truncated or
      -- header-only response) — treat everything as headers, body empty,
      -- rather than guessing where one might have started.
      block, rest = output, ""
    end

    local lines = vim.split(block, "\r?\n")
    local code, text = lines[1]:match("^HTTP/[%d%.]+%s+(%d+)%s*(.-)%s*$")
    if not code then
      return nil, "malformed status line: " .. lines[1]
    end

    if rest:match("^HTTP/") then
      -- An intermediate block (1xx, or a redirect hop) — unwrap and keep
      -- going; this one is not the caller's answer.
      output = rest
    else
      local headers = {}
      for i = 2, #lines do
        local k, v = lines[i]:match("^([^:]+):%s*(.-)%s*$")
        if k then
          headers[k:lower()] = v
        end
      end
      return { status = tonumber(code), status_text = text or "", headers = headers, body = rest }
    end
  end
end

---Fetch `url` and return the response verbatim — status, headers and body,
---undecoded — asynchronously. The second, "Postman-lite" tier alongside
---`fetch_json`: that one is right when the caller already knows the answer
---is JSON and only wants the decoded value; this one is for a caller that
---needs to *show* the response, or one whose content type is not JSON at
---all.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param cb fun(ok:boolean, response_or_err:Lib.Net.Curl.RawResponse|string, raw_obj:vim.SystemCompleted)
function M.fetch_raw(url, opts, cb)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv, stdin = build_argv(url, opts, true)

  vim.system(argv, { text = true, stdin = stdin, timeout = opts.timeout_ms }, function(obj)
    -- vim.system's completion callback runs in a fast event context; a
    -- caller's `cb` routinely touches the UI (vim.notify, a popup, ...),
    -- which Neovim's API rejects from there (E5560). fetch_stream already
    -- schedules its handlers for the same reason -- this tier just hadn't
    -- caught up.
    vim.schedule(function()
      if obj.code ~= 0 then
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
        cb(false, err, obj)
        return
      end
      local response, err = parse_raw_response(obj.stdout)
      if not response then
        cb(false, err or UNPARSEABLE, obj)
        return
      end
      cb(true, response, obj)
    end)
  end)
end

---Fetch `url` and return the response verbatim, blocking the caller. See
---`fetch_raw` for what "verbatim" means and when to reach for it instead of
---`fetch_json_blocking`.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@return boolean ok
---@return Lib.Net.Curl.RawResponse|string response_or_err
---@return vim.SystemCompleted raw_obj
function M.fetch_raw_blocking(url, opts)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv, stdin = build_argv(url, opts, true)

  local obj = vim.system(argv, { text = true, stdin = stdin }):wait(opts.timeout_ms)
  if obj.code ~= 0 then
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err, obj
  end
  local response, err = parse_raw_response(obj.stdout)
  if not response then
    return false, err or UNPARSEABLE, obj
  end
  return true, response, obj
end

---Fetch `url` and decode the response body as JSON, asynchronously.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param cb fun(ok:boolean, data_or_err:any, raw_obj:vim.SystemCompleted)
function M.fetch_json(url, opts, cb)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv, stdin = build_argv(url, opts)

  vim.system(argv, { text = true, stdin = stdin, timeout = opts.timeout_ms }, function(obj)
    -- See fetch_raw's identical comment: this callback runs in a fast
    -- event context, and a caller's `cb` routinely touches the UI.
    local ok, data_or_err = decode_result(obj)
    vim.schedule(function()
      cb(ok, data_or_err, obj)
    end)
  end)
end

---Fetch `url` and decode the response body as JSON, blocking the caller.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@return boolean ok
---@return any data_or_err
---@return vim.SystemCompleted raw_obj
function M.fetch_json_blocking(url, opts)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv, stdin = build_argv(url, opts)

  local obj = vim.system(argv, { text = true, stdin = stdin }):wait(opts.timeout_ms)
  local ok, data_or_err = decode_result(obj)
  return ok, data_or_err, obj
end

--- A download with neither a byte limit nor a wall-clock limit lets a hostile
--- or merely broken endpoint fill the disk before `remove_partial` ever runs
--- (it only runs once curl has exited). Both therefore default on for the
--- download tier; `false` lifts either explicitly. The fetch tiers keep
--- `timeout_ms` opt-in: they buffer in memory, and a caller streaming a long
--- response would be cut off by a default.
local DEFAULT_DOWNLOAD_TIMEOUT_MS = 5 * 60 * 1000
local DEFAULT_DOWNLOAD_MAX_BYTES = 512 * 1024 * 1024

---@internal
---@param opts Lib.Net.Curl.FetchOpts
---@return Lib.Net.Curl.FetchOpts
local function bounded(opts)
  local out = vim.tbl_extend("force", {}, opts)
  if out.max_bytes == nil then
    out.max_bytes = DEFAULT_DOWNLOAD_MAX_BYTES
  end
  if out.timeout_ms == nil then
    out.timeout_ms = DEFAULT_DOWNLOAD_TIMEOUT_MS
  end
  return out
end

---Fetch `url` and write the response body directly to `dest_path` instead
---of buffering it in memory, asynchronously. Returns status/headers like
---`fetch_raw` — `response.body` is always `""` here, since the body went
---to `dest_path`, not stdout. Bounded by default: see `bounded`.
---@param url string
---@param dest_path string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param cb fun(ok:boolean, response_or_err:Lib.Net.Curl.RawResponse|string, raw_obj:vim.SystemCompleted)
function M.download(url, dest_path, opts, cb)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = bounded(opts or {})

  local argv, stdin = build_argv(url, opts, false, dest_path)

  vim.system(argv, { text = true, stdin = stdin, timeout = opts.timeout_ms or nil }, function(obj)
    -- See fetch_raw's identical comment: this callback runs in a fast
    -- event context, and a caller's `cb` routinely touches the UI.
    vim.schedule(function()
      if obj.code ~= 0 then
        remove_partial(dest_path)
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
        cb(false, err, obj)
        return
      end
      local response, err = parse_raw_response(obj.stdout)
      if not response then
        cb(false, err or UNPARSEABLE, obj)
        return
      end
      cb(true, response, obj)
    end)
  end)
end

---Blocking counterpart to `M.download`.
---@param url string
---@param dest_path string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@return boolean ok
---@return Lib.Net.Curl.RawResponse|string response_or_err
---@return vim.SystemCompleted raw_obj
function M.download_blocking(url, dest_path, opts)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = bounded(opts or {})

  local argv, stdin = build_argv(url, opts, false, dest_path)

  local timeout = opts.timeout_ms or nil
  local obj = vim.system(argv, { text = true, stdin = stdin, timeout = timeout }):wait(timeout)
  if obj.code ~= 0 then
    remove_partial(dest_path)
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err, obj
  end
  local response, err = parse_raw_response(obj.stdout)
  if not response then
    return false, err or UNPARSEABLE, obj
  end
  return true, response, obj
end

---Fetch `url`, calling `handlers.on_chunk` once per line of the raw response
---body as it arrives, instead of buffering the whole response like
---`fetch_json`/`fetch_raw` do. No blocking counterpart — streaming and
---blocking are contradictory. Splits strictly on `\n` (a trailing `\r` is
---stripped, so both LF and CRLF line endings work); a final line with no
---trailing newline is still delivered to `on_chunk` before `on_done` fires.
---Deliberately does not interpret line content — SSE's `data: ...` prefix,
---the `data: [DONE]` sentinel, or NDJSON decoding are the caller's job, not
---this module's (same "bytes in, bytes out" split as `fetch_raw`'s relation
---to `fetch_json`, just one layer earlier).
---
---Unlike `fetch_json`/`fetch_raw`, `on_done` receives the raw
---`vim.SystemObj` unconditionally, whether curl exited 0 or not -- there is
---no built-in ok/err split here. A non-zero `obj.code` (or `obj.stderr`) is
---the caller's own responsibility to check before treating the accumulated
---chunks as a real answer.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param handlers Lib.Net.Curl.StreamHandlers
---@return vim.SystemObj process Call `process:kill(15)` to cancel a stream in progress.
function M.fetch_stream(url, opts, handlers)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}
  handlers = handlers or {}

  local argv, stdin = build_argv(url, opts)
  -- `-N`/`--no-buffer`: curl fully buffers its own stdout by default once it
  -- is not a TTY (i.e. always, once spawned via `vim.system`) -- nothing
  -- reaches this process until curl's internal buffer fills (~4KB) or the
  -- request finishes. That defeats the entire point of a streaming fetch, so
  -- it is unconditional here (unlike the other tiers, which never stream and
  -- so never notice the default buffering).
  table.insert(argv, 2, "-N")

  -- Chunks arrive mid-line; the collector holds the partial back until the
  -- rest of the same stream completes it (@see lib.nvim.system.lines).
  local collector = line_stream.collector()

  ---@param err string|nil
  ---@param data string|nil
  local function on_stdout(err, data)
    if err then
      if handlers.on_error then
        vim.schedule(function()
          handlers.on_error(err)
        end)
      end
      return
    end
    if not data then
      return -- stdout closed; on_exit (below) still fires separately
    end
    for _, line in ipairs(collector.feed(data)) do
      if handlers.on_chunk then
        vim.schedule(function()
          handlers.on_chunk(line)
        end)
      end
    end
  end

  return vim.system(
    argv,
    { text = true, stdin = stdin, timeout = opts.timeout_ms, stdout = on_stdout },
    function(obj)
      local line = collector.flush()
      if line and handlers.on_chunk then
        vim.schedule(function()
          handlers.on_chunk(line)
        end)
      end
      if handlers.on_done then
        vim.schedule(function()
          handlers.on_done(obj)
        end)
      end
    end
  )
end

---@type Lib.Net.Curl
return M
