---@module 'lib.lua.time.diff.internal.convert'
---@brief Time unit conversion utilities
---@description
--- Provides efficient conversion between time units.
--- All conversions are from nanoseconds (internal format).

local M = {}

--- Conversion factors from nanoseconds to target unit
---@type table<TimeUnit, number>
local CONVERSION_FACTORS = {
  ns = 1,
  us = 1e3,
  ms = 1e6,
  s = 1e9,
}

--- Unit suffixes for display
---@type table<TimeUnit, string>
local UNIT_SUFFIXES = {
  ns = "ns",
  us = "us",
  ms = "ms",
  s = "s",
}

--- Convert nanoseconds to target unit
---@param ns number Nanoseconds
---@param unit TimeUnit Target unit
---@return number converted Converted value
---@nodiscard
function M.convert_time(ns, unit)
  local factor = CONVERSION_FACTORS[unit]
  if not factor then
    error(string.format("[lib.lua.time.diff] Invalid unit: %s", tostring(unit)), 2)
  end
  return ns / factor
end

--- Get unit suffix for display
---@param unit TimeUnit Unit
---@return string suffix Unit suffix
---@nodiscard
function M.unit_suffix(unit)
  return UNIT_SUFFIXES[unit] or "ns"
end

--- Convert multiple values at once (performance optimization)
---@param values number[] Array of nanosecond values
---@param unit TimeUnit Target unit
---@return number[] converted Array of converted values
---@nodiscard
function M.convert_batch(values, unit)
  local factor = CONVERSION_FACTORS[unit]
  if not factor then
    error(string.format("[lib.lua.time.diff] Invalid unit: %s", tostring(unit)), 2)
  end

  local result = {}
  for i = 1, #values do
    result[i] = values[i] / factor
  end
  return result
end

return M
