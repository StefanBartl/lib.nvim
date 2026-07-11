---@meta
---@module 'lib.nvim.logger.@types'

---@alias Lib.Logger.LevelInput integer|string # vim.log.levels number or "trace"/"debug"/"info"/"warn"/"error"/"off"

---One recorded log entry.
---@class Lib.Logger.Record
---@field ts integer          # os.time() for coarse ordering / display
---@field mono integer        # vim.uv.hrtime() nanoseconds, for precise ordering
---@field iso string          # human timestamp, e.g. "2026-07-05 08:43:05"
---@field level integer       # vim.log.levels value
---@field level_name string   # "TRACE".."ERROR"
---@field scope string        # logger name
---@field msg string
---@field ctx table?          # structured context (sanitized before any sink)
---@field tags string[]?      # optional tags attached to this call
---@field src string?         # "file:line" (only when the logger has src=true)

---Options for `require("lib.nvim.logger").new(opts)`.
---@class Lib.Logger.Options
---@field name? string                 # scope / prefix (default "lib")
---@field level? Lib.Logger.LevelInput  # min level to RECORD (default DEBUG)
---@field notify_level? Lib.Logger.LevelInput # min level to also vim.notify (default WARN)
---@field file? string|false           # file-sink path; nil = stdpath default, false = disabled
---@field capture? boolean             # install crash capture (VimLeavePre flush) (default true)
---@field history? integer             # ring-buffer size (default 200)
---@field src? boolean                 # capture "file:line" per record (small cost) (default false)
---@field redact? string[]             # context keys to scrub before logging

---Per-call options (3rd argument to log.<level>).
---@class Lib.Logger.CallOpts
---@field tags? string[]   # tags for this call (for later enable/disable)
---@field to? string       # write this call to a different file (per-call override)
---@field notify? boolean  # force (true) or suppress (false) the notify sink for this call

---A logger instance (returned by `.new`).
--- Every `<level>` method's `ctx` may be a table OR a thunk returning one
--- (resolved only when the level is active, so expensive context is free when
--- the level is off).
---@alias Lib.Logger.Ctx table|(fun(): table)
---@class Lib.Logger.Instance
---@field name string
---@field trace fun(msg: string, ctx?: Lib.Logger.Ctx, opts?: Lib.Logger.CallOpts)
---@field debug fun(msg: string, ctx?: Lib.Logger.Ctx, opts?: Lib.Logger.CallOpts)
---@field info  fun(msg: string, ctx?: Lib.Logger.Ctx, opts?: Lib.Logger.CallOpts)
---@field warn  fun(msg: string, ctx?: Lib.Logger.Ctx, opts?: Lib.Logger.CallOpts)
---@field error fun(msg: string, ctx?: Lib.Logger.Ctx, opts?: Lib.Logger.CallOpts)
---@field log   fun(level: Lib.Logger.LevelInput, msg: string, ctx?: Lib.Logger.Ctx, opts?: Lib.Logger.CallOpts)
---@field set_enabled fun(on: boolean)   # per-logger master switch
---@field is_enabled fun(): boolean
---@field set_level fun(level: Lib.Logger.LevelInput)
---@field guard fun(fn: function, name?: string): function  # xpcall wrapper: log+flush on error, re-raises
---@field wrap fun(fn: function, name?: string): function   # xpcall wrapper: log+flush on error, swallows
---@field flush fun(): boolean            # write the in-memory ring to the file sink now
---@field snapshot fun(): Lib.Logger.Record[]  # copy of the current ring buffer
---@field clear fun()                     # empty the ring buffer
---@field once fun(key: string, level: Lib.Logger.LevelInput, msg: string, ctx?: table): boolean # log key at most once
---@field timer fun(label: string, level?: Lib.Logger.LevelInput): fun(ctx?: table)  # returns stop() that logs elapsed ms
---@field assert fun(cond: any, msg: string, ctx?: table): any  # log+raise (through guard) when falsy

---The `lib.nvim.logger` module.
---@class Lib.Logger
---@field new fun(opts?: Lib.Logger.Options): Lib.Logger.Instance
---@field setup fun(opts?: table)          # global defaults + switches
---@field set_enabled fun(on: boolean)     # GLOBAL master switch (de-facto zero cost when off)
---@field is_enabled fun(): boolean
---@field set_level fun(level?: Lib.Logger.LevelInput) # global min-level override (nil clears)
---@field disable_tag fun(tag: string)     # suppress every record carrying this tag
---@field enable_tag fun(tag: string)
---@field only_tags fun(tags?: string[])   # whitelist: keep only records with a listed tag (nil clears)
---@field tags fun(): { disabled: string[], only: string[]|nil }
---@field loggers fun(): Lib.Logger.Instance[]  # all live loggers (for :checkhealth / inspector)

return {}
