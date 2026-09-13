---@module 'lib.nvim.telemetry.report'
--- Turns collected counters into a report table, and a report table into lines.
---
--- The formatting half is not decoration. A raw dump of counts makes the reader
--- do the analysis; the point of argument profiling is the sentence at the end
--- of an entry — "91 % of calls share one argument — candidate for memoization"
--- — which names the pattern *and* points at the tool that fixes it
--- (`lib.lua.memo`). Without that line the feature is a table of numbers.

local store = require("lib.nvim.telemetry.store")

local M = {}

--- Below this share, "most calls pass the same thing" is not a real finding.
local DOMINANT_SHARE = 0.75

--- Below this many calls it is not a finding either — 3 of 4 is 75 % and means
--- nothing. A hint that fires on noise is a hint that gets ignored.
local DOMINANT_MIN_CALLS = 20

--- Distinct fingerprints kept per entry in the rendered report.
local ARGS_SHOWN = 3

---@param n number
---@return string
local function num(n)
  local s = tostring(math.floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (out:gsub("^%s+", ""))
end

---@param stats Lib.Telemetry.ArgStats
---@param calls integer
---@return { fingerprint: string, count: integer, share: number }[] top, integer other, integer distinct
local function top_args(stats, calls)
  local list = {}
  for fp, n in pairs(stats.values or {}) do
    list[#list + 1] = { fingerprint = fp, count = n, share = calls > 0 and n / calls or 0 }
  end
  table.sort(list, function(a, b)
    if a.count == b.count then
      return a.fingerprint < b.fingerprint
    end
    return a.count > b.count
  end)
  return list, stats.other or 0, stats.distinct or 0
end

---Build the report for one instance's data.
---@param namespace string
---@param data Lib.Telemetry.Data
---@param meta { running: boolean, disabled: boolean, wrapped: integer, modes: table }
---@param opts? Lib.Telemetry.ReportOpts
---@return Lib.Telemetry.Report
function M.build(namespace, data, meta, opts)
  opts = opts or {}

  local days = store.parse_since(opts.since)
  local windowed = days and store.since(data, days) or nil

  local entries, total = {}, 0
  for key, stats in pairs(data.functions or {}) do
    local calls = windowed and (windowed[key] or 0) or (stats.calls or 0)
    if calls > 0 or not windowed then
      local entry = { key = key, calls = calls, errors = stats.errors or 0 }

      local timing = stats.timing
      if timing and (timing.n or 0) > 0 then
        entry.mean_ms = timing.total_ms / timing.n
        entry.min_ms = timing.min_ms
        entry.max_ms = timing.max_ms
      end

      if stats.args then
        -- Argument shares are lifetime shares; the day buckets hold call
        -- counts only. Computing them against a windowed call count would
        -- produce percentages that do not add up, so use the lifetime total.
        local list, other, distinct = top_args(stats.args, stats.calls or 0)
        entry.args, entry.other, entry.distinct = list, other, distinct

        -- `"()"` is the fingerprint of a zero-argument call. It is always
        -- 100 % dominant and never actionable — memoizing a function that
        -- takes no arguments is a different decision entirely.
        local first = list[1]
        if
          first
          and first.fingerprint ~= "()"
          and (stats.calls or 0) >= DOMINANT_MIN_CALLS
          and first.share >= DOMINANT_SHARE
        then
          entry.hint = ("%.0f %% of calls share one argument — candidate for %s"):format(
            first.share * 100,
            "memoization (lib.lua.memo.memo / .lru)"
          )
        end
      end

      entries[#entries + 1] = entry
      total = total + calls
    end
  end

  local sort = opts.sort or "calls"
  table.sort(entries, function(a, b)
    if sort == "name" then
      return a.key < b.key
    elseif sort == "time" then
      return (a.mean_ms or -1) > (b.mean_ms or -1)
    end
    if a.calls == b.calls then
      return a.key < b.key
    end
    return a.calls > b.calls
  end)

  if opts.top and opts.top > 0 then
    for i = #entries, opts.top + 1, -1 do
      entries[i] = nil
    end
  end

  return {
    namespace = namespace,
    running = meta.running,
    disabled = meta.disabled,
    modes = meta.modes,
    wrapped = meta.wrapped,
    started_at = data.started_at,
    sessions = data.sessions or 0,
    total_calls = total,
    since = days and (days .. "d") or nil,
    entries = entries,
  }
end

---@param report Lib.Telemetry.Report
---@return string[]
function M.lines(report)
  local out = {}

  local modes = {}
  if report.modes.args then
    modes[#modes + 1] = "args"
  end
  if report.modes.timing then
    modes[#modes + 1] = "timing"
  end
  if report.modes.errors then
    modes[#modes + 1] = "errors"
  end
  local mode_str = #modes > 0 and ("counting + " .. table.concat(modes, " + ")) or "counting"

  -- `M.disable()` always stops a live instance before persisting, and
  -- `inst.start()` refuses to run while disabled, so "disabled" and
  -- "running" never overlap in practice.
  local state = report.disabled and "disabled" or (report.running and "running" or "stopped")
  out[#out + 1] = ("%s  —  %s"):format(report.namespace, state)
  out[#out + 1] = ("  %s · %s wrapped · %s calls · %d session(s)%s"):format(
    mode_str,
    num(report.wrapped),
    num(report.total_calls),
    report.sessions,
    report.since and (" · last " .. report.since) or ""
  )
  if report.started_at then
    out[#out + 1] = ("  collecting since %s"):format(os.date("%Y-%m-%d %H:%M", report.started_at))
  end
  out[#out + 1] = ""

  if #report.entries == 0 then
    out[#out + 1] = "  (no calls recorded)"
    return out
  end

  local width = 0
  for _, e in ipairs(report.entries) do
    width = math.max(width, #e.key)
  end
  width = math.min(width, 46)

  for _, e in ipairs(report.entries) do
    local line = ("  %-" .. width .. "s %10s calls"):format(e.key:sub(1, width), num(e.calls))
    if e.mean_ms then
      line = line .. ("  %7.2fms avg (%.2f–%.2f)"):format(e.mean_ms, e.min_ms, e.max_ms)
    end
    if e.errors > 0 then
      line = line .. ("  %s error(s)"):format(num(e.errors))
    end
    out[#out + 1] = line

    if e.args then
      local shown = 0
      for _, a in ipairs(e.args) do
        shown = shown + 1
        if shown > ARGS_SHOWN then
          break
        end
        out[#out + 1] = ("      └ %3.0f %%  %s"):format(a.share * 100, a.fingerprint)
      end
      if (e.other or 0) > 0 then
        out[#out + 1] = ("      └ %3.0f %%  <other: %d distinct>"):format(
          e.calls > 0 and (e.other / e.calls * 100) or 0,
          e.distinct or 0
        )
      end
      if e.hint then
        out[#out + 1] = ("      ⓘ %s"):format(e.hint)
      end
    end
  end

  return out
end

M.DOMINANT_SHARE = DOMINANT_SHARE
M.DOMINANT_MIN_CALLS = DOMINANT_MIN_CALLS
M.num = num

return M
