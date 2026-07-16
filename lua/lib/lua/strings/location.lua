---@module 'lib.lua.strings.location'
--- Parse "path:line:col"-style location strings out of arbitrary text
--- (grep output, compiler errors, stack traces, ...). Pure Lua.

local M = {}

---@class Lib.Strings.Location
---@field path string
---@field line integer|nil
---@field col integer|nil

---Parse a location out of `str`. Supported forms:
---  "path:line:col", "path:line", "path(line:col)", "path(line)", "path +line"
---@param str string
---@return Lib.Strings.Location|nil
function M.parse_location(str)
  if type(str) ~= "string" then
    return nil
  end
  local s = str:match("^%s*(.-)%s*$")

  local path, line, col = s:match("^(.-):(%d+):(%d+)$")
  if path then
    return { path = path, line = tonumber(line), col = tonumber(col) }
  end

  path, line = s:match("^(.-):(%d+)$")
  if path then
    return { path = path, line = tonumber(line), col = nil }
  end

  path, line, col = s:match("^(.-)%((%d+):(%d+)%)$")
  if path then
    return { path = path, line = tonumber(line), col = tonumber(col) }
  end

  path, line = s:match("^(.-)%((%d+)%)$")
  if path then
    return { path = path, line = tonumber(line), col = nil }
  end

  path, line = s:match("^(.-)%s+%+(%d+)$")
  if path then
    return { path = path, line = tonumber(line), col = nil }
  end

  return nil
end

return M
