---@module 'lib.lua.strings.safe'
--- Making text that came out of somebody else's repository, process or file
--- safe to put on screen. A commit message is chosen by whoever wrote the
--- commit: it can carry terminal escape sequences, a carriage return that
--- overwrites the line it sits on, invisible characters that make it read
--- differently from what it is, bytes that are not UTF-8, or a hundred
--- megabytes of text. The work is bounded by what is shown, not by what was
--- sent. Pure Lua (no `vim.*`), so it is usable from a fast-event context and
--- from `lib.lua` consumers.

local M = {}

---Default cap of `clean`, in characters. Longer text is cut and marked with "…".
M.MAX_LINE = 400

---Lines counted at most this far (a body of millions of lines is not walked to
---the end just to say how many there are).
local COUNT_CAP = 200000

local utf8 = require("lib.lua.strings.utf8")

local valid_len = utf8.valid_len

---`s` with every byte that is not part of valid UTF-8 replaced by `?`. A commit
---message is raw bytes in whatever encoding its author used; JSON, buffers and
---the clipboard want text. ASCII (the common case) is returned as is.
---@param s string
---@return string
function M.utf8(s)
  return (utf8.scrub(s))
end

---Byte offset after the first `max` characters of `s` (an invalid byte counts
---as one character), or `nil` when `s` has `max` characters or fewer.
---@param s string
---@param max integer
---@return integer|nil
local function cut_offset(s, max)
  local n = #s
  if n <= max then
    return nil -- at most one character per byte
  end
  local i, count = 1, 0
  while i <= n do
    if count == max then
      return i - 1
    end
    i = i + (valid_len(s, i) or 1)
    count = count + 1
  end
  return nil
end

---Make one line of foreign text printable: cut to what is shown, valid UTF-8,
---no control characters, no invisible or re-ordering ones, at most `max_chars`
---characters. A tab becomes a space; any other control byte (ESC, CR, NUL, DEL,
---...) becomes `?` so nothing in the text can move the cursor, recolour the
---terminal or hide a character. The C1 controls (U+0080..U+009F, two bytes in
---UTF-8) go too: a terminal in UTF-8 mode reads U+009B as a CSI. So do the
---characters that change how text is ORDERED or hide it -- zero-width and bidi
---marks (U+200B-200F, U+202A-202E, U+2060-206F), the line/paragraph separators
---U+2028/2029, the Arabic letter mark U+061C, the byte-order mark U+FEFF, the
---interlinear annotation marks U+FFF9-FFFB, the Unicode tag block
---(U+E0000-E3FFF, which can spell a sentence nobody sees) and the blank
---fillers (Hangul fillers, Mongolian selectors and vowel separator
---U+180B-180F, Khmer inherent vowels U+17B4/17B5, braille blank, soft hyphen,
---combining grapheme joiner, musical formatting, shorthand format controls
---U+1BCA0-1BCA3). Variation selectors (emoji presentation) stay.
---
---Only the first four bytes per allowed character are looked at, so a
---multi-megabyte line costs the same as a short one.
---@param s string
---@param max_chars? integer cap in characters (default `M.MAX_LINE`)
---@return string
function M.clean(s, max_chars)
  max_chars = max_chars or M.MAX_LINE
  local byte_cap = 4 * max_chars + 16
  if #s > byte_cap then
    s = s:sub(1, byte_cap)
  end
  s = M.utf8(s)
  -- An explicit byte class, not `%c`: `iscntrl` follows the C locale, and in some
  -- locales (macOS UTF-8, Latin-1) it also covers 0x80..0x9F, which would break
  -- the continuation bytes of "…", "€" or any CJK character.
  s = s:gsub("\t", " "):gsub("[%z\1-\31\127]", "?"):gsub("\194[\128-\159]", "?")
  if s:find("[\194-\244]") then
    s = s
      :gsub("\226\128[\139-\143]", "?") -- U+200B-200F
      :gsub("\226\128[\168-\174]", "?") -- U+2028-202E
      :gsub("\226\129[\160-\175]", "?") -- U+2060-206F
      :gsub("\216\156", "?") -- U+061C
      :gsub("\239\187\191", "?") -- U+FEFF
      :gsub("\239\191[\185-\187]", "?") -- U+FFF9-FFFB
      :gsub("\243[\160-\163][\128-\191][\128-\191]", "?") -- U+E0000-E3FFF
      :gsub("\227\133\164", "?") -- U+3164 Hangul filler
      :gsub("\239\190\160", "?") -- U+FFA0 halfwidth Hangul filler
      :gsub("\225\133[\159\160]", "?") -- U+115F, U+1160
      :gsub("\225\160[\139-\143]", "?") -- U+180B-180F Mongolian selectors, vowel separator
      :gsub("\225\158[\180\181]", "?") -- U+17B4, U+17B5 Khmer inherent vowels
      :gsub("\240\155\178[\160-\163]", "?") -- U+1BCA0-1BCA3 shorthand format controls
      :gsub("\226\160\128", "?") -- U+2800 braille blank
      :gsub("\194\173", "?") -- U+00AD soft hyphen
      :gsub("\205\143", "?") -- U+034F combining grapheme joiner
      :gsub("\240\157\133[\179-\186]", "?") -- U+1D173-1D17A musical formatting
  end
  local cut = cut_offset(s, max_chars)
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
---
---With `max`, only the first `max` lines are cleaned and returned; the rest are
---only counted. The cost then follows what is shown, not the size of the text.
---@param text string
---@param max? integer
---@param max_chars? integer per-line cap, see `clean`
---@return string[] lines
---@return integer total  How many lines there are (counted up to 200000).
---@return boolean exact  `false` when the count stopped at the cap.
function M.lines(text, max, max_chars)
  local byte_cap = 4 * (max_chars or M.MAX_LINE) + 16
  local out, total = {}, 0
  local pos, n = 1, #text
  while pos <= n + 1 do
    local nl = text:find("\n", pos, true)
    total = total + 1
    if not max or #out < max then
      local stop = (nl or n + 1) - 1
      -- never copy more of a huge line than `clean` looks at
      out[#out + 1] = M.clean(text:sub(pos, math.min(stop, pos + byte_cap)), max_chars)
    end
    if not nl then
      return out, total, true
    end
    if total >= COUNT_CAP and max and #out >= max then
      return out, total, false
    end
    pos = nl + 1
  end
  return out, total, true
end

return M
