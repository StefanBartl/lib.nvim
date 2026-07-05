---@meta
---@module 'lib.nvim.progress.@types'

---@alias Lib.Progress.Style "auto"|"notify"|"statusline"|"fidget"|"float"

---@class Lib.Progress.Opts
---@field title? string Prefix shown in front of every message (default `""`)
---@field style? Lib.Progress.Style Renderer selection (default `"auto"`)
---@field delay_ms? integer Suppress the indicator until it has run this long (default `150`)
---@field level? integer `vim.log.levels.*` used by the `"notify"` style (default `INFO`)

---Fields accepted by `Handle:update(...)`. All fields are optional and merge
---into the handle's running state; a field left `nil` keeps its previous value.
---@class Lib.Progress.Fields
---@field text? string Free-form status text
---@field current? integer Items processed so far
---@field total? integer Total items expected (enables a percentage/ratio)

---Snapshot passed to a style implementation on every render.
---@class Lib.Progress.Spec : Lib.Progress.Fields
---@field title string

---A style implementation renders a `Lib.Progress.Spec` through one concrete UI.
---`state` is opaque, owned by the style, and threaded back on every call.
---`request_cancel` is provided so an interactive style (e.g. "float") can let
---the user trigger cancellation from within its own UI; most styles ignore it.
---@class Lib.Progress.StyleImpl
---@field start fun(spec: Lib.Progress.Spec, opts: Lib.Progress.Opts, request_cancel: fun()): any
---@field update fun(state: any, spec: Lib.Progress.Spec, opts: Lib.Progress.Opts): any
---@field finish fun(state: any, spec: Lib.Progress.Spec, opts: Lib.Progress.Opts): nil
---@field cancel fun(state: any, spec: Lib.Progress.Spec, opts: Lib.Progress.Opts): nil

---Handle returned by `require("lib.nvim.progress").create(opts)`.
---@class Lib.Progress.Handle
---@field cancelled boolean true once `request_cancel()` has fired
---@field update fun(self: Lib.Progress.Handle, fields: Lib.Progress.Fields): nil
---@field finish fun(self: Lib.Progress.Handle, text?: string): nil
---@field cancel fun(self: Lib.Progress.Handle, text?: string): nil
---@field on_cancel fun(self: Lib.Progress.Handle, fn: fun()): nil
---@field request_cancel fun(self: Lib.Progress.Handle): nil

---@class Lib.Progress
---@field create fun(opts?: Lib.Progress.Opts): Lib.Progress.Handle

return {}
