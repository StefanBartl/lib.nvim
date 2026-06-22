---@module 'lib.lua.time.diff'
---@brief High-precision time measurement and interval tracking module.
---@description
--- Provides a lightweight, reusable timer object for measuring elapsed time
--- between code sections. Each call to `require("lib.lua.time.diff")` returns a
--- fresh timer instance with independent state.
---
--- Key features:
--- - Nanosecond precision via `vim.uv.hrtime()` (default output)
--- - Multiple checkpoints with automatic interval calculation
--- - Dynamic property generation (diff.first, diff.second, ..., diff.last)
--- - Pretty-printed summary tables with configurable units
--- - Iterator support with custom labels and index display
--- - Metatable-based callable interface (`print(diff)`, `diff()`)
--- - Memoized statistics calculations for performance
--- - Type-safe input validation
---
--- Usage:
---   local diff = require("lib.lua.time.diff")
---   diff.start()
---   -- ... code block 1 ...
---   local t1 = diff.check()         -- First interval (nanoseconds)
---   local t2_ms = diff.check("ms")  -- Second interval (milliseconds)
---   print(diff.first)                -- Access first checkpoint
---   print(diff.last)                 -- Access last checkpoint
---   print(diff("ms"))                -- Print all checkpoints in ms
---   print(diff.pretty("ms"))         -- Formatted table in ms

-- Load internal modules
local validate = require("lib.lua.time.diff.internal.validate")
local convert = require("lib.lua.time.diff.internal.convert")
local stats_module = require("lib.lua.time.diff.internal.stats")
local format = require("lib.lua.time.diff.internal.format")

local M = {}

--- Ordinal names for dynamic properties
---@type string[]
local ORDINALS = {
  "first",
  "second",
  "third",
  "fourth",
  "fifth",
  "sixth",
  "seventh",
  "eighth",
  "ninth",
  "tenth",
}

--- Create a new timer instance with isolated state.
--- Automatically starts timing on creation.
---@return Lib.Time.TimeDiff
---@nodiscard
local function create_timer()
  local instance = {
    _start = 0,
    _checks = {},
    _index = 0,
    _iter_label = nil,
    _iter_show_index = false,
    _stats_cache = nil, -- Memoized stats
  }

  --- Start or reset the timer.
  --- Clears all previous checkpoints and sets a new baseline.
  ---@return nil
  function instance.start()
    instance._start = vim.uv.hrtime()
    instance._checks = {}
    instance._index = 0
    instance._iter_label = nil
    instance._iter_show_index = false
    instance._stats_cache = nil
  end

  --- Record a checkpoint and return elapsed time since start.
  --- Can be called multiple times to measure intermediate intervals.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number elapsed Elapsed time in specified unit
  ---@nodiscard
  function instance.check(unit)
    -- Validate timer started
    if instance._start == 0 then
      error("[lib.lua.time.diff] Timer not started. Call `start()` first.", 2)
    end

    -- Validate unit
    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    -- Record checkpoint
    local now = vim.uv.hrtime()
    table.insert(instance._checks, now)

    -- Invalidate stats cache
    instance._stats_cache = nil

    local elapsed_ns = now - instance._start
    return convert.convert_time(elapsed_ns, validated_unit)
  end

  --- Get total elapsed time since start.
  --- Equivalent to the last checkpoint if `check()` was called.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil total Total time in specified unit, or nil if no checkpoints exist
  ---@nodiscard
  function instance.result(unit)
    if #instance._checks == 0 then
      return nil
    end

    -- Validate unit
    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    local last = instance._checks[#instance._checks]
    local elapsed_ns = last - instance._start
    return convert.convert_time(elapsed_ns, validated_unit)
  end

  --- Get elapsed time of a specific checkpoint by index.
  --- Index is 1-based (Lua convention).
  ---@param idx integer Checkpoint index (1 = first check, 2 = second, etc.)
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil elapsed Elapsed time in specified unit, or nil if index out of bounds
  ---@nodiscard
  function instance.get(idx, unit)
    -- Validate index
    local ok, validated_idx, _ = validate.validate_index(idx, #instance._checks)
    if not ok then
      return nil
    end

    -- Validate unit
    ok, unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", unit), 2)
    end

    local elapsed_ns = instance._checks[validated_idx] - instance._start
    return convert.convert_time(elapsed_ns, unit)
  end

  --- Get or compute cached statistics
  ---@return TimeDiffStats|nil stats Statistics object or nil
  ---@nodiscard
  local function get_stats()
    if not instance._stats_cache then
      instance._stats_cache = stats_module.calculate_stats(instance._checks, instance._start)
    end
    return instance._stats_cache
  end

  --- Get the fastest (minimum) interval between checkpoints.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil fastest Fastest interval, or nil if fewer than 1 checkpoint
  ---@nodiscard
  function instance.fastest(unit)
    local stats = get_stats()
    if not stats then
      return nil
    end

    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    return convert.convert_time(stats.min, validated_unit)
  end

  --- Get the longest (maximum) interval between checkpoints.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil longest Longest interval, or nil if fewer than 1 checkpoint
  ---@nodiscard
  function instance.longest(unit)
    local stats = get_stats()
    if not stats then
      return nil
    end

    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    return convert.convert_time(stats.max, validated_unit)
  end

  --- Get the average interval between checkpoints.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil average Average interval, or nil if fewer than 1 checkpoint
  ---@nodiscard
  function instance.average(unit)
    local stats = get_stats()
    if not stats then
      return nil
    end

    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    return convert.convert_time(stats.avg, validated_unit)
  end

  --- Get the median interval between checkpoints.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil median Median interval, or nil if fewer than 1 checkpoint
  ---@nodiscard
  function instance.median(unit)
    local stats = get_stats()
    if not stats then
      return nil
    end

    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    return convert.convert_time(stats.median, validated_unit)
  end

  --- Get standard deviation of intervals between checkpoints.
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil stddev Standard deviation, or nil if fewer than 2 checkpoints
  ---@nodiscard
  function instance.stddev(unit)
    if #instance._checks < 2 then
      return nil
    end

    local stats = get_stats()
    if not stats then
      return nil
    end

    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    local stddev_ns = stats_module.calculate_stddev(stats)
    if not stddev_ns then
      return nil
    end

    return convert.convert_time(stddev_ns, validated_unit)
  end

  --- Get coefficient of variation (CV) as percentage.
  ---@return number|nil cv Coefficient of variation (%), or nil if fewer than 2 checkpoints
  ---@nodiscard
  function instance.cv()
    local stats = get_stats()
    if not stats then
      return nil
    end

    local stddev_ns = stats_module.calculate_stddev(stats)
    return stats_module.calculate_cv(stats, stddev_ns)
  end

  --- Calculate difference between two intervals.
  ---@param iv1 TimeDiffIntervalSpec First interval (index, keyword, or value)
  ---@param iv2 TimeDiffIntervalSpec Second interval (index, keyword, or value)
  ---@param unit? TimeUnit Unit for return value (default: "ns")
  ---@return number|nil diff Absolute difference, or nil if invalid input
  ---@nodiscard
  function instance.calc_diff(iv1, iv2, unit)
    -- Validate unit
    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    --- Resolve interval spec to nanosecond value
    ---@param spec TimeDiffIntervalSpec
    ---@return string|number|nil value_ns
    local function resolve_value(spec)
      local valid, spec_type, resolved, err =
        validate.resolve_interval_spec(spec, #instance._checks)

      if not valid then
        error(string.format("[lib.lua.time.diff] %s", err), 3)
      end

      if spec_type == "index" then
        return instance._checks[resolved] - instance._start
      elseif spec_type == "keyword" then
        local stats = get_stats()
        if not stats then
          return nil
        end

        if resolved == "average" then
          return stats.avg
        elseif resolved == "fastest" then
          return stats.min
        elseif resolved == "longest" then
          return stats.max
        elseif resolved == "median" then
          return stats.median
        end
      elseif spec_type == "value" then
        return resolved
      end

      return nil
    end

    local val1 = resolve_value(iv1)
    local val2 = resolve_value(iv2)

    if not val1 or not val2 then
      return nil
    end

    local diff_ns = math.abs(val1 - val2)
    return convert.convert_time(diff_ns, validated_unit)
  end

  --- Iterator: Returns the next checkpoint sequentially.
  ---@param label? string Custom label for this specific call (overrides iterator label)
  ---@param unit? TimeUnit Unit for time value (default: "ns")
  ---@return string|number|nil output Formatted string if label set, raw number otherwise, or nil if exhausted
  ---@nodiscard
  function instance.next(label, unit)
    -- Validate label
    if label ~= nil then
      local ok, validated_label = validate.validate_label(label)
      if not ok then
        error(string.format("[lib.lua.time.diff] %s", validated_label), 2)
      end
      label = validated_label
    end

    -- Validate unit
    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    instance._index = instance._index + 1
    if instance._index > #instance._checks then
      instance._index = 0
      return nil
    end

    local time_val = instance.get(instance._index, validated_unit)
    if not time_val then
      return nil
    end
    local effective_label = label or instance._iter_label
    local suffix = convert.unit_suffix(validated_unit)

    return format.format_iterator_output(
      instance._index,
      time_val,
      effective_label,
      instance._iter_show_index,
      suffix
    )
  end

  --- Reset the iterator to the beginning.
  ---@param label? string Custom label to prepend to each iterator output
  ---@param show_index? boolean Whether to include checkpoint index in output
  ---@return nil
  function instance.reset_iterator(label, show_index)
    -- Validate label
    if label ~= nil then
      local ok, validated_label = validate.validate_label(label)
      if not ok then
        error(string.format("[lib.lua.time.diff] %s", validated_label), 2)
      end
      label = validated_label
    end

    -- Validate show_index
    local val, err = validate.validate_show_index(show_index)
    if not val then
      error(string.format("[lib.lua.time.diff] %s", err), 2)
    end

    instance._index = 0
    instance._iter_label = label
    instance._iter_show_index = val
  end

  --- Generate a summary string with all checkpoint times and statistics.
  ---@param unit? TimeUnit Unit for time values (default: "ns")
  ---@return string summary Human-readable summary
  ---@nodiscard
  function instance.results(unit)
    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    return format.format_results(instance._checks, instance._start, validated_unit)
  end

  --- Generate a pretty-printed table suitable for `:messages` or notify.
  ---@param unit? TimeUnit Unit for time values (default: "ns")
  ---@return string formatted Multi-line formatted table
  ---@nodiscard
  function instance.pretty(unit)
    local ok, validated_unit = validate.validate_unit(unit, true)
    if not ok then
      error(string.format("[lib.lua.time.diff] %s", validated_unit), 2)
    end

    return format.format_pretty(instance._checks, instance._start, validated_unit)
  end

  --- Metatable: Makes the instance callable and supports dynamic properties.
  ---@return string summary
  setmetatable(instance, {
    __call = function(_, unit)
      return instance.results(unit)
    end,
    __tostring = function()
      return instance.results()
    end,
    __index = function(tbl, key)
      -- Handle ordinal property access: first, second, third, ..., last
      for i = 1, #ORDINALS do
        if key == ORDINALS[i] then
          return instance.get(i)
        end
      end

      if key == "last" then
        return instance.result()
      end

      -- Fallback to raw table access for private/public fields
      return rawget(tbl, key)
    end,
  })

  -- Auto-start on creation
  instance.start()

  ---@type Lib.Time.TimeDiff
  return instance
end

--- Factory function: Returns a new timer instance.
--- Each call creates an independent timer with its own state.
---@return Lib.Time.TimeDiff
---@nodiscard
setmetatable(M, {
  __call = function()
    return create_timer()
  end,
})

return M
