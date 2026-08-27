---@meta
---@module 'lib.nvim.bindings.autocmd.@types'

---@class Lib.AutoCmd.AuGroup.Create
---@field clear fun(name: string): integer # Create/clear a namespaced augroup

---@class Lib.AutoCmd.AuGroup
---@field create Lib.AutoCmd.AuGroup.Create

---@class Lib.Autocmd.Args
---@field id integer Autocommand ID
---@field event string Event name
---@field group integer|nil Augroup ID
---@field match string Matched pattern
---@field buf integer Buffer number
---@field file string Filename
---@field data any Event-specific data

---@class LibAutocmdOpts
---@field group? string|integer
---@field pattern? string|string[]
---@field buffer? integer  # Buffer-local autocmd; mutually exclusive with pattern.
---@field desc? string
---@field once? boolean
---@field nested? boolean

---@class Lib.AutoCmd
---@field norm_events fun(ev: any, fallback: string[]): string[] # Normalize event configuration to a non-empty list.
---@field norm_pattern fun(pat: any): string|string[] # Normalize an autocmd pattern field.
---@field group fun(name: string, clear: boolean|nil): integer # Create autocommand group
---@field create fun(event: string|string[], callback: fun(args:Lib.Autocmd.Args), opts: LibAutocmdOpts|nil): integer # Create autocommand, returns its id
---@field get_augroup fun(name: string, opts: { clear?: boolean, prefix?: string }|nil): integer # Augroup registry: Centralized augroup creation with optional prefixing and deduplication.
---@field augroup Lib.AutoCmd.AuGroup
---@field dispatcher Lib.Autocmd.Dispatcher

return {}

--- One autocmd as it was actually created, recorded by
--- `lib.nvim.bindings.autocmd.create`. Read it back with `registered()` or
--- `by_event()`.
---@class Lib.Autocmd.Record
---@field id integer          # nvim_create_autocmd's id
---@field events string[]     # always a list, even for a single event
---@field group string|nil    # augroup name, when one was given by name
---@field pattern string|string[]|nil
---@field buffer integer|nil  # set instead of `pattern` for a buffer-local autocmd
---@field desc string|nil
---@field once boolean
---@field src string          # "file:line" of the call site, so the answer says where to look
