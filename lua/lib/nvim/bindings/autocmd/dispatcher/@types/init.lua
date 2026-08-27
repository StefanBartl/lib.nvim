---@meta
---@module 'lib.nvim.bindings.autocmd.dispatcher.@types'

--- Passed to every matched handler on dispatch.
---@class Lib.Autocmd.Dispatcher.Ctx
---@field ev Lib.Autocmd.Args Raw autocmd event args
---@field buf integer
---@field key string The concrete key this event resolved to (e.g. a filetype)
---@field context any Result of `opts.context(ev)`, if `opts.context` was given; nil otherwise

---@alias Lib.Autocmd.Dispatcher.HandlerFn fun(ctx: Lib.Autocmd.Dispatcher.Ctx)

--- A lazily-loaded handler: `load` is required (and called) only once its key
--- actually matches an event — the module's own top-level code is expected to
--- do the real work as a side effect of being loaded/called.
---@class Lib.Autocmd.Dispatcher.HandlerSpec
---@field load Lib.Autocmd.Dispatcher.HandlerFn
---@field priority? integer Lower runs first; default 0. Ties broken by registration order.
---@field once? boolean Run at most once per buffer (not once-globally, unlike native `once`)
---@field owner? string Whoever registered it, so `unregister(owner)` can take it back out — required for anything with a setup/teardown cycle.
---@field desc? string What this handler does; the "What" column of the generated bindings table.

--- One registered handler, as `handle.handlers()` reports it.
---@class Lib.Autocmd.Dispatcher.HandlerInfo
---@field keys string[]
---@field owner string|nil
---@field desc string|nil
---@field priority integer
---@field once boolean
---@field src string  # "file:line" of the `register()` call

--- One dispatcher, as `dispatcher.registry()` reports it.
---@class Lib.Autocmd.Dispatcher.Entry
---@field name string
---@field events string[]
---@field group string|nil
---@field attached boolean
---@field handlers Lib.Autocmd.Dispatcher.HandlerInfo[]

--- Either a plain function (called directly on match) or a `{ load = … }`
--- table for the lazy-require case.
---@alias Lib.Autocmd.Dispatcher.Handler Lib.Autocmd.Dispatcher.HandlerSpec|Lib.Autocmd.Dispatcher.HandlerFn

---@class Lib.Autocmd.Dispatcher.Opts
---@field event string|string[] Autocmd event(s) to dispatch on
---@field name? string Name used in generated docs and `registry()`; defaults to `group`
---@field desc? string `desc` of the dispatcher's own autocmd; a default is derived from `name`
---@field group? string Augroup name, created/looked up via `lib.nvim.bindings.autocmd`
---@field pattern? string|string[] Autocmd pattern; default `"*"` — matching happens in Lua via `key`
---@field key fun(ev: Lib.Autocmd.Args): string|nil Derives the dispatch key from the event (e.g. `function(ev) return ev.match end`); a `nil` return skips dispatch entirely
---@field context? fun(ev: Lib.Autocmd.Args): any Optional shared context built once per event, passed to every matched handler as `ctx.context`

---@class Lib.Autocmd.Dispatcher.Stats
---@field total_keys integer Distinct key patterns registered
---@field total_handlers integer Total `register()` calls made
---@field keys string[] Every registered key pattern
---@field attached boolean Whether `attach()` has been called (and not yet `detach()`d)

--- Handle returned by `dispatcher.new()`. Every field is a plain function
--- (not a method) — call as `handle.register(...)`, not `handle:register(...)`.
---@class Lib.Autocmd.Dispatcher.Handle
---@field register fun(key_or_keys: string|string[], handler: Lib.Autocmd.Dispatcher.Handler): Lib.Autocmd.Dispatcher.Handle
---@field unregister fun(owner: string): integer
---@field handlers fun(): Lib.Autocmd.Dispatcher.HandlerInfo[]
---@field attach fun(): Lib.Autocmd.Dispatcher.Handle
---@field detach fun(): Lib.Autocmd.Dispatcher.Handle
---@field stats fun(): Lib.Autocmd.Dispatcher.Stats

---@class Lib.Autocmd.Dispatcher
---@field new fun(opts: Lib.Autocmd.Dispatcher.Opts): Lib.Autocmd.Dispatcher.Handle
---@field registry fun(): Lib.Autocmd.Dispatcher.Entry[]
---@field filetype Lib.Autocmd.Dispatcher.FileType

---@class Lib.Autocmd.Dispatcher.FileType
---@field new fun(opts?: { group?: string, context?: fun(ev: Lib.Autocmd.Args): any }): Lib.Autocmd.Dispatcher.Handle

return {}
