---@module 'lib.lua.strings.location'
--- Parse "path:line:col"-style location strings out of arbitrary text
--- (grep output, compiler errors, stack traces, ...). Pure Lua.

local M = {}

--- Lib.Strings.Location: see @types/init.lua.

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

---@type Lib.Strings.Location.Mod
return M
