---@module 'lib.nvim.diff.word_ranges'
---@brief The spans that changed between two single lines, found by `vim.text.diff` (no second diff implementation).
---@description
--- `lib.lua.diff` diffs arrays of lines. To highlight WHAT changed inside one
--- changed line, the line is exploded into a synthetic document with one
--- "line" per unit, run through Neovim's own diff (`result_type = "indices"`)
--- and the hunks are mapped back to byte offsets.
---
--- The unit is a UTF-8 codepoint, so a highlighted span starts and ends on a
--- codepoint boundary, never inside a multi-byte character. Every byte that is not
--- part of a well-formed sequence (a stray byte, NUL) is a unit of its own.
---
---```lua
--- local word_ranges = require("lib.nvim.diff.word_ranges")
---
--- local r = word_ranges("local x = 1", "local y = 1")
--- -- r.a == { { 6, 7 } }   -- 0-based, end-exclusive byte ranges in `a`
--- -- r.b == { { 6, 7 } }   -- ... and in `b`
---```
---@see lib.lua.diff

require("lib.nvim.diff.word_ranges.@types")

---`vim.text.diff` is the current name; `vim.diff` is the deprecated one before Neovim 0.12.
---@return function|nil
local function diff_fn()
  return (vim.text and vim.text.diff) or vim.diff
end

---Start offsets (1-based) of the units of `s`: a well-formed UTF-8 sequence is one unit, every other byte
---(a stray continuation byte, a truncated or invalid sequence, NUL) is a unit of its own. Done by hand because
---`vim.str_utf_pos` stops at a NUL byte and cannot be told to go on after an invalid one.
---@param s string
---@return integer[]
local function unit_starts(s)
  local starts, n, i = {}, #s, 1
  while i <= n do
    starts[#starts + 1] = i
    local b = s:byte(i)
    local len = 1
    if b >= 0xC2 and b <= 0xDF then
      len = 2
    elseif b >= 0xE0 and b <= 0xEF then
      len = 3
    elseif b >= 0xF0 and b <= 0xF4 then
      len = 4
    end
    if len > 1 then
      if i + len - 1 > n then
        len = 1
      else
        for k = i + 1, i + len - 1 do
          local c = s:byte(k)
          if c < 0x80 or c > 0xBF then
            len = 1
            break
          end
        end
      end
    end
    i = i + len
  end
  return starts
end

---A unit that would break the synthetic document (it is made of lines) is stood for by a token that no single
---unit can equal, so two equal units stay equal.
local STAND_IN = { ["\n"] = "<LF>", ["\r"] = "<CR>" }

---One diff "line" per unit, each ended by a line feed: the last unit of a document without one would differ from
---the same unit inside the other document, and a change at the end of the line would mark it too.
---@param s string
---@param pos integer[]
---@return string
local function explode(s, pos)
  local units = {}
  local n = #pos
  for i = 1, n do
    local unit = s:sub(pos[i], (i < n) and (pos[i + 1] - 1) or #s)
    units[i] = STAND_IN[unit] or unit
  end
  if n == 0 then
    return ""
  end
  return table.concat(units, "\n") .. "\n"
end

---Map a 1-based run of `count` units starting at unit `start` to a 0-based `[from, to)` byte range.
---@param pos integer[]
---@param s string
---@param start integer
---@param count integer
---@return integer[]
local function byte_range(pos, s, start, count)
  local last = start + count
  return { pos[start] - 1, (last <= #pos) and (pos[last] - 1) or #s }
end

---@param a string
---@param b string
---@param algorithm string
---@return Lib.Diff.WordRanges.Result|nil
local function run(a, b, algorithm)
  local fn = diff_fn()
  if not fn then
    return nil
  end
  local pos_a, pos_b = unit_starts(a), unit_starts(b)
  local ok, hunks = pcall(fn, explode(a, pos_a), explode(b, pos_b), {
    result_type = "indices",
    algorithm = algorithm,
  })
  if not ok or type(hunks) ~= "table" then
    return nil
  end
  local ranges = { a = {}, b = {} }
  for _, h in ipairs(hunks) do
    local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]
    if count_a > 0 then
      ranges.a[#ranges.a + 1] = byte_range(pos_a, a, start_a, count_a)
    end
    if count_b > 0 then
      ranges.b[#ranges.b + 1] = byte_range(pos_b, b, start_b, count_b)
    end
  end
  return ranges
end

---The changed byte ranges of two strings.
---@param a string  the old text (normally one line; a line break inside counts as one ordinary unit)
---@param b string  the new text
---@param algorithm? "myers"|"minimal"|"patience"|"histogram"  `vim.text.diff` algorithm (default `"myers"`)
---@return Lib.Diff.WordRanges.Result|nil ranges  `nil` when an argument is no string or the diff failed; equal strings give empty lists
return function(a, b, algorithm)
  if type(a) ~= "string" or type(b) ~= "string" then
    return nil
  end
  if a == b then
    return { a = {}, b = {} }
  end
  return run(a, b, algorithm or "myers")
end
