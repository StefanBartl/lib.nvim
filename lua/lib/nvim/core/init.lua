---@module 'lib.nvim.core'
--- Executable-on-PATH lookups (memoized) plus lib.nvim.core's own aggregated
--- helpers, e.g. simple_echo.

local lazy = require("lib.lua.lazy")

local M = {}

local exec_cache = {} ---@type table<string, boolean>

---@param bin string
---@return boolean
function M.has_exec(bin)
  local cached = exec_cache[bin]
  if cached == nil then
    cached = vim.fn.executable(bin) == 1
    exec_cache[bin] = cached
  end
  return cached
end

---Return the first candidate binary found on PATH, or nil if none are.
---Results of `has_exec` are memoized per binary name.
---@param candidates string[]
---@return string|nil
function M.first_available(candidates)
  for _, bin in ipairs(candidates) do
    if M.has_exec(bin) then
      return bin
    end
  end
  return nil
end

---Drop `bin`'s memoized `has_exec` result, so the next call re-probes PATH.
---For the one legitimate case where "not found" can go stale within a
---session: something installed `bin` after `has_exec` first cached it —
---`lib.nvim.deps.view`'s inline install flips a tool's status line from
---`[missing]` to `[ok]` this way once its install finishes. Not needed for
---the opposite direction (PATH losing a binary mid-session is not a case
---any known caller re-checks).
---@param bin string
function M.forget_exec(bin)
  exec_cache[bin] = nil
end

M.simple_echo = lazy.require("lib.nvim.core.simple_echo")

---@type Lib.Nvim
return M
