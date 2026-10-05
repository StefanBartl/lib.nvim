---@module 'lib.lua.strings.location'
--- Parse "path:line:col"-style location strings out of arbitrary text
--- (grep output, compiler errors, stack traces, ...). Pure Lua.

local strings = require("lib.lua.strings.core")

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
  local s = strings.trim(str)

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

  -- "path +line". Not `^(.-)%s+%+(%d+)$`: that retries a whitespace run from every byte
  -- inside it (SEC-32). The digits come first, then the text before the `+` must end in
  -- whitespace.
  local plus_line = s:match("%+(%d+)$")
  if plus_line then
    local before = s:sub(1, #s - #plus_line - 1)
    if before:find("%s$") then
      return { path = strings.rtrim(before), line = tonumber(plus_line), col = nil }
    end
  end

  return nil
end

---@type Lib.Strings.Location.Mod
return M
