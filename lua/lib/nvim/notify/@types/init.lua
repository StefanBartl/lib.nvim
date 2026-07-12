---@meta
---@module 'lib.nvim.notify.@types'

--- A concrete vim.log.levels value (0-5).
---@alias LogLevelNumber integer
--- A log level as accepted by resolve_log_level: a number (0-5), a level name
--- ("trace"/"debug"/"info"/"warn"/"error"/"off", case-insensitive), or a
--- vim.log.levels table value.
---@alias LogLevel LogLevelNumber|string

---@class Lib.Notify.Notifier
---@field notify? fun(msg: string, level?: integer, opts?: table)
---@field info? fun(msg: string, opts?: table)
---@field warn? fun(msg: string, opts?: table)
---@field error? fun(msg: string, opts?: table)
---@field debug? fun(msg: string, opts?: table)

---@alias Lib.Notify.CreateFN fun(prefix: string): Lib.Notify.Notifier

---@class Lib.Notify.Safe
---@field schedule fun(msg: string, level?: integer, opts?: table): nil
---@field defer fun(msg: string, level?: integer, opts?: table, delay_ms?: integer): nil
---@field wrap fun(): fun(msg: string, level?: integer, opts?: table)
---@field notify fun(msg: string, level?: integer, opts?: table, mode?: '"schedule"'|'"defer"'|'"wrap"', delay_ms?: integer): nil
---@field create_safe fun(prefix: string): Lib.Notify.Notifier

---@class Lib.Notify
---@field create Lib.Notify.CreateFN
---@field safe Lib.Notify.Safe
---@field resolve_log_level fun(level?: LogLevel, default?: LogLevelNumber): integer # Resolve log level

return {}
