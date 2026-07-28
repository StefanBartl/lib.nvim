---@module 'lib.nvim.docmap.browse'
--- `:LibBrowse` — the module map inside the editor.
---
--- Explicitly **not** the HTML diagram in a terminal. Boxes with connecting
--- curves need pixels: free positions, curves, continuous zoom. A terminal
--- gives a fixed cell grid, and what comes out of that is a worse version of
--- a page that already exists. This is a *navigator over the same edges*, so
--- the hierarchy is a drill-down list and Deps/Calls are lists, not graphs.
---
--- What justifies it existing next to the generated page — three things the
--- page cannot do at all:
---   1. jump to the source at the line (`gd`);
---   2. fill the quickfix list (`gq`) — the point where call edges stop being
---      decorative and start saving work;
---   3. be live (`:LibBrowse live`), where the page is a snapshot of the last
---      `:LibMap`.
---
---   :LibBrowse            read docs/map/module_map.json (~10ms)
---   :LibBrowse live       install a watching handle instead (~0.65s once)
---   :LibBrowse lib.nvim.fs   open centered on a module
---   :LibBrowse history    open on the commit list
---
--- Keys: 1..5 modes · j/k move · <CR> descend · -/<BS> up · <C-o>/<C-i>
--- history · h/l direction · +/_ depth · gd source · gq quickfix · gI impact
--- · gO open the page here · gD the opened commit's diff · / search · q close.

require("lib.nvim.docmap.browse.@types")

local kit = require("lib.nvim.ui.kit")
local map = require("lib.nvim.map")
local notify = require("lib.nvim.notify").create("[docmap.browse]")
local source = require("lib.nvim.docmap.browse.source")
local view = require("lib.nvim.docmap.browse.view")

local M = {}

---Single active browser, mirroring the chooser/confirm single-instance model
---in `lib.nvim.ui.kit`: two of these on screen at once would fight over the
---same keys and the same "which window am I in" question.
---@type table|nil
local state = nil

local MODES = { "structure", "deps", "calls", "types", "history" }

-- ── History mode: the git half ──────────────────────────────────────────────
--
-- `view.lua` is pure and stays that way, so everything that shells out lives
-- here and hands the results over on the state. Same split as `history.lua`
-- (pure) plus `command.lua` (git) — and the same reason: the mode logic is
-- then testable headlessly without a repository.

---@param st table
---@param args string[]
---@return string|nil stdout
---@return string|nil err
local function git(st, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local proc = vim.system(cmd, { cwd = st.opts.root, text = true }):wait()
  if proc.code ~= 0 then
    return nil, vim.trim(proc.stderr or "git failed")
  end
  return proc.stdout or ""
end

---Load the commit list once per session. Cached on the state: it is the same
---list every time the mode is entered, and re-running `git log` on each `5`
---keypress would make the mode feel slower than it is.
---@param st table
local function load_commits(st)
  if st.commits then
    return
  end
  -- Unit/record separators, not a printable delimiter: a subject can contain
  -- whatever character looked safe.
  local out, err =
    git(st, { "log", "-n", "200", "--date=short", "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e" })
  if not out then
    st.commits = {}
    notify.warn("git log failed: " .. tostring(err))
    return
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
  st.commits = commits
end

---Analyse one commit: its diff, the artifacts either side of it, and the
---pure `history.analyze` over both.
---
---`git show` rather than `git diff <sha>^ <sha>` because it also handles the
---root commit, which has no parent to name. Excluding `out_dir` is not
---cosmetic: measured here, a commit's full diff is 4.8 MB of which all but
---~16 KB is the regenerated map.
---@param st table
---@param sha string
local function load_impact(st, sha)
  local out_dir = st.opts.out_dir or "docs/map"

  local diff_text, derr = git(st, {
    "show",
    "--unified=0",
    "--format=",
    sha,
    "--",
    ".",
    (":(exclude)%s"):format(out_dir),
  })
  if not diff_text then
    notify.warn("git show failed: " .. tostring(derr))
    st.impact = nil
    return
  end
  st.diff_text = diff_text

  ---@param rev string
  ---@return Lib.Docmap.IR|nil
  local function ir_at(rev)
    local rel = out_dir .. "/module_map.json"
    local raw = git(st, { "show", ("%s:%s"):format(rev, rel) })
    if not raw or raw == "" then
      return nil
    end
    local ok, doc = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
    if not ok or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
      return nil
    end
    return require("lib.nvim.docmap.browse.source").rehydrate(doc)
  end

  local ir_after = ir_at(sha)
  local ir_before = ir_at(sha .. "^")
  st.impact_has_map = ir_after ~= nil
  st.impact = require("lib.nvim.docmap.history").analyze(diff_text, ir_after, ir_before)
end

---@return boolean
function M.is_open()
  return state ~= nil and state.group ~= nil and state.slots.list:is_valid()
end

---Close the browser (idempotent).
function M.close()
  local st = state
  state = nil
  if not st then
    return
  end
  if st.unsubscribe then
    pcall(st.unsubscribe)
  end
  if st.group then
    pcall(st.group.close)
  end
end

-- ── Rendering ───────────────────────────────────────────────────────────────

---@param st table
local function render(st)
  -- History's data comes from git, not the IR, so it is fetched here rather
  -- than in `go`: `<C-o>` restores a `sha` straight onto the state without
  -- passing through `go` at all, and the analysis has to follow it. Keyed on
  -- `impact_sha` so stepping back onto a commit already looked at costs
  -- nothing.
  if st.mode == "history" then
    load_commits(st)
    if st.sha and st.impact_sha ~= st.sha then
      load_impact(st, st.sha)
      st.impact_sha = st.sha
    elseif not st.sha then
      st.impact, st.impact_sha, st.impact_has_map, st.diff_text = nil, nil, nil, nil
    end
  end

  st.entries = view.entries(st.ir, st)

  if st.cursor > #st.entries then
    st.cursor = #st.entries
  end
  if st.cursor < 1 then
    st.cursor = 1
  end

  local list_w = vim.api.nvim_win_get_width(st.slots.list.winid)
  st.slots.list:set_lines(view.list_lines(st.entries, list_w))
  st.slots.list:set_title((" %s "):format(st.mode))

  if st.slots.list:is_valid() and #st.entries > 0 then
    pcall(vim.api.nvim_win_set_cursor, st.slots.list.winid, { st.cursor, 0 })
  end

  st.slots.detail:set_lines(view.detail(st.ir, st, st.entries[st.cursor]))
  st.slots.status:set_lines({ view.status(st.ir, st) })
end

---The entry under the cursor.
---
---Reads the window rather than a cached index on purpose. `st.cursor` is kept
---in step by a `CursorMoved` autocmd, which is fine for *rendering* but must
---not be what an action trusts: any path that moves the cursor without firing
---that autocmd (a mapping with `noautocmd`, a `feedkeys` batch, `:normal!`
---from another plugin) would leave the cache stale and make `<CR>` act on a
---row the user is not looking at. The window position is the truth; the cache
---only exists so a redraw can restore it.
---@param st table
---@return Lib.Docmap.Browse.Entry|nil
local function selected(st)
  if st.slots.list:is_valid() and #st.entries > 0 then
    local row = vim.api.nvim_win_get_cursor(st.slots.list.winid)[1]
    st.cursor = math.max(1, math.min(row, #st.entries))
  end
  return st.entries[st.cursor]
end

---Re-render only the detail pane — what `j`/`k` need. Rebuilding the list on
---every cursor move would reset the cursor and fight the movement.
---@param st table
local function render_detail(st)
  st.slots.detail:set_lines(view.detail(st.ir, st, selected(st)))
  st.slots.status:set_lines({ view.status(st.ir, st) })
end

-- ── Navigation ──────────────────────────────────────────────────────────────

---@param st table
---@return table
local function snapshot(st)
  return {
    mode = st.mode,
    id = st.id,
    fn = st.fn,
    dir = st.dir,
    depth = st.depth,
    cursor = st.cursor,
    sha = st.sha,
  }
end

-- `sha` travels with the trail so `<C-o>` out of a commit lands back on the
-- list rather than on the same commit with a different cursor. The analysis
-- itself is not snapshotted — it is derived, and re-deriving on the way back
-- is cheaper than carrying a copy of it per history entry.
local SNAP_KEYS = { "mode", "id", "fn", "dir", "depth", "cursor", "sha" }

--- A patch cannot say "clear this field" with `nil`: `pairs` never yields a
--- key whose value is nil, so `{ sha = nil }` *is* the empty table and the
--- move silently keeps the old value. Found the honest way — `-` out of an
--- opened commit redrew the same function list, because `go` had been handed
--- nothing at all. Hence a sentinel.
local CLEAR = setmetatable({}, {
  __tostring = function()
    return "<clear>"
  end,
})

---Keep the entry for the position being left in step with the window before
---moving off it, so coming back restores the row the user was actually on
---rather than the row they arrived at.
---@param st table
local function sync_snapshot(st)
  selected(st)
  local snap = st.history[st.hindex]
  if snap then
    snap.cursor = st.cursor
  end
end

---Record the current position, then apply `changes`.
---
---`history` holds the whole trail **including where we are now**, and `hindex`
---points at it. That is the model the HTML renderer uses and the one every
---browser uses, and it is worth stating because the alternative — recording
---only *past* positions — is what this did first and it could not work: after
---a move `hindex` addressed the entry before the current one, so the first
---`<C-o>` fell off the front and the second landed one stop too far back.
---@param st table
---@param changes table
local function go(st, changes)
  sync_snapshot(st)

  -- A new move truncates any forward history, exactly like a browser.
  for i = #st.history, st.hindex + 1, -1 do
    st.history[i] = nil
  end

  for k, v in pairs(changes) do
    if v == CLEAR then
      st[k] = nil
    else
      st[k] = v
    end
  end
  if changes.cursor == nil then
    st.cursor = 1
  end

  st.history[#st.history + 1] = snapshot(st)
  st.hindex = #st.history
  render(st)
end

---@param st table
---@param delta integer
local function history_step(st, delta)
  local target = st.hindex + delta
  if target < 1 or target > #st.history then
    return
  end
  sync_snapshot(st)
  st.hindex = target
  local snap = st.history[target]
  for _, k in ipairs(SNAP_KEYS) do
    st[k] = snap[k]
  end
  render(st)
end

---Descend: into a node's children, or onto a function's own call view.
---@param st table
local function enter(st)
  local e = selected(st)
  if not e then
    return
  end

  -- History descends within its own mode first: commit → the functions it
  -- touched. Only from there does `<CR>` leave for the call graph.
  if e.kind == "commit" and e.sha then
    go(st, { sha = e.sha })
    return
  end
  if st.mode == "history" and st.sha and e.kind == "function" and e.id and e.fn then
    -- `dir = "in"` because the question the History mode is asking is "who
    -- calls the thing that changed" — leaving on `out` would answer a
    -- question nobody was on this screen to ask.
    go(st, { mode = "calls", id = e.id, fn = e.fn, dir = "in", sha = CLEAR })
    return
  end

  if e.kind == "node" and e.id then
    -- In deps/calls, following an edge re-centers on the far node while
    -- keeping the mode — that *is* "follow the edge".
    go(st, { id = e.id, fn = CLEAR })
  elseif e.kind == "function" and e.id and e.fn then
    go(st, { mode = "calls", id = e.id, fn = e.fn, dir = "out" })
  end
end

---@param st table
local function up(st)
  -- In History, "out" is the commit list, not the parent node — the node
  -- hierarchy has nothing to do with what this mode is showing.
  if st.mode == "history" and st.sha then
    go(st, { sha = CLEAR })
    return
  end
  if st.fn then
    go(st, { fn = CLEAR, mode = st.mode == "calls" and "structure" or st.mode })
    return
  end
  local node = st.ir.nodes[st.id]
  if node and node.parent then
    go(st, { id = node.parent })
  end
end

-- ── Actions ─────────────────────────────────────────────────────────────────

---Absolute path for a repo-relative source path.
---@param st table
---@param rel string
---@return string
local function abs(st, rel)
  return source.norm_root(st.opts.root) .. "/" .. rel
end

---`gd` — open the source and close the browser.
---
---Closing is deliberate: the floats sit over the whole editor, and leaving
---them up means jumping "to" a file the user cannot see.
---@param st table
local function goto_source(st)
  local e = selected(st) or {}
  local rel = e.source or (st.ir.nodes[st.id] or {}).source
  if not rel then
    notify.warn("nothing to open here")
    return
  end
  local line = e.line
  local path = abs(st, rel)

  M.close()
  vim.cmd.edit(vim.fn.fnameescape(path))
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    vim.cmd("normal! zz")
  end
end

---`gq` — the current list into the quickfix list.
---@param st table
local function to_quickfix(st)
  local items = {}
  for _, e in ipairs(st.entries) do
    if e.source then
      items[#items + 1] = {
        filename = abs(st, e.source),
        lnum = e.line or 1,
        col = 1,
        text = (e.label or ""):gsub("^%s+", ""),
      }
    end
  end

  if #items == 0 then
    notify.warn("nothing in this list has a source location")
    return
  end

  vim.fn.setqflist({}, " ", {
    title = ("docmap %s: %s"):format(st.mode, view.breadcrumb(st.ir, st.id)),
    items = items,
  })
  M.close()
  vim.cmd("copen")
end

---`gI` — the blast radius of the centered node into the quickfix list.
---
---The counterpart to `gq`: `gq` sends what is *on screen*, this sends what
---would break. Transitive, so it answers the question actually being asked
---before a refactor rather than only naming the immediate dependents.
---Acts on whatever the **detail pane** is describing, not on the centered
---node. Those differ the moment the cursor moves off the first row, and a
---`gI` that reported a different number from the one just read two panes over
---would be worse than no number at all.
---@param st table
local function impact_to_quickfix(st)
  local entry = selected(st)
  local target = (entry and entry.id) or st.id
  local hull, direct = require("lib.nvim.docmap.deps").impact(st.ir, target)
  if #hull == 0 then
    notify.info("nothing depends on this — safe to change")
    return
  end

  local items = {}
  for _, id in ipairs(hull) do
    local node = st.ir.nodes[id]
    if node and node.source then
      items[#items + 1] = {
        filename = abs(st, node.source),
        lnum = 1,
        col = 1,
        text = node.module or node.path or id,
      }
    end
  end

  vim.fn.setqflist({}, " ", {
    title = ("docmap impact: %s (%d, %d direct)"):format(
      view.breadcrumb(st.ir, target),
      #hull,
      direct
    ),
    items = items,
  })
  M.close()
  vim.cmd("copen")
end

---`gD` — the opened commit's diff in a scratch buffer.
---
---A buffer rather than a pane: the diff is the one part of this that is
---ordinary text a reader wants to scroll, search and yank, and Neovim already
---does all three better than a third list column would. `filetype=diff` gets
---the syntax highlighting for free.
---
---The view closes first, for the same reason `gd` and `gq` close it: the
---floats cover the editor, and putting a buffer *behind* them would be a jump
---to somewhere the reader cannot see.
---@param st table
local function show_diff(st)
  if st.mode ~= "history" or not st.sha then
    notify.warn("gD shows a commit's diff — open one in History mode (5) first")
    return
  end
  local text = st.diff_text
  if not text or vim.trim(text) == "" then
    notify.info("that commit changed nothing outside the generated map")
    return
  end

  local sha = st.sha
  M.close()
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, ("docmap://diff/%s"):format(sha:sub(1, 10)))
end

---`gO` — hand the current position over to the generated HTML page.
---
---The navigator knows mode, center, direction, depth and function; the page's
---whole state lives in its URL fragment. So this is a `format()` and the
---existing opener — and it answers "actually, I want to see that as a
---picture" without hunting for the place again.
---@param st table
local function open_in_browser(st)
  local target = source.norm_root(st.opts.root)
    .. "/"
    .. (st.opts.out_dir or "docs/map")
    .. "/index.html"
  if not (vim.uv or vim.loop).fs_stat(target) then
    notify.warn("no generated page yet — run :LibMap first")
    return
  end

  -- The page has no Structure mode; its equivalent is the Modules hierarchy.
  local view_name = st.mode == "structure" and "modules" or st.mode
  local hash = ("#tab=hierarchy&center=%s&view=%s&dir=%s&depth=%d"):format(
    vim.uri_encode(st.id, "rfc2396"),
    view_name,
    st.dir or "out",
    st.depth or 2
  )
  if st.mode == "calls" and st.fn then
    hash = hash .. "&fn=" .. vim.uri_encode(st.id .. "#" .. st.fn, "rfc2396")
  end

  require("lib.nvim.fs.open.url.system_opener").open(vim.uri_from_fname(target) .. hash)
end

---`/` — fuzzy jump across every module and function in the map.
---@param st table
local function search(st)
  local candidates = {}
  for _, id in ipairs(st.ir.order or {}) do
    local node = st.ir.nodes[id]
    if node then
      candidates[#candidates + 1] = { label = node.module or node.name, id = id }
      for _, fn in ipairs(node.functions or {}) do
        candidates[#candidates + 1] = {
          label = ("%s#%s"):format(node.module or node.name, fn.name),
          id = id,
          fn = fn.name,
        }
      end
    end
  end

  local matches = candidates
  local picker
  picker = kit.picker({
    on_change = function(query)
      matches = {}
      local needle = query:lower()
      for _, c in ipairs(candidates) do
        if needle == "" or c.label:lower():find(needle, 1, true) then
          matches[#matches + 1] = c
        end
      end
      local lines = {}
      for i, c in ipairs(matches) do
        lines[i] = c.label
      end
      picker.set_results(lines)
    end,
    on_submit = function(idx)
      local hit = matches[idx]
      if not hit or not M.is_open() then
        return
      end
      if hit.fn then
        go(st, { mode = "calls", id = hit.id, fn = hit.fn, dir = "out" })
      else
        go(st, { mode = "structure", id = hit.id, fn = CLEAR })
      end
      st.slots.list:focus()
    end,
  })
  if picker then
    local lines = {}
    for i, c in ipairs(candidates) do
      lines[i] = c.label
    end
    picker.set_results(lines)
  end
end

-- ── Keymaps ─────────────────────────────────────────────────────────────────

---@param st table
local function bind(st)
  local mo = { buffer = st.slots.list.bufnr, nowait = true }

  for i, mode in ipairs(MODES) do
    map("n", tostring(i), function()
      if st.mode ~= mode then
        -- Leaving History drops the opened commit: coming back should land on
        -- the list, and a stale `sha` would otherwise make mode `5` reopen a
        -- commit the reader had already navigated away from.
        go(st, { mode = mode, sha = CLEAR })
      end
    end, mo)
  end

  -- j/k stay native so counts and scrolloff behave; CursorMoved drives the
  -- detail pane instead of re-implementing movement.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = st.slots.list.bufnr,
    callback = function()
      if M.is_open() then
        render_detail(st)
      end
    end,
    desc = "lib.nvim.docmap.browse: detail follows the list cursor",
  })

  map("n", "<CR>", function()
    enter(st)
  end, mo)
  for _, key in ipairs({ "-", "<BS>" }) do
    map("n", key, function()
      up(st)
    end, mo)
  end

  map("n", "<C-o>", function()
    history_step(st, -1)
  end, mo)
  map("n", "<C-i>", function()
    history_step(st, 1)
  end, mo)

  -- Same reasoning as the mode keys above: a move that changes nothing must
  -- not become a history stop, or Back appears to stall on it.
  local function set_dir(dir)
    if (st.mode == "deps" or st.mode == "calls") and st.dir ~= dir then
      go(st, { dir = dir })
    end
  end

  map("n", "h", function()
    set_dir("in")
  end, mo)
  map("n", "l", function()
    set_dir("out")
  end, mo)

  -- Depth is a Deps-only axis: `walk_requires` is the only thing that reads
  -- it. Ungated, `+` in Structure or Types pushed a history stop that changed
  -- nothing on screen — and a `<C-o>` that visibly does nothing reads as the
  -- history being broken rather than as the depth key having been a no-op.
  local function set_depth(delta)
    if st.mode ~= "deps" then
      return
    end
    local want = math.max(1, math.min(9, st.depth + delta))
    if want ~= st.depth then
      go(st, { depth = want })
    end
  end

  map("n", "+", function()
    set_depth(1)
  end, mo)
  map("n", "_", function()
    set_depth(-1)
  end, mo)

  map("n", "gd", function()
    goto_source(st)
  end, mo)
  map("n", "gq", function()
    to_quickfix(st)
  end, mo)
  map("n", "gI", function()
    impact_to_quickfix(st)
  end, mo)
  map("n", "gO", function()
    open_in_browser(st)
  end, mo)
  map("n", "gD", function()
    show_diff(st)
  end, mo)
  map("n", "/", function()
    search(st)
  end, mo)

  for _, key in ipairs({ "q", "<Esc>" }) do
    map("n", key, function()
      M.close()
    end, mo)
  end
end

-- ── Entry point ─────────────────────────────────────────────────────────────

---Open the browser.
---@param opts Lib.Docmap.Browse.Opts
---@return boolean opened
function M.open(opts)
  opts = opts or {}
  assert(
    type(opts.root) == "string" and opts.root ~= "",
    "docmap.browse.open: opts.root is required"
  )

  M.close()

  local ir, handle, hint = source.acquire(opts)
  if not ir then
    notify.error(hint or "could not load the map")
    return false
  end

  local group = kit.layout.mount({
    width = opts.width or 0.86,
    height = opts.height or 0.86,
    gap = 0,
    rows = {
      {
        cols = {
          { name = "list", width = opts.list_width or 0.38 },
          { name = "detail", width = 1 - (opts.list_width or 0.38) },
        },
      },
      { name = "status", height = 3 },
    },
  }, {
    theme = opts.theme,
    enter = "list",
    slot = {
      list = { wo = { cursorline = true }, filetype = "lib-docmap-browse-list" },
      detail = { filetype = "lib-docmap-browse-detail" },
      status = { filetype = "lib-docmap-browse-status" },
    },
  })

  if not (group and group.slots.list and group.slots.detail and group.slots.status) then
    if group then
      group.close()
    end
    notify.error("could not mount the browser layout")
    return false
  end

  -- Center on the requested module, else the root.
  --
  -- Resolution goes through `command.find_node` rather than a local
  -- `node.module == name` scan, and that matters for exactly the case a user
  -- is most likely to type: `lua/lib/nvim/fs` is a *namespace* with no
  -- `init.lua`, so it declares no `@module` at all — yet `lib.nvim.fs` is the
  -- name in everyone's head, and namespaces are the aggregation points a
  -- dependency view is most useful at. `find_node` already falls back to the
  -- module path a node's location implies; duplicating that here would mean
  -- re-fixing the same bug in a second place. (It was found here by typing
  -- `:LibBrowse lib.nvim.fs` and silently landing on the root.)
  local center = ir.root
  if opts.center and opts.center ~= "" then
    local found =
      require("lib.nvim.docmap.command").find_node(ir, opts.center, opts.lua_root or "lua")
    if found then
      center = found
    else
      notify.warn(("no module matching '%s' — opening at the root"):format(opts.center))
    end
  end

  state = {
    opts = opts,
    ir = ir,
    handle = handle,
    group = group,
    slots = group.slots,
    mode = opts.mode or "structure",
    id = center,
    fn = nil,
    dir = "out",
    depth = opts.depth or 2,
    cursor = 1,
    entries = {},
    history = {},
    hindex = 1,
    hint = hint,
  }
  -- The trail starts with where we are, not empty: `hindex` always addresses
  -- a real entry, which is what lets `history_step` be a plain bounds check.
  state.history[1] = snapshot(state)

  if handle then
    state.unsubscribe = handle.on_change(function(new_ir)
      if M.is_open() then
        state.ir = new_ir
        -- The centered node can vanish across a rescan (file deleted while
        -- watching); falling back to the root beats rendering an empty pane
        -- with no way out.
        if not state.ir.nodes[state.id] then
          state.id = state.ir.root
          state.fn = nil
        end
        render(state)
      end
    end)
  end

  bind(state)
  render(state)
  return true
end

---Toggle: open when closed, close when open.
---@param opts Lib.Docmap.Browse.Opts
function M.toggle(opts)
  if M.is_open() then
    M.close()
  else
    M.open(opts)
  end
end

return M
