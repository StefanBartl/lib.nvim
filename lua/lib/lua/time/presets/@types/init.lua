---@meta
---@module 'lib.lua.time.presets.@types'

---@class LibTimeRange
---@field from integer
---@field to integer

---@class LibTimePresets
---@field today fun(now?: integer): LibTimeRange
---@field yesterday fun(now?: integer): LibTimeRange
---@field last_week fun(now?: integer): LibTimeRange
---@field this_month fun(now?: integer): LibTimeRange
---@field this_quarter fun(now?: integer): LibTimeRange
---@field this_year fun(now?: integer): LibTimeRange
---@field custom fun(from: integer, to: integer): LibTimeRange|nil, string|nil
