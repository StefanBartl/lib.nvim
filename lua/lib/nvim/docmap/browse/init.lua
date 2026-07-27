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
---
--- Keys: 1..4 modes · j/k move · <CR> descend · -/<BS> up · <C-o>/<C-i>
--- history · h/l direction · +/_ depth · gd source · gq quickfix · / search
--- · q close.

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

local MODES = { "structure", "deps", "calls", "types" }

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
  }
end

local SNAP_KEYS = { "mode", "id", "fn", "dir", "depth", "cursor" }

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
    st[k] = v
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

  if e.kind == "node" and e.id then
    -- In deps/calls, following an edge re-centers on the far node while
    -- keeping the mode — that *is* "follow the edge".
    go(st, { id = e.id, fn = nil })
  elseif e.kind == "function" and e.id and e.fn then
    go(st, { mode = "calls", id = e.id, fn = e.fn, dir = "out" })
  end
end

---@param st table
local function up(st)
  if st.fn then
    go(st, { fn = nil, mode = st.mode == "calls" and "structure" or st.mode })
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
        go(st, { mode = "structure", id = hit.id, fn = nil })
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
        go(st, { mode = mode })
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

  map("n", "h", function()
    if st.mode == "deps" or st.mode == "calls" then
      go(st, { dir = "in" })
    end
  end, mo)
  map("n", "l", function()
    if st.mode == "deps" or st.mode == "calls" then
      go(st, { dir = "out" })
    end
  end, mo)

  map("n", "+", function()
    go(st, { depth = math.min(9, st.depth + 1) })
  end, mo)
  map("n", "_", function()
    go(st, { depth = math.max(1, st.depth - 1) })
  end, mo)

  map("n", "gd", function()
    goto_source(st)
  end, mo)
  map("n", "gq", function()
    to_quickfix(st)
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
    mode = "structure",
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
