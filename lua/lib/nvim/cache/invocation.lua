---@module 'lib.nvim.cache.invocation'
--- A cache that lives for the duration of one call: values computed inside `scope:run(fn)` are remembered until
--- the outermost `run` returns, then dropped. Outside a `run` nothing is remembered, so a producer is simply
--- called through.
---
--- The typical user is a command that asks the editor the same question from several nested helpers -- where
--- is the cursor, what is under it, what is selected -- and wants every helper to see ONE reading, without
--- passing a table down through every signature. Generalised from open.nvim's `context.with_cache`.
---
--- ```lua
--- local scope = require("lib.nvim.cache.invocation").new("open")
---
--- scope:run(function()
---   local a = scope:editor_state()   -- reads the editor
---   local b = scope:editor_state()   -- the same table, no second read
--- end)
--- ```
---
--- Storage is a `lib.nvim.cache.memory` namespace (`invocation:<name>`), so `:Lib cache stats` shows it. It is
--- emptied when the outermost `run` ends, whether `fn` returned or raised.

local memory = require("lib.nvim.cache.memory")

local M = {}

---@class Lib.Cache.Invocation.EditorState
---@field buf integer
---@field win integer
---@field mode string                 # `vim.fn.mode()` at the time of the reading.
---@field cursor integer[]            # `{ row (1-based), col (0-based) }` of the current window.
---@field cfile string|nil            # `<cfile>`, nil when empty.
---@field cword string|nil            # `<cWORD>`, nil when empty.
---@field selection string|nil        # The text of the active visual selection (lines joined by "\n"), else nil.
---@field buffer_path string|nil      # Name of the current buffer, nil when it has none.

---@class Lib.Cache.Invocation.Scope
---@field private name string
---@field private depth integer
---@field private ns Lib.Cache.Memory.Namespace
local Scope = {}
Scope.__index = Scope

---A new, independent scope. Two scopes never see each other's values, even with the same `name`
---(the name only labels the stats namespace).
---@param name string
---@return Lib.Cache.Invocation.Scope
function M.new(name)
  vim.validate("name", name, "string")
  return setmetatable(
    { name = name, depth = 0, ns = memory.namespace("invocation:" .. name) },
    Scope
  )
end

---Whether a `run` is in progress, i.e. whether `memo` remembers anything right now.
---@return boolean
function Scope:active()
  return self.depth > 0
end

---Run `fn(...)` with the cache switched on. Nested runs share the outer one's values; the values are dropped
---when the outermost run ends. An error in `fn` is re-raised unchanged after the cleanup.
---@param fn fun(...): any
---@param ... any
---@return any ...
function Scope:run(fn, ...)
  self.depth = self.depth + 1
  local results = vim.F.pack_len(pcall(fn, ...))
  self.depth = self.depth - 1
  if self.depth == 0 then
    self.ns.clear()
  end
  if not results[1] then
    error(results[2], 0)
  end
  return select(2, vim.F.unpack_len(results))
end

---Return the value stored under `key`, calling `produce()` once to fill it. `nil` and `false` are remembered
---too. Outside a `run` this is just `produce()`. A producer that raises stores nothing.
---@param key string
---@param produce fun(): any
---@return any
function Scope:memo(key, produce)
  if self.depth == 0 then
    return produce()
  end
  local box = self.ns.get(key)
  if box then
    return box.value
  end
  local value = produce()
  self.ns.set(key, { value = value })
  return value
end

---Read the editor state now, without any caching.
---@return Lib.Cache.Invocation.EditorState
function M.read_editor_state()
  local state = {
    buf = vim.api.nvim_get_current_buf(),
    win = vim.api.nvim_get_current_win(),
    mode = vim.fn.mode(),
    cursor = vim.api.nvim_win_get_cursor(0),
  }
  local cfile = vim.fn.expand("<cfile>")
  state.cfile = cfile ~= "" and cfile or nil
  local cword = vim.fn.expand("<cWORD>")
  state.cword = cword ~= "" and cword or nil
  local name = vim.api.nvim_buf_get_name(0)
  state.buffer_path = name ~= "" and name or nil

  -- Only a LIVE selection: the '< '> marks outlive the visual mode and would hand back text nobody has
  -- selected any more.
  local mode = state.mode
  if mode == "v" or mode == "V" or mode == string.char(22) then
    local ok, lines =
      pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    if ok and type(lines) == "table" and #lines > 0 then
      local text = table.concat(lines, "\n")
      state.selection = text ~= "" and text or nil
    end
  end
  return state
end

---`M.read_editor_state()`, read once per `run`: every caller inside the same run gets the same table.
---Do not mutate it.
---@return Lib.Cache.Invocation.EditorState
function Scope:editor_state()
  return self:memo("editor_state", M.read_editor_state)
end

return M
