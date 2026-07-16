---@module 'lib.lua.dump'
--- Recursive Lua value dumper, pure Lua — an alternative/complement to
--- `vim.inspect` for tables/metatables/functions/threads/userdata, with a
--- hard recursion-depth limit against cyclic tables or huge structures.
---
--- Usage:
--- ```lua
--- local dump = require("lib.lua.dump")
--- print(dump.to_string(some_value))
--- local lines = dump.to_lines(some_value, { max_depth = 10 })
--- ```

---@type LibDump
local M = {}

---@type integer Default hard recursion-depth limit.
local DEFAULT_MAX_DEPTH = 30

---@param value any
---@param depth integer
---@param key any
---@param lines string[]
---@param max_depth integer
---@return nil
local function dump_value(value, depth, key, lines, max_depth)
  local line_prefix = ""
  local spaces = ""
  if key ~= nil then
    line_prefix = "[" .. tostring(key) .. "] = "
  end
  if depth > 0 then
    spaces = string.rep("  ", depth)
  end

  if depth > max_depth then
    lines[#lines + 1] = spaces .. line_prefix .. "<max depth reached>"
    return
  end

  if type(value) == "table" then
    local mtable = getmetatable(value)
    if mtable == nil then
      lines[#lines + 1] = spaces .. line_prefix .. "(table)"
    else
      lines[#lines + 1] = spaces .. line_prefix .. "(table with metatable)"
      for k, v in pairs(value) do
        dump_value(v, depth + 1, k, lines, max_depth)
      end
      lines[#lines + 1] = spaces .. "  (metatable)"
      dump_value(mtable, depth + 1, nil, lines, max_depth)
      return
    end
    for k, v in pairs(value) do
      dump_value(v, depth + 1, k, lines, max_depth)
    end
  elseif type(value) == "function" or type(value) == "thread" or type(value) == "userdata" or value == nil then
    lines[#lines + 1] = spaces .. line_prefix .. tostring(value)
  else
    lines[#lines + 1] = spaces .. line_prefix .. "(" .. type(value) .. ") " .. tostring(value)
  end
end

---Recursively dump `value` into an array of indented report lines.
---@param value any
---@param opts? { max_depth?: integer }
---@return string[] lines
function M.to_lines(value, opts)
  opts = opts or {}
  local lines = {}
  dump_value(value, 0, nil, lines, opts.max_depth or DEFAULT_MAX_DEPTH)
  return lines
end

---Recursively dump `value` into a single newline-joined report string.
---@param value any
---@param opts? { max_depth?: integer }
---@return string
function M.to_string(value, opts)
  return table.concat(M.to_lines(value, opts), "\n")
end

return M
