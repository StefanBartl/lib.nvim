---@module 'lib.lua.strings.convert.hex_to_string'
--- Convert a hex codepoint string (e.g. "F0056") to a UTF-8 character.
--- Pure Lua (lib.lua.strings.utf8.encode) -- this module lives under the
--- editor-independent lib.lua.* tree, so it must not depend on `vim`; it
--- previously called vim.fn.nr2char, the one exception in this namespace.

local utf8 = require("lib.lua.strings.utf8")

---@param hex string -- upper/lower hex without "0x", e.g. "F0056"
---@return string    -- the UTF-8 character or empty string on failure/codepoint 0
return function(hex)
  -- Defensive: tonumber(..., 16) may return nil on invalid input
  local n = tonumber(hex, 16)
  if not n or n <= 0 then
    -- nr2char(0) returned "" (NUL can't live in a normal Vim string); match that.
    return ""
  end
  return utf8.encode(n)
end
