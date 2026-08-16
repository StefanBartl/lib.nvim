---@meta
---@module 'lib.nvim.fs.watch.@types'

---Options for `require("lib.nvim.fs.watch").start`.
---@class Lib.Fs.Watch.Opts
---@field debounce_ms? integer Quiet period before `on_change` fires (default `200`)
---@field recursive? boolean Watch subdirectories too (default `false`; Linux inotify ignores this — see README)

---Handle returned by `require("lib.nvim.fs.watch").start`.
---@class Lib.Fs.Watch.Handle
---@field stop fun() Cancel the pending debounce and close the underlying `fs_event` handle; safe to call more than once

---@class Lib.Fs.Watch
---@field start fun(path: string, on_change: fun(path: string, filename: string|nil, events: table), opts?: Lib.Fs.Watch.Opts): Lib.Fs.Watch.Handle|nil, string|nil

return {}
