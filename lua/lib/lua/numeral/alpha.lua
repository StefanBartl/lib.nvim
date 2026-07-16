---@module 'lib.lua.numeral.alpha'
--- Bijective base-26 conversion (spreadsheet-column style): 1 -> "a",
--- 26 -> "z", 27 -> "aa", 28 -> "ab", … Pure Lua.

---@type LibNumeralAlpha
local M = {}

---Convert an integer (>= 1) to a lowercase bijective base-26 string.
---@nodiscard
---@param n integer
---@return string|nil alpha
---@return string|nil err
function M.to_alpha(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < 1 then
    return nil, "out of range"
  end

  local chars = {}
  local remaining = n
  while remaining > 0 do
    remaining = remaining - 1
    local rem = remaining % 26
    table.insert(chars, 1, string.char(97 + rem))
    remaining = math.floor(remaining / 26)
  end

  return table.concat(chars)
end

---Convert a (lowercase or uppercase) letter string back to an integer.
---@nodiscard
---@param s string
---@return integer|nil n
function M.to_int(s)
  if type(s) ~= "string" or s == "" then
    return nil
  end

  local lower = s:lower()
  if lower:match("^%a+$") == nil then
    return nil
  end

  local total = 0
  for i = 1, #lower do
    local digit = lower:byte(i) - 96 -- 'a' -> 1, ..., 'z' -> 26
    total = total * 26 + digit
  end

  return total
end

return M
