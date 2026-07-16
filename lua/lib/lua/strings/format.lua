---@module 'lib.lua.strings.format'
--- Human-readable number/byte-size formatting, pure Lua.

local M = {}

local UNITS = { "B", "KB", "MB", "GB", "TB", "PB" }

---Format a byte count as a human-readable size (e.g. `1536` -> `"1.5 KB"`).
---@param n integer
---@param decimals? integer defaults to 1
---@return string
function M.format_bytes(n, decimals)
  decimals = decimals or 1
  if n < 1024 then
    return string.format("%d B", n)
  end
  local value = n
  local unit_i = 1
  while value >= 1024 and unit_i < #UNITS do
    value = value / 1024
    unit_i = unit_i + 1
  end
  return string.format("%." .. decimals .. "f %s", value, UNITS[unit_i])
end

---Format an integer or float with thousands separators (e.g. `1234567` ->
---`"1,234,567"`).
---@param n number
---@param sep? string defaults to ","
---@return string
function M.format_number(n, sep)
  sep = sep or ","
  local is_negative = n < 0
  local digits = string.format("%.0f", math.abs(n))
  -- Group from the right by reversing, inserting a separator every 3 digits,
  -- then reversing back. A group of exactly 3 at the very end leaves a
  -- leading separator behind ("123456" -> ",123,456"), so strip it.
  local grouped = digits:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
  if grouped:sub(1, #sep) == sep then
    grouped = grouped:sub(#sep + 1)
  end
  return (is_negative and "-" or "") .. grouped
end

return M
