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
--- **A run belongs to the coroutine that started it.** `fn` may yield (async code): when it is resumed later it
--- still sees its own values, while code running meanwhile on the main thread or in another coroutine neither
--- sees them nor ends them. The reverse holds too: a coroutine spawned INSIDE a run does not share its values
--- (its `memo` calls through). A run whose coroutine is abandoned is garbage-collected with it.
---
--- Each scope keeps its values in a table of its own (two scopes never see each other's, whatever their name);
--- they are therefore not affected by `lib.nvim.cache.memory`'s auto-invalidation and do not show up in
--- `:Lib cache stats`.

local M = {}

--- State key of the main thread (`coroutine.running()` is nil there on LuaJIT, a main flag on 5.2+).
local MAIN = {}
--- Private key of the editor-state reading: a user `memo` key can never collide with it.
local EDITOR_STATE = {}

---@class Lib.Cache.Invocation.EditorState
---@field buf integer
---@field win integer
---@field mode string                 # `vim.fn.mode()` at the time of the reading.
---@field cursor integer[]            # `{ row (1-based), col (0-based) }` of the current window.
---@field cfile string|nil            # `<cfile>`, nil when empty.
---@field cword string|nil            # `<cWORD>`, nil when empty.
---@field selection string|nil        # The text of the active visual or select-mode selection (lines joined by "\n"), else nil.
---@field buffer_path string|nil      # Name of the current buffer, nil when it has none.

---@class Lib.Cache.Invocation.Scope
---@field private name string
---@field private states table<any, { depth: integer, values: table }>
local Scope = {}
Scope.__index = Scope

---A new, independent scope. Two scopes never see each other's values, even with the same `name`
---(the name only labels it).
---@param name string
---@return Lib.Cache.Invocation.Scope
function M.new(name)
  vim.validate("name", name, "string")
  return setmetatable({ name = name, states = setmetatable({}, { __mode = "k" }) }, Scope)
end

---@private
---@return any key
local function thread_key()
  local co, is_main = coroutine.running()
  if not co or is_main then
    return MAIN
  end
  return co
end

---Whether a `run` of the calling coroutine is in progress, i.e. whether `memo` remembers anything right now.
---@return boolean
function Scope:active()
  local st = self.states[thread_key()]
  return st ~= nil and st.depth > 0
end

---Run `fn(...)` with the cache switched on. Nested runs (in the same coroutine) share the outer one's values;
---the values are dropped when the outermost run ends. An error in `fn` is re-raised unchanged after the cleanup.
---@param fn fun(...): any
---@param ... any
---@return any ...
function Scope:run(fn, ...)
  local key = thread_key()
  local st = self.states[key]
  if not st then
    st = { depth = 0, values = {} }
    self.states[key] = st
  end
  st.depth = st.depth + 1
  local results = vim.F.pack_len(pcall(fn, ...))
  st.depth = st.depth - 1
  if st.depth == 0 then
    self.states[key] = nil
  end
  if not results[1] then
    error(results[2], 0)
  end
  return select(2, vim.F.unpack_len(results))
end

---@private
---@param key any
---@param produce fun(): any
---@return any
function Scope:_memo(key, produce)
  local st = self.states[thread_key()]
  if not st or st.depth == 0 then
    return produce()
  end
  local box = st.values[key]
  if box then
    return box.value
  end
  local value = produce()
  st.values[key] = { value = value }
  return value
end

---Return the value stored under `key`, calling `produce()` once to fill it. `nil` and `false` are remembered
---too. Outside a `run` this is just `produce()`. A producer that raises stores nothing.
---@param key string
---@param produce fun(): any
---@return any
function Scope:memo(key, produce)
  vim.validate("key", key, "string")
  vim.validate("produce", produce, "function")
  return self:_memo(key, produce)
end

--- Region type for `getregion()` by mode: visual and select mode (`s` is `v` with a different keymap, and so on).
local REGION_TYPE = {
  v = "v",
  V = "V",
  [string.char(22)] = string.char(22),
  s = "v",
  S = "V",
  [string.char(19)] = string.char(22),
}

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
  -- selected any more. (A `:` command typed from visual mode runs in normal mode: no selection then.)
  local region_type = REGION_TYPE[state.mode]
  if region_type then
    local ok, lines =
      pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = region_type })
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
  return self:_memo(EDITOR_STATE, M.read_editor_state)
end

return M
