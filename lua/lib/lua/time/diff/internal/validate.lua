---@module 'lib.lua.time.diff.internal.validate'
---@brief Input validation utilities for time diff module
---@description
--- Provides centralized validation for all input parameters.
--- Ensures type safety and proper error messages.

local M = {}

--- Valid time units
---@type table<string, true>
local VALID_UNITS = {
  ns = true,
  us = true,
  ms = true,
  s = true,
}

--- Valid statistical keywords and their aliases
---@type table<string, string>
local STAT_KEYWORDS = {
  average = "average",
  avg = "average",
  fastest = "fastest",
  min = "fastest",
  longest = "longest",
  max = "longest",
  median = "median",
  med = "median",
}

--- Validate time unit parameter
---@param unit any
---@param allow_nil? boolean
---@return boolean valid
---@return TimeUnit|string unit_or_err
---@nodiscard
function M.validate_unit(unit, allow_nil)
  if unit == nil then
    if allow_nil == false then
      return false, "unit is required"
    end
    return true, "ns"
  end

  if type(unit) ~= "string" then
    return false, "unit must be a string"
  end

  if not VALID_UNITS[unit] then
    return false, ("invalid unit: %s (must be ns, us, ms, or s)"):format(unit)
  end

  return true, unit
end

--- Validate checkpoint index
---@param idx any Index to validate
---@param max_idx integer Maximum valid index
---@return boolean valid True if valid
---@return integer|nil index_or_err Valid index or nil
---@return string|nil err Error message if invalid
---@nodiscard
function M.validate_index(idx, max_idx)
  if type(idx) ~= "number" then
    return false, nil, "index must be a number"
  end

  if idx ~= math.floor(idx) then
    return false, nil, "index must be an integer"
  end

  if idx < 1 or idx > max_idx then
    return false, nil, string.format("index out of bounds [1..%d]", max_idx)
  end

  return true, idx, nil
end

--- Resolve interval specifier to keyword or validate as index
---@param spec any Interval specifier
---@param max_idx integer Maximum valid checkpoint index
---@return boolean valid True if valid
---@return "index"|"keyword"|"value"|nil type Type of specifier
---@return integer|string|number|nil resolved Resolved value
---@return string|nil err Error message
---@nodiscard
function M.resolve_interval_spec(spec, max_idx)
  local t = type(spec)

  -- String keyword
  if t == "string" then
    local normalized = STAT_KEYWORDS[spec:lower()]
    if normalized then
      return true, "keyword", normalized, nil
    end
    return false, nil, nil, string.format("unknown keyword: %s", spec)
  end

  -- Number
  if t == "number" then
    -- Small integer → checkpoint index
    if spec == math.floor(spec) and spec >= 1 and spec <= 10 then
      if spec > max_idx then
        return false, nil, nil, string.format("checkpoint index %d not found (max: %d)", spec, max_idx)
      end
      return true, "index", spec, nil
    end

    -- Large number → raw nanosecond value
    if spec >= 0 then
      return true, "value", spec, nil
    end

    return false, nil, nil, "time value must be non-negative"
  end

  return false, nil, nil, string.format("invalid interval specifier type: %s", t)
end

--- Validate label parameter for iterator
---@param label any Label to validate
---@return boolean valid True if valid
---@return string|nil label_or_err Normalized label or error message
---@nodiscard
function M.validate_label(label)
  if label == nil then
    return true, nil
  end

  if type(label) ~= "string" then
    return false, "label must be a string or nil"
  end

  if label == "" then
    return false, "label cannot be empty"
  end

  return true, label
end


--- Validate show_index parameter
---@param show_index any
---@return boolean valid
---@return boolean|string value_or_err
---@nodiscard
function M.validate_show_index(show_index)
  if show_index == nil then
    return true, false
  end

  if type(show_index) ~= "boolean" then
    return false, "show_index must be a boolean or nil"
  end

  return true, show_index
end

return M
