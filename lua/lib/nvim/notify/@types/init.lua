---@meta
---@module 'lib.nvim.notify.@types'

--- A concrete vim.log.levels value (0-5).
---
--- Namespaced, unlike the bare `LogLevelNumber` this used to be: the author's
--- nvim config declares a global alias of that name too, and two global
--- aliases with one name are a `duplicate-doc-alias` in both files.
---@alias Lib.Notify.LogLevelNumber integer
--- A log level as accepted by resolve_log_level: a number (0-5), a level name
--- ("trace"/"debug"/"info"/"warn"/"error"/"off", case-insensitive), or a
--- vim.log.levels table value.
---@alias Lib.Notify.LogLevel Lib.Notify.LogLevelNumber|string

--- Every field is set by `create()`, so none of them is optional -- marking
--- them so only forced a nil check on `notify().info(...)` at every call site.
---@class Lib.Notify.Notifier
---@field notify fun(msg: string, level?: integer, opts?: table)
---@field info fun(msg: string, opts?: table)
---@field warn fun(msg: string, opts?: table)
---@field error fun(msg: string, opts?: table)
---@field debug fun(msg: string, opts?: table)

---@alias Lib.Notify.CreateFN fun(prefix: string): Lib.Notify.Notifier

---Which scheduling strategy `Lib.Notify.Safe.notify` uses to reach the main loop.
---@alias Lib.Notify.Safe.ScheduleMode
---| '"schedule"' # Immediate scheduling via vim.schedule (default)
---| '"defer"'    # Delayed scheduling via vim.defer_fn with a configurable delay
---| '"wrap"'     # A pre-wrapped function, for repeated calls

---Notifier returned by `Lib.Notify.Safe.create_safe(prefix)`. Same shape as
---`Lib.Notify.Notifier`, but every method schedules via `vim.schedule` so it is
---safe to call from a fast-event context.
---@class Lib.Notify.Safe.Notifier
---@field notify fun(msg: string, level?: integer, opts?: table)
---@field info fun(msg: string, opts?: table)
---@field warn fun(msg: string, opts?: table)
---@field error fun(msg: string, opts?: table)
---@field debug fun(msg: string, opts?: table)

---@class Lib.Notify.Safe
---@field schedule fun(msg: string, level?: integer, opts?: table): nil
---@field defer fun(msg: string, level?: integer, opts?: table, delay_ms?: integer): nil
---@field wrap fun(): fun(msg: string, level?: integer, opts?: table)
---@field notify fun(msg: string, level?: integer, opts?: table, mode?: Lib.Notify.Safe.ScheduleMode, delay_ms?: integer): nil
---@field create_safe fun(prefix: string): Lib.Notify.Safe.Notifier

---@class Lib.Notify
---@field create Lib.Notify.CreateFN
---@field safe Lib.Notify.Safe

return {}
