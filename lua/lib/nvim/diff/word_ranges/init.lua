---@module 'lib.nvim.diff.word_ranges'
---@brief The spans that changed between two single lines, found by `vim.text.diff` (no second diff implementation).
---@description
--- `lib.lua.diff` diffs arrays of lines. To highlight WHAT changed inside one
--- changed line, the line is exploded into a synthetic document with one
--- "line" per unit, run through Neovim's own diff (`result_type = "indices"`)
--- and the hunks are mapped back to byte offsets.
---
--- The unit is a UTF-8 codepoint, so a highlighted span starts and ends on a
--- codepoint boundary, never inside a multi-byte character. A line that is not
--- valid UTF-8 is compared byte by byte instead.
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

---Code-point start offsets of `s` (1-based), or nil when `s` is not valid UTF-8.
---@param s string
---@return integer[]|nil
local function utf8_positions(s)
  local ok, pos = pcall(vim.str_utf_pos, s)
  if not ok or type(pos) ~= "table" then
    return nil
  end
  return pos
end

---One diff "line" per unit.
---@param s string
---@param pos integer[]|nil  code-point starts; nil: one unit per byte
---@return string
local function explode(s, pos)
  local units = {}
  if pos then
    local n = #pos
    for i = 1, n do
      units[i] = s:sub(pos[i], (i < n) and (pos[i + 1] - 1) or #s)
    end
  else
    for i = 1, #s do
      units[i] = s:sub(i, i)
    end
  end
  return table.concat(units, "\n")
end

---Map a 1-based run of `count` units starting at unit `start` to a 0-based `[from, to)` byte range.
---@param pos integer[]|nil
---@param s string
---@param start integer
---@param count integer
---@return integer[]
local function byte_range(pos, s, start, count)
  if not pos then
    return { start - 1, start - 1 + count }
  end
  local last = start + count
  return { pos[start] - 1, (last <= #pos) and (pos[last] - 1) or #s }
end

---@param a string
---@param b string
---@param algorithm string
---@param pos_a integer[]|nil
---@param pos_b integer[]|nil
---@return Lib.Diff.WordRanges.Result|nil
local function run(a, b, algorithm, pos_a, pos_b)
  local fn = diff_fn()
  if not fn then
    return nil
  end
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
---@param a string  the old text (one line)
---@param b string  the new text (one line)
---@param algorithm? "myers"|"minimal"|"patience"|"histogram"  `vim.text.diff` algorithm (default `"myers"`)
---@return Lib.Diff.WordRanges.Result|nil ranges  `nil` when an argument is no string or the diff failed; equal strings give empty lists
return function(a, b, algorithm)
  if type(a) ~= "string" or type(b) ~= "string" then
    return nil
  end
  if a == b then
    return { a = {}, b = {} }
  end
  algorithm = algorithm or "myers"
  local pos_a, pos_b = utf8_positions(a), utf8_positions(b)
  if pos_a and pos_b then
    local r = run(a, b, algorithm, pos_a, pos_b)
    if r then
      return r
    end
  end
  return run(a, b, algorithm, nil, nil)
end
