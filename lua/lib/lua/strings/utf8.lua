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
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
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

---Length in bytes of the valid UTF-8 sequence (RFC 3629) starting at `str[i]`, or `nil` when the bytes there
---are not valid UTF-8: a stray continuation byte, `0xC0`/`0xC1`, `0xF5-0xFF`, a sequence cut short, an overlong
---form (`E0 80 80`), a UTF-16 surrogate (`ED A0 80`) or a value above U+10FFFF (`F4 90 80 80`).
---@param str string
---@param i? integer  # defaults to 1
---@return integer|nil len
function M.valid_len(str, i)
  i = i or 1
  local c = str:byte(i)
  if not c then
    return nil
  end
  local len
  if c < 0x80 then
    return 1
  elseif c >= 0xC2 and c <= 0xDF then
    len = 2
  elseif c >= 0xE0 and c <= 0xEF then
    len = 3
  elseif c >= 0xF0 and c <= 0xF4 then
    len = 4
  else
    return nil
  end
  if i + len - 1 > #str then
    return nil
  end
  for k = 1, len - 1 do
    local b = str:byte(i + k)
    if b < 0x80 or b > 0xBF then
      return nil
    end
  end
  if len >= 3 then
    local b2 = str:byte(i + 1)
    if
      (c == 0xE0 and b2 < 0xA0)
      or (c == 0xED and b2 > 0x9F)
      or (c == 0xF0 and b2 < 0x90)
      or (c == 0xF4 and b2 > 0x8F)
    then
      return nil
    end
  end
  return len
end

---Replace every byte that is not part of a valid UTF-8 sequence (see `valid_len`) with `repl`, one replacement
---per byte, and count them. Valid input is returned unchanged (the same string). A lead byte whose
---continuation bytes are wrong is replaced alone; the bytes after it are judged on their own.
---
---Meant for a consumer that dies on a bad byte (`win32yank.exe -i` exits 101 and the yank is lost).
---@param str string
---@param repl? string  # replacement for one bad byte (default "?")
---@return string clean
---@return integer replaced  # number of bytes replaced
function M.scrub(str, repl)
  repl = repl or "?"
  -- Pure ASCII is the overwhelmingly common case and always valid.
  if not str:find("[\128-\255]") then
    return str, 0
  end
  -- copy valid runs whole; only an invalid byte costs an extra piece
  local out, i, n, run_start, replaced = {}, 1, #str, 1, 0
  while i <= n do
    local len = M.valid_len(str, i)
    if len then
      i = i + len
    else
      if i > run_start then
        out[#out + 1] = str:sub(run_start, i - 1)
      end
      out[#out + 1] = repl
      replaced = replaced + 1
      i = i + 1
      run_start = i
    end
  end
  if replaced == 0 then
    return str, 0
  end
  if run_start <= n then
    out[#out + 1] = str:sub(run_start, n)
  end
  return table.concat(out), replaced
end

---@type Lib.Strings.Utf8
return M
