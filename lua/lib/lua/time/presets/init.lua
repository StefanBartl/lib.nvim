---@module 'lib.lua.time.presets'
--- Date-range preset resolver, pure Lua (`os.time`/`os.date`), no `vim.*`.
---
--- Each preset returns `{ from, to }` unix timestamps (integers): start of
--- the period and end of the period (or "now" for the current, still-open
--- period). All presets accept an optional `now` (unix timestamp) for
--- testability/reproducibility; it defaults to `os.time()` at call time.
---
--- `last_week` returns the last 7 full days ending at the start of today
--- (i.e. `[today-7d 00:00, today 00:00)`), not the previous Mon-Sun
--- calendar week — documented here since either reading is defensible.

---@type LibTimePresets
local M = {}

local SECONDS_PER_DAY = 86400

---@param ts integer
---@return osdate
local function to_date_table(ts)
  return os.date("*t", ts)
end

---Start-of-day timestamp for the calendar day containing `ts`.
---@param ts integer
---@return integer
local function start_of_day(ts)
  local t = to_date_table(ts)
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

---@nodiscard
---@param now? integer Defaults to `os.time()`
---@return LibTimeRange
function M.today(now)
  now = now or os.time()
  return { from = start_of_day(now), to = now }
end

---@nodiscard
---@param now? integer Defaults to `os.time()`
---@return LibTimeRange
function M.yesterday(now)
  now = now or os.time()
  local today_start = start_of_day(now)
  return { from = today_start - SECONDS_PER_DAY, to = today_start }
end

---Last 7 full days, ending at the start of today (does not include today).
---@nodiscard
---@param now? integer Defaults to `os.time()`
---@return LibTimeRange
function M.last_week(now)
  now = now or os.time()
  local today_start = start_of_day(now)
  return { from = today_start - 7 * SECONDS_PER_DAY, to = today_start }
end

---@nodiscard
---@param now? integer Defaults to `os.time()`
---@return LibTimeRange
function M.this_month(now)
  now = now or os.time()
  local t = to_date_table(now)
  local from = os.time({ year = t.year, month = t.month, day = 1, hour = 0, min = 0, sec = 0 })
  return { from = from, to = now }
end

---@nodiscard
---@param now? integer Defaults to `os.time()`
---@return LibTimeRange
function M.this_quarter(now)
  now = now or os.time()
  local t = to_date_table(now)
  local quarter_start_month = (math.floor((t.month - 1) / 3) * 3) + 1
  local from = os.time({ year = t.year, month = quarter_start_month, day = 1, hour = 0, min = 0, sec = 0 })
  return { from = from, to = now }
end

---@nodiscard
---@param now? integer Defaults to `os.time()`
---@return LibTimeRange
function M.this_year(now)
  now = now or os.time()
  local t = to_date_table(now)
  local from = os.time({ year = t.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
  return { from = from, to = now }
end

---Trivial passthrough/validation helper for symmetry with the presets.
---@nodiscard
---@param from integer
---@param to integer
---@return LibTimeRange|nil range
---@return string|nil err
function M.custom(from, to)
  if type(from) ~= "number" or type(to) ~= "number" then
    return nil, "from/to must be numbers"
  end
  if from > to then
    return nil, "from must be <= to"
  end
  return { from = from, to = to }
end

return M
