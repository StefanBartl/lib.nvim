---@module 'lib.lua.strings.utf8'
--- Minimal UTF-8 codepoint encode/decode, pure Lua (arithmetic only, no
--- bitwise operators — works unmodified on Lua 5.1/LuaJIT).

local M = {}

---Number of bytes in the UTF-8 sequence starting with `lead_byte`.
---@param lead_byte integer 0-255
---@return integer len 1-4, or 1 for an invalid/continuation lead byte
function M.char_len(lead_byte)
  if lead_byte < 0x80 then
    return 1
  elseif lead_byte >= 0xF0 then
    return 4
  elseif lead_byte >= 0xE0 then
    return 3
  elseif lead_byte >= 0xC0 then
    return 2
  end
  return 1 -- continuation byte or invalid; treat as a single byte
end

---Encode a Unicode codepoint as a UTF-8 byte string.
---@param cp integer
---@return string
function M.encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(
      0xC0 + math.floor(cp / 0x40),
      0x80 + (cp % 0x40)
    )
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 0x1000),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  else
    return string.char(
      0xF0 + math.floor(cp / 0x40000),
      0x80 + (math.floor(cp / 0x1000) % 0x40),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  end
end

---Decode the UTF-8 character starting at byte index `i` (1-based) in `str`.
---@param str string
---@param i? integer defaults to 1
---@return integer|nil cp Codepoint, or nil if `i` is out of range
---@return integer next_i Byte index of the next character
function M.decode(str, i)
  i = i or 1
  if i > #str then
    return nil, i
  end
  local b1 = str:byte(i)
  local len = M.char_len(b1)
  if i + len - 1 > #str then
    return b1, i + 1 -- truncated sequence; fall back to single byte
  end
  local cp
  if len == 1 then
    cp = b1
  elseif len == 2 then
    local b2 = str:byte(i + 1)
    cp = (b1 % 0x20) * 0x40 + (b2 % 0x40)
  elseif len == 3 then
    local b2, b3 = str:byte(i + 1), str:byte(i + 2)
    cp = (b1 % 0x10) * 0x1000 + (b2 % 0x40) * 0x40 + (b3 % 0x40)
  else
    local b2, b3, b4 = str:byte(i + 1), str:byte(i + 2), str:byte(i + 3)
    cp = (b1 % 0x08) * 0x40000 + (b2 % 0x40) * 0x1000 + (b3 % 0x40) * 0x40 + (b4 % 0x40)
  end
  return cp, i + len
end

---Iterate over the Unicode codepoints of `str`.
---@param str string
---@return fun(): integer|nil, integer|nil # iterator yielding (codepoint, byte_index)
function M.iter(str)
  local i = 1
  return function()
    if i > #str then
      return nil
    end
    local cp, next_i = M.decode(str, i)
    local start = i
    i = next_i
    return cp, start
  end
end

return M
