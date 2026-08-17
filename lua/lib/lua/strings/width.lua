---@module 'lib.lua.strings.width'
--- Display-width arithmetic: how many terminal *columns* a string occupies,
--- as opposed to how many bytes (`#str`) or codepoints it contains.
---
--- The rest of `lib.lua.strings` measures in bytes, which is correct for
--- ASCII and wrong for everything else: `#"日本"` is 6, its width is 4, and
--- its length in characters is 2. `core.pad_end`/`wrap.center_text` pad by
--- byte count and therefore misalign any column containing CJK text, an
--- emoji, or a tab. This module is the width-aware counterpart — additive,
--- so the byte-based originals keep their (cheaper, ASCII-correct)
--- behavior for callers that never see non-ASCII.
---
--- Inside Neovim, `vim.fn.strdisplaywidth()` is the authoritative answer
--- and already handles `'ambiwidth'`, custom `'listchars'` and the full
--- Unicode tables. Prefer it there. This exists because `lib.lua.*` is
--- editor-independent by definition and cannot call `vim.fn` — and because
--- a `vim.fn` call is not usable in a fast-event context, where a
--- `lib.lua` helper still is.
---
---```lua
--- local width = require("lib.lua.strings.width")
---
--- width.display_width("日本")        --> 4
--- width.display_width("a\tb")        --> 10  (tab to the next stop of 8)
--- width.truncate("日本語テキスト", 6) --> "日本語"
--- width.pad_end("日本", 6)            --> "日本  "
---```

local utf8 = require("lib.lua.strings.utf8")

local M = {}

-- =========================================================
-- Character width tables
-- =========================================================

--- Codepoint ranges rendered two columns wide: East Asian Wide (W) and
--- Fullwidth (F) per UAX #11, plus the emoji blocks terminals universally
--- render double-width.
---
--- A hand-maintained approximation of the real Unicode tables, not a
--- generated copy of them: it covers the ranges that actually show up in
--- source, filenames and UI strings. Codepoints outside these ranges are
--- treated as single-width, so an exotic wide character is under-measured
--- rather than raising.
local WIDE_RANGES = {
  { 0x1100, 0x115F }, -- Hangul Jamo (initial consonants)
  { 0x2E80, 0x303E }, -- CJK radicals, Kangxi, CJK symbols/punctuation
  { 0x3041, 0x33FF }, -- Hiragana, Katakana, Bopomofo, Hangul Compat, CJK compat
  { 0x3400, 0x4DBF }, -- CJK Unified Ideographs Extension A
  { 0x4E00, 0x9FFF }, -- CJK Unified Ideographs
  { 0xA000, 0xA4CF }, -- Yi syllables/radicals
  { 0xAC00, 0xD7A3 }, -- Hangul syllables
  { 0xF900, 0xFAFF }, -- CJK Compatibility Ideographs
  { 0xFE10, 0xFE19 }, -- Vertical forms
  { 0xFE30, 0xFE6F }, -- CJK compatibility forms, small form variants
  { 0xFF00, 0xFF60 }, -- Fullwidth ASCII variants
  { 0xFFE0, 0xFFE6 }, -- Fullwidth signs
  { 0x1F300, 0x1F64F }, -- Misc symbols/pictographs, emoticons
  { 0x1F900, 0x1F9FF }, -- Supplemental symbols/pictographs
  { 0x20000, 0x2FFFD }, -- CJK Extension B..F
  { 0x30000, 0x3FFFD }, -- CJK Extension G
}

--- Codepoint ranges that occupy no column of their own: combining marks
--- (they stack onto the preceding character), zero-width spaces/joiners,
--- and variation selectors.
local ZERO_RANGES = {
  { 0x0300, 0x036F }, -- Combining diacritical marks
  { 0x0483, 0x0489 }, -- Combining Cyrillic
  { 0x0591, 0x05BD }, -- Hebrew points
  { 0x0610, 0x061A }, -- Arabic marks
  { 0x064B, 0x065F }, -- Arabic diacritics
  { 0x0E31, 0x0E31 }, -- Thai vowel sign
  { 0x0E34, 0x0E3A },
  { 0x1AB0, 0x1AFF }, -- Combining diacritical marks extended
  { 0x1DC0, 0x1DFF }, -- Combining diacritical marks supplement
  { 0x200B, 0x200F }, -- Zero-width space/joiners, directional marks
  { 0x20D0, 0x20FF }, -- Combining marks for symbols
  { 0xFE00, 0xFE0F }, -- Variation selectors
  { 0xFE20, 0xFE2F }, -- Combining half marks
  { 0xFEFF, 0xFEFF }, -- Zero-width no-break space (BOM)
}

---@internal
---@param cp integer
---@param ranges integer[][]
---@return boolean
local function in_ranges(cp, ranges)
  for i = 1, #ranges do
    local range = ranges[i]
    if cp >= range[1] and cp <= range[2] then
      return true
    end
  end
  return false
end

--- Columns occupied by a single codepoint: `0` for combining/zero-width
--- marks, `2` for East Asian Wide/Fullwidth and emoji, `1` otherwise.
---
--- Control characters other than tab report `0`; a tab has no intrinsic
--- width at all (it depends on the current column), so `display_width`
--- handles it and this returns `0` for it too.
---@param cp integer
---@return integer
function M.char_width(cp)
  if cp == 0x09 then
    return 0 -- tab: column-dependent, resolved in display_width
  end
  if cp < 0x20 or cp == 0x7F then
    return 0 -- other C0 controls / DEL render as nothing on their own
  end
  if cp < 0x7F then
    return 1 -- printable ASCII, the overwhelmingly common case
  end
  if in_ranges(cp, ZERO_RANGES) then
    return 0
  end
  if in_ranges(cp, WIDE_RANGES) then
    return 2
  end
  return 1
end

-- =========================================================
-- String width
-- =========================================================

--- Columns occupied by `str`.
---
--- Tabs advance to the next multiple of `opts.tabstop` (default 8), which
--- is why this is not simply the sum of `char_width` over the string: a
--- tab's width depends on where it starts.
---@param str string
---@param opts? Lib.Strings.Width.Opts
---@return integer
function M.display_width(str, opts)
  local tabstop = (opts and opts.tabstop) or 8
  local col = 0
  for cp in utf8.iter(str) do
    if cp == 0x09 then
      col = col + (tabstop - (col % tabstop))
    else
      col = col + M.char_width(cp)
    end
  end
  return col
end

--- Truncate `str` to at most `max_cols` display columns, never splitting a
--- character in half.
---
--- With `opts.ellipsis`, the ellipsis is appended *within* the budget (the
--- result still fits `max_cols`), so it replaces trailing content rather
--- than overflowing. If the ellipsis alone is wider than `max_cols`, the
--- result is empty rather than over-wide.
---
--- A double-width character that would straddle the limit is dropped
--- whole, so the result can be one column narrower than `max_cols`.
---@param str string
---@param max_cols integer
---@param opts? Lib.Strings.Width.TruncateOpts
---@return string truncated
---@return integer width Display width of the result.
function M.truncate(str, max_cols, opts)
  local tabstop = (opts and opts.tabstop) or 8
  local ellipsis = (opts and opts.ellipsis) or ""

  if M.display_width(str, { tabstop = tabstop }) <= max_cols then
    return str, M.display_width(str, { tabstop = tabstop })
  end

  local ellipsis_w = M.display_width(ellipsis, { tabstop = tabstop })
  local budget = max_cols - ellipsis_w
  if budget < 0 then
    return "", 0
  end

  -- `cut` is tracked as "everything strictly before the current character",
  -- taken from the iterator's own start index rather than re-encoding the
  -- codepoint to measure it — a truncated or invalid sequence decodes to a
  -- single byte but would re-encode to more, which would over-cut.
  local col, cut = 0, #str
  for cp, byte_index in utf8.iter(str) do
    local w
    if cp == 0x09 then
      w = tabstop - (col % tabstop)
    else
      w = M.char_width(cp)
    end
    if col + w > budget then
      cut = byte_index - 1
      break
    end
    col = col + w
  end

  return str:sub(1, cut) .. ellipsis, col + ellipsis_w
end

-- =========================================================
-- Width-aware padding
-- =========================================================

--- Left-pad `str` with spaces to `width` display columns. The width-aware
--- counterpart to `lib.lua.strings.core.pad_start`, which counts bytes.
---@param str string
---@param width integer
---@param opts? Lib.Strings.Width.Opts
---@return string
function M.pad_start(str, width, opts)
  local w = M.display_width(str, opts)
  if w >= width then
    return str
  end
  return string.rep(" ", width - w) .. str
end

--- Right-pad `str` with spaces to `width` display columns.
---@param str string
---@param width integer
---@param opts? Lib.Strings.Width.Opts
---@return string
function M.pad_end(str, width, opts)
  local w = M.display_width(str, opts)
  if w >= width then
    return str
  end
  return str .. string.rep(" ", width - w)
end

--- Center `str` within `width` display columns. An odd remainder goes to
--- the right, matching `lib.lua.strings.core.pad_center`.
---@param str string
---@param width integer
---@param opts? Lib.Strings.Width.Opts
---@return string
function M.pad_center(str, width, opts)
  local w = M.display_width(str, opts)
  if w >= width then
    return str
  end
  local total = width - w
  local left = math.floor(total / 2)
  return string.rep(" ", left) .. str .. string.rep(" ", total - left)
end

---@type Lib.Strings.Width.Mod
return M
