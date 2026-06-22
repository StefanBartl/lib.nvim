---@module 'lib.lua.time.diff.internal.stats'
---@brief Statistical calculations for time intervals
---@description
--- Provides efficient statistical analysis of checkpoint intervals.
--- All calculations operate on deltas (intervals between checkpoints).

local memo = require("lib.lua.memo")

local M = {}

-- Types: see @types/init.lua (TimeDiffStats).

--- Calculate deltas from checkpoint timestamps
---@param checks number[] Checkpoint timestamps (ns)
---@param start_time number Start timestamp (ns)
---@return number[] deltas Array of intervals
---@nodiscard
local function calculate_deltas(checks, start_time)
  if #checks == 0 then
    return {}
  end

  local deltas = {}
  local prev = start_time

  for i = 1, #checks do
    deltas[i] = checks[i] - prev
    prev = checks[i]
  end

  return deltas
end

--- Calculate min, max, sum in single pass
---@param deltas number[] Array of intervals
---@return number min Minimum value
---@return number max Maximum value
---@return number sum Sum of all values
---@nodiscard
local function calculate_min_max_sum(deltas)
  local min_val = math.huge
  local max_val = -math.huge
  local sum_val = 0

  for i = 1, #deltas do
    local d = deltas[i]
    if d < min_val then min_val = d end
    if d > max_val then max_val = d end
    sum_val = sum_val + d
  end

  return min_val, max_val, sum_val
end

--- Calculate median from sorted array
---@param sorted_deltas number[] Sorted array of intervals
---@return number median Median value
---@nodiscard
local function calculate_median(sorted_deltas)
  local n = #sorted_deltas
  if n == 0 then
    return 0
  end

  local mid = math.floor(n / 2)
  if n % 2 == 0 then
    return (sorted_deltas[mid] + sorted_deltas[mid + 1]) / 2
  else
    return sorted_deltas[mid + 1]
  end
end

--- Calculate all statistics for checkpoints
---@param checks number[] Checkpoint timestamps (ns)
---@param start_time number Start timestamp (ns)
---@return TimeDiffStats|nil stats Statistics object or nil if no checkpoints
---@nodiscard
function M.calculate_stats(checks, start_time)
  if #checks == 0 then
    return nil
  end

  -- Calculate deltas
  local deltas = calculate_deltas(checks, start_time)

  -- Calculate min, max, sum in single pass
  local min_val, max_val, sum_val = calculate_min_max_sum(deltas)

  -- Calculate average
  local avg_val = sum_val / #deltas

  -- Calculate median (requires sorting)
  local sorted_deltas = {}
  for i = 1, #deltas do
    sorted_deltas[i] = deltas[i]
  end
  table.sort(sorted_deltas)

  local median_val = calculate_median(sorted_deltas)

  return {
    min = min_val,
    max = max_val,
    avg = avg_val,
    median = median_val,
    sum = sum_val,
    count = #deltas,
    deltas = deltas,
  }
end

--- Calculate standard deviation
---@param stats TimeDiffStats Statistics object
---@return number|nil stddev Standard deviation or nil if insufficient data
---@nodiscard
function M.calculate_stddev(stats)
  if not stats or stats.count < 2 then
    return nil
  end

  local variance = 0
  for i = 1, #stats.deltas do
    local diff = stats.deltas[i] - stats.avg
    variance = variance + (diff * diff)
  end
  variance = variance / stats.count

  return math.sqrt(variance)
end

--- Calculate coefficient of variation
---@param stats TimeDiffStats Statistics object
---@param stddev number Standard deviation
---@return number|nil cv Coefficient of variation (%) or nil if avg is zero
---@nodiscard
function M.calculate_cv(stats, stddev)
  if not stats or stats.avg == 0 or not stddev then
    return nil
  end

  return (stddev / stats.avg) * 100
end

--- Create memoized stats calculator
--- Caches results based on checkpoint array reference
---@return fun(checks: number[], start_time: number): TimeDiffStats|nil
---@nodiscard
function M.create_memoized_calculator()
  return memo.fn(M.calculate_stats, {
    max_size = 100,
    -- Use checks array length as cache key component
    key_fn = function(checks, start_time)
      return string.format("%d:%d", #checks, start_time)
    end,
  })
end

return M
