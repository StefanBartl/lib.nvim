---@module 'lib.lua.time.diff.internal.format'
---@brief Output formatting utilities
---@description
--- Provides formatting functions for human-readable output.
--- Handles both compact and pretty-printed formats.

local convert = require("lib.lua.time.diff.internal.convert")
local stats_module = require("lib.lua.time.diff.internal.stats")

local M = {}

--- Format single checkpoint for display
---@param index integer Checkpoint index
---@param elapsed number Elapsed time (ns)
---@param unit TimeUnit Display unit
---@return string formatted Formatted string
---@nodiscard
local function format_checkpoint(index, elapsed, unit)
  local converted = convert.convert_time(elapsed, unit)
  local suffix = convert.unit_suffix(unit)
  return string.format("Check %d: %.3f%s", index, converted, suffix)
end

--- Format statistics summary
---@param stats TimeDiffStats Statistics object
---@param unit TimeUnit Display unit
---@return string[] lines Array of formatted lines
---@nodiscard
local function format_stats_summary(stats, unit)
  local lines = {}

  local fastest = convert.convert_time(stats.min, unit)
  local longest = convert.convert_time(stats.max, unit)
  local avg = convert.convert_time(stats.avg, unit)
  local range = longest - fastest

  local suffix = convert.unit_suffix(unit)

  table.insert(lines, string.format("Fastest: %.3f%s", fastest, suffix))
  table.insert(lines, string.format("Longest: %.3f%s", longest, suffix))
  table.insert(lines, string.format("Average: %.3f%s", avg, suffix))
  table.insert(lines, string.format("Range: %.3f%s", range, suffix))

  return lines
end

--- Generate compact summary string
---@param checks number[] Checkpoint timestamps (ns)
---@param start_time number Start timestamp (ns)
---@param unit TimeUnit Display unit
---@return string summary Compact summary string
---@nodiscard
function M.format_results(checks, start_time, unit)
  if #checks == 0 then
    return "[lib.lua.time.diff] No checkpoints recorded."
  end

  local parts = {}

  -- Format each checkpoint
  for i = 1, #checks do
    local elapsed = checks[i] - start_time
    table.insert(parts, format_checkpoint(i, elapsed, unit))
  end

  -- Add total
  local total = checks[#checks] - start_time
  local converted_total = convert.convert_time(total, unit)
  local suffix = convert.unit_suffix(unit)
  table.insert(parts, string.format("Total: %.3f%s", converted_total, suffix))

  -- Add statistics
  local stats = stats_module.calculate_stats(checks, start_time)
  if stats then
    local stats_lines = format_stats_summary(stats, unit)
    for i = 1, #stats_lines do
      table.insert(parts, stats_lines[i])
    end
  end

  return table.concat(parts, " | ")
end

--- Format table row
---@param index integer Row index
---@param elapsed number Elapsed time (ns)
---@param delta number Delta time (ns)
---@param unit TimeUnit Display unit
---@return string row Formatted table row
---@nodiscard
local function format_table_row(index, elapsed, delta, unit)
  local elapsed_conv = convert.convert_time(elapsed, unit)
  local delta_conv = convert.convert_time(delta, unit)
  return string.format("│ %6d │    %11.3f │    %11.3f │", index, elapsed_conv, delta_conv)
end

--- Format statistics section for pretty output
---@param stats TimeDiffStats Statistics object
---@param unit TimeUnit Display unit
---@param has_stddev boolean Whether to include stddev/CV
---@return string[] lines Array of formatted lines
---@nodiscard
local function format_stats_section(stats, unit, has_stddev)
  local lines = {
    "├──────────────────────────────────────────────┤",
    "│ Statistics:                                  │",
    "├──────────────────────────────────────────────┤",
  }

  local fastest = convert.convert_time(stats.min, unit)
  local longest = convert.convert_time(stats.max, unit)
  local avg = convert.convert_time(stats.avg, unit)
  local med = convert.convert_time(stats.median, unit)
  local range = longest - fastest

  local suffix = convert.unit_suffix(unit)

  table.insert(lines, string.format("│ Fastest Δ: %11.3f%2s                │", fastest, suffix))
  table.insert(lines, string.format("│ Longest Δ: %11.3f%2s                │", longest, suffix))
  table.insert(lines, string.format("│ Average Δ: %11.3f%2s                │", avg, suffix))
  table.insert(lines, string.format("│ Median Δ:  %11.3f%2s                │", med, suffix))
  table.insert(lines, string.format("│ Range:     %11.3f%2s                │", range, suffix))

  if has_stddev then
    local stddev = stats_module.calculate_stddev(stats)
    local cv = stats_module.calculate_cv(stats, stddev)

    if stddev then
      local stddev_conv = convert.convert_time(stddev, unit)
      table.insert(lines, string.format("│ Std Dev:   %11.3f%2s                │", stddev_conv, suffix))
    end

    if cv then
      table.insert(lines, string.format("│ CV:        %11.2f%%                   │", cv))
    end
  end

  return lines
end

--- Generate pretty-printed table
---@param checks number[] Checkpoint timestamps (ns)
---@param start_time number Start timestamp (ns)
---@param unit TimeUnit Display unit
---@return string table Multi-line formatted table
---@nodiscard
function M.format_pretty(checks, start_time, unit)
  if #checks == 0 then
    return "[lib.lua.time.diff] No checkpoints to display."
  end

  local suffix = convert.unit_suffix(unit)

  local lines = {
    "┌────────┬─────────────────┬─────────────────┐",
    string.format("│ Index  │  Elapsed (%2s)  │   Delta (%2s)   │", suffix, suffix),
    "├────────┼─────────────────┼─────────────────┤",
  }

  -- Format data rows
  local prev = start_time
  for i = 1, #checks do
    local elapsed = checks[i] - start_time
    local delta = checks[i] - prev
    prev = checks[i]
    table.insert(lines, format_table_row(i, elapsed, delta, unit))
  end

  -- Add total
  local total = checks[#checks] - start_time
  local total_conv = convert.convert_time(total, unit)
  table.insert(lines, "├────────┴─────────────────┴─────────────────┤")
  table.insert(lines, string.format("│ Total: %11.3f%2s                  │", total_conv, suffix))

  -- Add statistics
  local stats = stats_module.calculate_stats(checks, start_time)
  if stats then
    local stats_lines = format_stats_section(stats, unit, #checks >= 2)
    for i = 1, #stats_lines do
      table.insert(lines, stats_lines[i])
    end
  end

  table.insert(lines, "└──────────────────────────────────────────────┘")

  return table.concat(lines, "\n")
end

--- Format iterator output
---@param index integer Checkpoint index
---@param time_val number Time value (already converted)
---@param label string|nil Custom label
---@param show_index boolean Whether to show index
---@param suffix string Unit suffix
---@return string|number formatted Formatted string or raw number
---@nodiscard
function M.format_iterator_output(index, time_val, label, show_index, suffix)
  if not label then
    return time_val
  end

  if show_index then
    return string.format("%s %d: %.3f%s", label, index, time_val, suffix)
  else
    return string.format("%s %.3f%s", label, time_val, suffix)
  end
end

return M
