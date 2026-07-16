---@module 'lib.lua.numeral.roman'
--- Roman numeral conversion (1-3999), pure Lua.

---@type LibNumeralRoman
local M = {}

---@type { [1]: integer, [2]: string }[]
local TABLE = {
  { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" },
  { 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" },
  { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" },
}

---Convert an integer (1-3999) to an uppercase Roman numeral string.
---@nodiscard
---@param n integer
---@return string|nil roman
---@return string|nil err
function M.to_roman(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > 3999 then
    return nil, "out of range"
  end

  local remaining = n
  local parts = {}
  for _, pair in ipairs(TABLE) do
    local value, numeral = pair[1], pair[2]
    while remaining >= value do
      parts[#parts + 1] = numeral
      remaining = remaining - value
    end
  end

  return table.concat(parts)
end

---@type table<string, integer>
local VALUES = { M = 1000, D = 500, C = 100, L = 50, X = 10, V = 5, I = 1 }

---Convert a Roman numeral string (case-insensitive) back to an integer.
---
---Round-trip-validates internally: converting the parsed integer back to
---Roman must equal the uppercased input, so non-canonical forms like
---"IIII" (canonical: "IV") are rejected.
---@nodiscard
---@param s string
---@return integer|nil n
---@return string|nil err
function M.to_int(s)
  if type(s) ~= "string" or s == "" then
    return nil, "invalid roman numeral"
  end

  local upper = s:upper()
  if upper:match("^[MDCLXVI]+$") == nil then
    return nil, "invalid roman numeral"
  end

  local total = 0
  local prev = 0
  -- Walk right to left; subtract when a smaller value precedes a larger one.
  for i = #upper, 1, -1 do
    local ch = upper:sub(i, i)
    local value = VALUES[ch]
    if value < prev then
      total = total - value
    else
      total = total + value
      prev = value
    end
  end

  if total < 1 or total > 3999 then
    return nil, "invalid roman numeral"
  end

  local canonical = M.to_roman(total)
  if not canonical or canonical ~= upper then
    return nil, "invalid roman numeral"
  end

  return total
end

return M
