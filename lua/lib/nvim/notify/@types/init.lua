---@meta
---@module 'lib.nvim.notify.@types'

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
