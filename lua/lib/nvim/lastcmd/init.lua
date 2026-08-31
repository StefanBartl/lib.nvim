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
--- **Experimental, and off unless asked for.** The tracker sees every keypress
--- in the session, so it does not install itself just because the library is
--- on the runtimepath. `opts.experimental` is the opt-in, and it also carries
--- the key, because the module binds the trigger itself -- see `M.setup`.
---
--- Usage:
--- ```lua
--- require("lib.nvim.lastcmd").setup({ experimental = true })      -- default lhs
--- require("lib.nvim.lastcmd").setup({ experimental = "<M-r>" })   -- your own
--- ```
---
--- `3<M-Right>` then `5j` then the trigger re-runs `3<M-Right>`. A later
--- `<M-c>` then `jjj` then the trigger re-runs `<M-c>`. A native `dw` in
--- between wins over both, because it happened last.

require("lib.nvim.lastcmd.@types")

local selection = require("lib.nvim.selection")

local M = {}

--- Default trigger, used when `experimental = true` rather than a string.
---
--- Deliberately *not* `<C-#>`: outside the kitty keyboard protocol a terminal
--- has no encoding for Ctrl with a non-alphabetic key, so it sends a bare `#`
--- and the mapping can never fire. `<M-.>` survives the legacy ESC-prefix
--- encoding every terminal implements, and keeps `.`'s "repeat" mnemonic.
---
--- That reasoning is now a module: `bindings.keymap.portability` classifies
--- any `lhs` the same way (`<C-#>` fragile, `<M-.>` common), and
--- `bindings.audit.key_risks` reports which registered actions still rest on
--- one -- so the next such choice does not depend on someone remembering
--- this comment.
---@see lib.nvim.bindings.keymap.portability
local DEFAULT_LHS = "<M-.>"

--- Modes the trigger is bound in. Visual is included because Visual-mode
--- mappings are tracked (by selection shape) and must be replayable.
local TRIGGER_MODES = { "n", "x" }

--- Mapped keys that are pure motions, so they never become "the last
--- command". Unmapped motions need no entry -- they match no mapping, and
--- they never move `changedtick`, so both halves already ignore them. This
--- list only matters when something has actually *mapped* one of these.
-- stylua: ignore
-- Grouped by kind, one family per line: stylua would spread this to 34 lines
-- and lose exactly the grouping that makes it reviewable.
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

--- Entry recorded by `on_key` but not yet promoted to `last`.
---
--- `on_key` runs *before* the mapping's rhs, so at the moment the trigger's
--- own keys are read it looks like any other mapping and would overwrite
--- `last` with itself -- after which `repeat_last` replays the trigger, which
--- replays the trigger, forever. Promotion is therefore deferred by one
--- `vim.schedule` tick, which puts it *after* the rhs has run, and
--- `repeat_last` cancels whatever is in flight when it starts. That holds for
--- any lhs and any wrapper around `repeat_last`, which comparing the resolved
--- callback against `M.repeat_last` did not: the documented binding wraps it
--- in a closure, so the identity never matched and the runaway was reachable
--- from the README's own example.
---@type Lib.Lastcmd.Entry|nil
local pending = nil

--- The lhs `setup` bound the trigger to, so `teardown` can remove exactly
--- that and a re-`setup` with a different key does not leave the old one.
---@type string|nil
local installed_lhs = nil

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
---@param mode "mt"|"m"|"n" `mt` = remapped *and* counted as typed (see `replay`)
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
  -- the mapping again -- and "t" so they count as *typed*.
  --
  -- "t" is load-bearing, not cosmetic. `on_key`'s second argument is empty
  -- for keys fed without it, and this module ignores those, so a replay fed
  -- with "m" alone is invisible to the tracker: `seen` never gets credited
  -- with the edit the replay just made, that edit reads as a native change on
  -- the next repeat, and every repeat after the first silently falls through
  -- to `normal! .`. With "t" the replay re-enters `on_key`, re-records the
  -- same entry and refreshes `seen`, which keeps the arbitration consistent
  -- without a second bookkeeping path.
  feed(entry.count .. entry.keys, "mt")
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
  pending = entry

  -- `on_key` runs *before* the mapping's callback, so both halves of this are
  -- only knowable a tick later: the post-mapping tick, and whether the key
  -- turned out to be the repeat trigger (which cancels `pending` from its
  -- rhs). Crediting the mapping with the change it is about to make is what
  -- stops that change from later reading as a native one.
  vim.schedule(function()
    if pending ~= entry then
      return -- superseded, or cancelled by `repeat_last`
    end
    pending = nil
    last = entry
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
    -- The repeat trigger is not special-cased here: it records like anything
    -- else and its rhs cancels the record before it is promoted (see
    -- `pending`). Its lhs is on the ignore list too, which costs nothing and
    -- covers a trigger whose rhs defers before calling `repeat_last`.
    if not ignore[cand] then
      record(cand, mapmode, realmode)
    end
    seq, count = "", ""
  elseif prefix then
    seq = cand
  else
    seq, count = "", ""
  end
end

---Remove the trigger this module bound, if any.
local function unbind()
  if installed_lhs then
    for _, mode in ipairs(TRIGGER_MODES) do
      pcall(vim.keymap.del, mode, installed_lhs)
    end
    installed_lhs = nil
  end
end

---Bind the trigger, through `lib.nvim.bindings.keymap` so it lands in the
---keymap registry like every other binding and `conflicts()` can see it.
---Required lazily: this module is loadable without the bindings tree.
---@param lhs string
---@return boolean ok
local function bind(lhs)
  local ok, err = pcall(function()
    require("lib.nvim.bindings.keymap").set(TRIGGER_MODES, lhs, function()
      M.repeat_last()
    end, { silent = true }, "repeat last real command (lib.nvim.lastcmd)")
  end)
  if not ok then
    vim.notify(
      "lib.nvim.lastcmd: could not bind " .. lhs .. ": " .. tostring(err),
      vim.log.levels.WARN
    )
    return false
  end
  installed_lhs = lhs
  return true
end

---Turn the feature on, and bind its trigger.
---
---Opt-in on purpose. The tracker is a session-wide `vim.on_key` listener and
---the arbitration is new, so nothing happens until `opts.experimental` says
---so:
---
---  * `nil`/`false` -- off. An earlier `setup` is undone, so this is also how
---    you switch it back off at runtime.
---  * `true` -- on, bound to the default lhs (`<M-.>`).
---  * `"<lhs>"` -- on, bound to that key instead.
---
---Idempotent: calling it again re-reads `opts`, re-binds only if the key
---changed, and never stacks a second `on_key` handler.
---@param opts? Lib.Lastcmd.Opts
---@return boolean enabled
function M.setup(opts)
  opts = opts or {}

  local exp = opts.experimental
  if exp ~= nil and exp ~= false and exp ~= true and type(exp) ~= "string" then
    vim.notify(
      "lib.nvim.lastcmd: `experimental` must be true, false or a keymap lhs, got " .. type(exp),
      vim.log.levels.WARN
    )
    exp = false
  end

  if not exp then
    M.teardown()
    return false
  end

  local lhs = type(exp) == "string" and exp or DEFAULT_LHS
  if lhs == "" then
    vim.notify(
      "lib.nvim.lastcmd: `experimental` is an empty string, expected a keymap lhs",
      vim.log.levels.WARN
    )
    M.teardown()
    return false
  end

  ignore = {}
  if opts.motions ~= false then
    for _, k in ipairs(DEFAULT_IGNORE) do
      ignore[k] = true
    end
  end
  for _, k in ipairs(opts.ignore or {}) do
    ignore[k] = true
  end
  ignore[lhs] = true

  if installed_lhs ~= lhs then
    unbind()
    if not bind(lhs) then
      M.teardown()
      return false
    end
  end

  if not ns then
    ns = vim.on_key(on_key)
  end
  return true
end

---Remove the key tracker and the trigger this module bound.
function M.teardown()
  if ns then
    vim.on_key(nil, ns)
    ns = nil
  end
  unbind()
  seq, count = "", ""
  pending = nil
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
  -- Whatever key got us here is mid-record; cancel it before reading `last`,
  -- or the trigger becomes the thing it repeats.
  pending = nil

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
  local ok = pcall(function()
    vim.cmd("normal! .")
  end)
  return ok
end

---@return Lib.Lastcmd.Entry|nil
function M.peek()
  return last
end

---Forget the recorded mapping and all per-buffer tick bookkeeping.
function M.clear()
  last = nil
  pending = nil
  seq, count = "", ""
  seen = {}
end

---The lhs the trigger is currently bound to, or `nil` when off.
---@return string|nil
function M.trigger_key()
  return installed_lhs
end

---@type Lib.Lastcmd
return M
