---@module 'lib.nvim.lastcmd'
--- Repeat the last *real* command -- mapping or native change -- skipping
--- pure motions. Nothing has to be wrapped: the tracker watches the key
--- stream and the buffer, so any mapping (yours, a plugin's, a built-in)
--- participates without cooperating.
---
--- Why this exists: native `.` cannot repeat a Lua-callback mapping. `.`
--- replays the *recorded keystrokes* of a change, and a mapping whose rhs is
--- a Lua function edits the buffer through the API, which never touches the
--- redo machinery. Pressing `.` after such a mapping therefore silently
--- replays some older, unrelated change rather than doing nothing -- which is
--- worse than failing.
---
--- Two trackers, one arbiter:
---
--- * **Mappings** are read off the key stream via `vim.on_key`, which reports
---   the keys as *typed* (`3`, `<M-Right>`). A sequence is resolved against
---   the keymap table -- `maparg` non-empty means an exact mapping, `mapcheck`
---   non-empty means it is still a prefix of a longer one -- so multi-key
---   mappings like `<leader>ct` are handled without guessing.
--- * **Native changes** are not parsed at all. Vim already knows what the
---   last native change was, and `.` replays it correctly; reimplementing
---   Vim's normal-mode grammar in Lua to re-derive that would be a thousand
---   lines that are never quite right. So the only question asked is *did the
---   buffer change after the last mapping ran*, answered with `changedtick`.
---
--- Whichever is more recent wins: a tracked mapping is replayed by feeding
--- its keys, a native change by running `normal! .`.
---
--- Motion filtering falls out of both halves rather than needing a parser:
--- motions do not change text, so they never move `changedtick`, and an
--- unmapped motion key never matches `maparg`. Only a *mapped* key that
--- happens to be a motion needs naming, which is what `DEFAULT_IGNORE` and
--- `opts.ignore` are for.
---
--- Usage:
--- ```lua
--- require("lib.nvim.lastcmd").setup()
--- vim.keymap.set({ "n", "x" }, "<leader>.", function()
---   require("lib.nvim.lastcmd").repeat_last()
--- end, { desc = "repeat last real command" })
--- ```
---
--- `3<M-Right>` then `5j` then `<leader>.` re-runs `3<M-Right>`. A later
--- `<M-c>` then `jjj` then `<leader>.` re-runs `<M-c>`. A native `dw` in
--- between wins over both, because it happened last.

require("lib.nvim.lastcmd.@types")

local selection = require("lib.nvim.selection")

local M = {}

--- Mapped keys that are pure motions, so they never become "the last
--- command". Unmapped motions need no entry -- they match no mapping, and
--- they never move `changedtick`, so both halves already ignore them. This
--- list only matters when something has actually *mapped* one of these.
local DEFAULT_IGNORE = {
  "h", "j", "k", "l",
  "<Left>", "<Right>", "<Up>", "<Down>",
  "w", "W", "b", "B", "e", "E", "ge", "gE",
  "0", "^", "$", "g_",
  "gg", "G", "H", "M", "L",
  "{", "}", "(", ")", "[[", "]]",
  "%", "n", "N", ";", ",",
  "<C-d>", "<C-u>", "<C-f>", "<C-b>",
  "<PageUp>", "<PageDown>", "<Home>", "<End>",
}

---@type table<string, true>
local ignore = {}

--- Pending key sequence, in `keytrans` notation, excluding its count prefix.
local seq = ""
--- Pending count prefix, exactly as typed.
local count = ""

---@type Lib.Lastcmd.Entry|nil
local last = nil

--- `changedtick` already accounted for, per buffer. A tick above the stored
--- value means the buffer changed without a mapping of ours being credited
--- for it -- i.e. a native change, and a more recent one than `last`.
---@type table<integer, integer>
local seen = {}

---@type integer|nil
local ns = nil

---Buffer-safe `changedtick` read.
---@param buf integer
---@return integer
local function tick_of(buf)
  local ok, tick = pcall(vim.api.nvim_buf_get_changedtick, buf)
  return ok and tick or 0
end

---Capture the current Visual selection's *shape* (not its position), so the
---replay can rebuild an equally sized one wherever the cursor then is.
---
---`{count}v` looks like it would do this and does not: it forces charwise,
---so a linewise selection comes back as a single character. The shape is
---therefore measured here and rebuilt through `lib.nvim.selection`.
---@param realmode string
---@return Lib.Lastcmd.Visual|nil
local function capture_visual(realmode)
  if realmode == "V" then
    local srow, erow = selection.lines()
    if srow and erow then
      return { kind = "V", lines = erow - srow + 1 }
    end
  elseif realmode == "v" then
    local row, scol, ecol = selection.chars()
    if row then
      return { kind = "v", cols = ecol - scol }
    end
    local srow, scol2, erow, ecol2 = selection.chars_multiline()
    if srow then
      return { kind = "v", rows = erow - srow, scol = scol2, ecol = ecol2 }
    end
  else
    -- Blockwise. `selection` has no blockwise capture, so the span is read
    -- off the visual marks directly and rebuilt with plain motions below.
    local srow, erow = selection.lines()
    if srow and erow then
      local a = vim.fn.col("v")
      local b = vim.fn.col(".")
      return { kind = "b", lines = erow - srow + 1, cols = math.abs(b - a) }
    end
  end
  return nil
end

---@param keys string
---@param mode "m"|"n"
local function feed(keys, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode, false)
end

---Rebuild a selection of the recorded shape, anchored at the cursor.
---@param vis Lib.Lastcmd.Visual
---@return boolean ok
local function restore_visual(vis)
  local pos = vim.api.nvim_win_get_cursor(0)
  local row0, col0 = pos[1] - 1, pos[2]
  local lines = vim.api.nvim_buf_line_count(0)

  if vis.kind == "V" then
    local erow = math.min(row0 + (vis.lines or 1) - 1, lines - 1)
    selection.reselect_lines(row0, erow)
    return true
  end

  if vis.kind == "v" then
    if vis.cols then
      selection.reselect_chars(row0, col0, col0 + vis.cols)
      return true
    end
    local erow = math.min(row0 + (vis.rows or 0), lines - 1)
    selection.reselect_chars_multiline(row0, vis.scol or col0, erow, vis.ecol or col0)
    return true
  end

  -- Blockwise: no `selection` counterpart, so drive it with motions.
  local down = (vis.lines or 1) - 1
  local right = vis.cols or 0
  feed("<C-v>" .. (down > 0 and (down .. "j") or "") .. (right > 0 and (right .. "l") or ""), "n")
  return true
end

---@param entry Lib.Lastcmd.Entry
local function replay(entry)
  if entry.mode == "x" and entry.visual then
    restore_visual(entry.visual)
  end
  -- "m" so the fed keys go through mappings -- the whole point is to trigger
  -- the mapping again. This also re-enters `on_key`, which re-records the
  -- same entry and refreshes `seen`, keeping the arbitration consistent
  -- without a second bookkeeping path.
  feed(entry.count .. entry.keys, "m")
end

---@param keys string
---@param mapmode "n"|"x"
---@param realmode string
local function record(keys, mapmode, realmode)
  ---@type Lib.Lastcmd.Entry
  local entry = { keys = keys, count = count, mode = mapmode }
  if mapmode == "x" then
    entry.visual = capture_visual(realmode)
  end
  last = entry

  -- `on_key` runs *before* the mapping's callback, so the post-mapping tick
  -- is only knowable a tick later. Crediting the mapping with the change it
  -- is about to make is what stops that change from later reading as a
  -- native one.
  vim.schedule(function()
    local buf = vim.api.nvim_get_current_buf()
    seen[buf] = tick_of(buf)
  end)
end

---@param typed string|nil
local function on_key(_, typed)
  if typed == nil or typed == "" then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  if seen[buf] == nil then
    -- First time this buffer is seen: adopt its current tick, so pre-existing
    -- content is not mistaken for a change that happened after `last`.
    seen[buf] = tick_of(buf)
  end

  local realmode = vim.fn.mode()
  local base = realmode:sub(1, 1)
  ---@type "n"|"x"|nil
  local mapmode
  if base == "n" then
    mapmode = "n"
  elseif base == "v" or base == "V" or base == "\22" then
    mapmode = "x"
  else
    -- Insert, cmdline, terminal, operator-pending: not tracked. Native `.`
    -- already repeats insert-mode edits correctly, and a half-typed command
    -- is not a command yet.
    seq, count = "", ""
    return
  end

  local ok, t = pcall(vim.fn.keytrans, typed)
  if not ok or t == "" then
    seq, count = "", ""
    return
  end

  -- Leading count. `0` is a motion on its own but a digit inside a count.
  if seq == "" and (t:match("^[1-9]$") or (count ~= "" and t == "0")) then
    count = count .. t
    return
  end

  local cand = seq .. t
  local map = vim.fn.maparg(cand, mapmode, false, true)
  local exact = type(map) == "table" and next(map) ~= nil
  local prefix = vim.fn.mapcheck(cand, mapmode) ~= ""

  if exact then
    -- Never record the repeat key itself -- that would make it replay
    -- itself forever. Identity is checked against the resolved callback, so
    -- this holds whatever lhs the user chose and needs no configuration.
    local is_self = type(map) == "table" and map.callback == M.repeat_last
    if not is_self and not ignore[cand] then
      record(cand, mapmode, realmode)
    end
    seq, count = "", ""
  elseif prefix then
    seq = cand
  else
    seq, count = "", ""
  end
end

---Install the key tracker. Idempotent -- calling it again re-reads `opts`
---rather than stacking a second handler.
---@param opts? Lib.Lastcmd.Opts
function M.setup(opts)
  opts = opts or {}

  ignore = {}
  if opts.motions ~= false then
    for _, k in ipairs(DEFAULT_IGNORE) do
      ignore[k] = true
    end
  end
  for _, k in ipairs(opts.ignore or {}) do
    ignore[k] = true
  end

  if ns then
    return
  end
  ns = vim.on_key(on_key)
end

---Remove the key tracker.
function M.teardown()
  if ns then
    vim.on_key(nil, ns)
    ns = nil
  end
  seq, count = "", ""
end

---@return boolean
function M.enabled()
  return ns ~= nil
end

---Re-run the last real command.
---
---A tracked mapping wins unless the buffer changed after it ran, in which
---case that native change is the more recent real command and `.` repeats
---it. Motions move neither, so they never decide this.
---@return boolean ran
function M.repeat_last()
  local buf = vim.api.nvim_get_current_buf()
  local accounted = seen[buf]
  local native_newer = accounted ~= nil and tick_of(buf) > accounted

  if last and not native_newer then
    replay(last)
    return true
  end

  -- Deliberately does not refresh `seen`: the native change stays the most
  -- recent real command until a tracked mapping actually runs again, so a
  -- second repeat repeats it too.
  local ok = pcall(vim.cmd, "normal! .")
  return ok
end

---@return Lib.Lastcmd.Entry|nil
function M.peek()
  return last
end

---Forget the recorded mapping and all per-buffer tick bookkeeping.
function M.clear()
  last = nil
  seq, count = "", ""
  seen = {}
end

---@type Lib.Lastcmd
return M
