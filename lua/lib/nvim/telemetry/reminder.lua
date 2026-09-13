---@module 'lib.nvim.telemetry.reminder'
--- Tells you, once, that enough data has piled up to be worth reading.
---
--- The failure mode this feature invites is being switched on and forgotten:
--- it keeps costing overhead for months and the data never gets looked at. So
--- once a threshold is crossed the module says so — and says it *actionably*,
--- naming the exact commands for reading and stopping. A reminder that says
--- "you have data" without saying how to look at it just moves the forgetting
--- one step later.
---
--- Three rules, each with a reason:
---   - Checked where work already happens (flush time, `VimEnter`), never on
---     the hot path. A reminder a few minutes late costs nothing; a clock read
---     per wrapped call costs exactly what this design avoids.
---   - Fires once per threshold and persists that it fired, in the same cache
---     entry as the counts. A reminder that reappears every session is a nag,
---     and a nag gets muted.
---   - Escalates once, then stops for good. Two messages over months is a
---     reminder; more is nagging.

local M = {}

M.DEFAULTS = { days = 7, calls = 50000 }

--- Multiple of the configured duration at which the single follow-up fires.
local ESCALATE_FACTOR = 4

---@param data Lib.Telemetry.Data
---@return integer
local function total_calls(data)
  local n = 0
  for _, stats in pairs(data.functions or {}) do
    n = n + (stats.calls or 0)
  end
  return n
end

---@param data Lib.Telemetry.Data
---@return integer
local function days_collected(data)
  return math.floor((os.time() - (data.started_at or os.time())) / 86400)
end

---@param data Lib.Telemetry.Data
---@return integer
local function fn_count(data)
  local n = 0
  for _ in pairs(data.functions or {}) do
    n = n + 1
  end
  return n
end

---Decide whether a reminder is due, and mark it as fired.
---
---Returns `nil` when nothing is due. Mutates `data.reminded` on a hit, so the
---caller only has to flush.
---@param namespace string
---@param data Lib.Telemetry.Data
---@param config Lib.Telemetry.RemindAfter|false|nil
---@return string|nil message
function M.check(namespace, data, config)
  if config == false then
    return nil
  end

  local days = (config and config.days) or M.DEFAULTS.days
  local calls = (config and config.calls) or M.DEFAULTS.calls

  local have_days = days_collected(data)
  local have_calls = total_calls(data)

  data.reminded = data.reminded or {}

  local stage
  if not data.reminded.first then
    if (days and have_days >= days) or (calls and have_calls >= calls) then
      stage = "first"
    end
  elseif not data.reminded.escalated then
    if days and have_days >= days * ESCALATE_FACTOR then
      stage = "escalated"
    end
  end

  if not stage then
    return nil
  end
  data.reminded[stage] = true

  local lead = stage == "first" and "has been collecting for %d day(s)"
    or "is *still* collecting after %d day(s)"

  return table.concat({
    ("%s "):format(namespace) .. lead:format(have_days),
    (" (%d calls, %d functions)."):format(have_calls, fn_count(data)),
    (" Review with :LibTelemetry %s — stop with :LibTelemetry stop."):format(namespace),
  })
end

M.ESCALATE_FACTOR = ESCALATE_FACTOR
M.total_calls = total_calls
M.days_collected = days_collected

return M
