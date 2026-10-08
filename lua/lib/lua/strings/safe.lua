---@module 'lib.lua.strings.safe'
--- Making text that came out of somebody else's repository, process or file
--- safe to put on screen. A commit message is chosen by whoever wrote the
--- commit: it can carry terminal escape sequences, a carriage return that
--- overwrites the line it sits on, bytes that are not UTF-8 at all, or a
--- megabyte of text. Pure Lua (no `vim.*`), so it is usable from a fast-event
--- context and from `lib.lua` consumers.

local M = {}

---Default cap of `clean`, in characters. Longer text is cut and marked with "…".
M.MAX_LINE = 400

---Length in bytes of the valid UTF-8 sequence starting at `s[i]`, or `nil` when
---the bytes there are not valid UTF-8 (stray continuation byte, truncated or
---overlong sequence, surrogate, code point above U+10FFFF).
---@param s string
---@param i integer
---@return integer|nil
local function valid_len(s, i)
  local c = s:byte(i)
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
  if i + len - 1 > #s then
    return nil
  end
  for k = 1, len - 1 do
    local b = s:byte(i + k)
    if b < 0x80 or b > 0xBF then
      return nil
    end
  end
  if len >= 3 then
    local b2 = s:byte(i + 1)
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

---`s` with every byte that is not part of valid UTF-8 replaced by `?`. A commit
---message is raw bytes in whatever encoding its author used; JSON, buffers and
---the clipboard want text. ASCII (the common case) is returned as is.
---@param s string
---@return string
function M.utf8(s)
  if not s:find("[\128-\255]") then
    return s
  end
  local out, i, n = {}, 1, #s
  while i <= n do
    local len = valid_len(s, i)
    if len then
      out[#out + 1] = s:sub(i, i + len - 1)
      i = i + len
    else
      out[#out + 1] = "?"
      i = i + 1
    end
  end
  return table.concat(out)
end

---Byte offset after the first `max` characters of `s` (an invalid byte counts
---as one character), or `nil` when `s` has `max` characters or fewer.
---@param s string
---@param max integer
---@return integer|nil
local function cut_offset(s, max)
  local i, n, count = 1, #s, 0
  if n <= max then
    return nil
  end -- at most one character per byte
  while i <= n do
    if count == max then
      return i - 1
    end
    i = i + (valid_len(s, i) or 1)
    count = count + 1
  end
  return nil
end

---Replace control characters and cap the length. A tab becomes a space; any
---other control byte (ESC, CR, NUL, DEL, ...) becomes `?` so nothing in the
---text can move the cursor, recolour the terminal or hide a character. The C1
---controls (U+0080..U+009F, two bytes in UTF-8) go too: a terminal in UTF-8
---mode reads U+009B as a CSI. Characters that change how text is ORDERED or hide
---it (zero-width and bidi marks, line/paragraph separators, the byte-order mark)
---are replaced as well.
---@param s string
---@param max_chars? integer cap in characters (default `M.MAX_LINE`)
---@return string
function M.clean(s, max_chars)
  -- An explicit byte class, not `%c`: `iscntrl` follows the C locale, and in some
  -- locales (macOS UTF-8, Latin-1) it also covers 0x80..0x9F, which would break
  -- the continuation bytes of "…", "€" or any CJK character.
  s = s:gsub("\t", " "):gsub("[%z\1-\31\127]", "?"):gsub("\194[\128-\159]", "?")
  -- UTF-8 byte forms: U+200B-200F, U+202A-202E, U+2066-2069, U+2028/2029, U+FEFF.
  s = s:gsub("\226\128[\139-\143]", "?")
    :gsub("\226\128[\168-\174]", "?")
    :gsub("\226\129[\166-\169]", "?")
    :gsub("\239\187\191", "?")
  local cut = cut_offset(s, max_chars or M.MAX_LINE)
  if cut then
    s = s:sub(1, cut) .. "…"
  end
  return s
end

---The first line of `s`, cleaned: what goes into a notification, a window title
---or a header. A multi-line git error must not turn a one-line message into a
---hit-enter prompt.
---@param s any
---@param max_chars? integer
---@return string
function M.one_line(s, max_chars)
  s = tostring(s == nil and "" or s)
  return M.clean((s:match("^[^\r\n]*")), max_chars)
end

---Split a multi-line text into cleaned lines.
---@param text string
---@param max_chars? integer
---@return string[]
function M.lines(text, max_chars)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = M.clean(line, max_chars)
  end
  return out
end

return M
