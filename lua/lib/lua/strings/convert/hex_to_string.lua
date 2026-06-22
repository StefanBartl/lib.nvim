---@module 'lib.lua.strings.convert.hex_to_string'
--- Convert a hex codepoint string (e.g. "F0056") to a UTF-8 character.
--- Uses Vim's nr2char to produce a valid UTF-8 sequence.
---@param hex string -- upper/lower hex without "0x", e.g. "F0056"
---@return string    -- the UTF-8 character or empty string on failure
return function (hex)
  -- Defensive: tonumber(..., 16) may return nil on invalid input
  local n = tonumber(hex, 16)
  if not n then
    return ""
  end
  return vim.fn.nr2char(n)
end

