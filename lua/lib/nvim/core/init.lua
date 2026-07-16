---@module 'lib.nvim.core'

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

M.simple_echo = lazy.require("lib.nvim.core.simple_echo")

---@type Lib.Nvim
return M
