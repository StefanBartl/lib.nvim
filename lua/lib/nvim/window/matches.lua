---@module 'lib.nvim.window.matches'
--- A ledger for window-local matches (`matchadd()` / `matchdelete()`): `window -> { name -> match id }`, so a
--- caller names its highlights and never keeps match ids itself.
---
--- A match belongs to ONE window and survives buffer changes in it, which is why plugins that highlight with
--- `matchadd` end up keeping a table `win -> id` and a cleanup for windows that went away. This is that table.
---
--- Generalised from the bookkeeping of `spotlight.nvim`. Each plugin makes its own ledger with `new()`, so two
--- plugins never delete each other's matches.
---
--- ```lua
--- local ledger = require("lib.nvim.window.matches").new()
---
--- ledger:add(win, "cursorword", "Search", [[\<foo\>]], { priority = 5 })
--- ledger:has(win, "cursorword")      --> true
--- ledger:add(win, "cursorword", "Search", [[\<bar\>]]) -- replaces the previous one under that name
--- ledger:remove(win, "cursorword")
--- ledger:clear(win)                  -- every match of this window
--- ledger:clear_all()                 -- every match of every window
--- ```

local api = vim.api
local fn = vim.fn

local M = {}

---@class Lib.Window.Matches.Opts
---@field priority? integer  # `matchadd` priority (default 10).
---@field conceal? string    # A conceal character for the match.

---@class Lib.Window.Matches.Ledger
---@field private by_win table<integer, table<string, integer>>
local Ledger = {}
Ledger.__index = Ledger

---@param name any
---@return boolean
local function valid_name(name)
  return type(name) == "string" and name ~= ""
end

---Forget windows that no longer exist (their matches went with them).
---@private
function Ledger:_prune()
  for win in pairs(self.by_win) do
    if not api.nvim_win_is_valid(win) then
      self.by_win[win] = nil
    end
  end
end

---@private
---@param win integer
---@param name string
---@return boolean removed
function Ledger:_delete(win, name)
  local ids = self.by_win[win]
  local id = ids and ids[name]
  if not id then
    return false
  end
  ids[name] = nil
  if next(ids) == nil then
    self.by_win[win] = nil
  end
  -- (somebody else may have removed it already: `matchdelete` then errors, which is fine)
  pcall(fn.matchdelete, id, win)
  return true
end

---@private
---@param win integer
---@param name string
---@param id integer
function Ledger:_store(win, name, id)
  self.by_win[win] = self.by_win[win] or {}
  self.by_win[win][name] = id
end

---@param win any
---@param name any
---@return string|nil err
local function bad_args(win, name)
  if type(win) ~= "number" or not api.nvim_win_is_valid(win) then
    return "invalid window"
  end
  if not valid_name(name) then
    return "a match needs a non-empty name"
  end
  return nil
end

---Add (or replace, under the same name) a match for `pattern` in `win`.
---@param win integer
---@param name string
---@param group string   # Highlight group.
---@param pattern string
---@param opts? Lib.Window.Matches.Opts
---@return integer|nil match_id
---@return string|nil err
function Ledger:add(win, name, group, pattern, opts)
  local err = bad_args(win, name)
  if err then
    return nil, err
  end
  self:_prune()
  local args = { priority = 10 }
  if opts and opts.priority then
    args.priority = opts.priority
  end
  local extra = { window = win }
  if opts and opts.conceal then
    extra.conceal = opts.conceal
  end
  local ok, id = pcall(fn.matchadd, group, pattern, args.priority, -1, extra)
  if not ok then
    return nil, tostring(id)
  end
  -- the old one goes only after the new one exists: a bad pattern keeps the previous highlight
  self:_delete(win, name)
  self:_store(win, name, id)
  return id, nil
end

---Add (or replace) a match for explicit positions (`matchaddpos`).
---@param win integer
---@param name string
---@param group string
---@param positions (integer|integer[])[]  # `{ line }`, `{ line, col }` or `{ line, col, len }` entries.
---@param opts? Lib.Window.Matches.Opts
---@return integer|nil match_id
---@return string|nil err
function Ledger:add_pos(win, name, group, positions, opts)
  local err = bad_args(win, name)
  if err then
    return nil, err
  end
  self:_prune()
  local extra = { window = win }
  if opts and opts.conceal then
    extra.conceal = opts.conceal
  end
  local ok, id = pcall(fn.matchaddpos, group, positions, (opts and opts.priority) or 10, -1, extra)
  if not ok then
    return nil, tostring(id)
  end
  self:_delete(win, name)
  self:_store(win, name, id)
  return id, nil
end

---Remove one named match of a window.
---@param win integer
---@param name string
---@return boolean removed  # false when there was none under that name
function Ledger:remove(win, name)
  if not valid_name(name) then
    return false
  end
  self:_prune()
  return self:_delete(win, name)
end

---Remove every match this ledger holds for `win`.
---@param win integer
---@return integer count
function Ledger:clear(win)
  local ids = self.by_win[win]
  if not ids then
    return 0
  end
  local names = vim.tbl_keys(ids)
  for _, name in ipairs(names) do
    self:_delete(win, name)
  end
  return #names
end

---Remove every match of every window.
---@return integer count
function Ledger:clear_all()
  local count = 0
  for win in pairs(vim.deepcopy(self.by_win)) do
    count = count + self:clear(win)
  end
  self.by_win = {}
  return count
end

---Whether `win` has a match under `name` (a match somebody removed behind the ledger's back counts as gone).
---@param win integer
---@param name string
---@return boolean
function Ledger:has(win, name)
  local id = self.by_win[win] and self.by_win[win][name]
  if not id or not api.nvim_win_is_valid(win) then
    return false
  end
  for _, m in ipairs(fn.getmatches(win)) do
    if m.id == id then
      return true
    end
  end
  -- gone behind our back: forget it
  self.by_win[win][name] = nil
  return false
end

---The matches of a window: `name -> match id`.
---@param win integer
---@return table<string, integer>
function Ledger:list(win)
  self:_prune()
  local out = {}
  for name in pairs(self.by_win[win] or {}) do
    if self:has(win, name) then
      out[name] = self.by_win[win][name]
    end
  end
  return out
end

---A new, empty ledger.
---@return Lib.Window.Matches.Ledger
function M.new()
  return setmetatable({ by_win = {} }, Ledger)
end

return M
