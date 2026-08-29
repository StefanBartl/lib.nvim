---@meta
---@module 'lib.nvim.bindings.keymap.modifier.@types'

---@class Lib.Keymap.Modifier.Opts
---@field experimental? boolean # Opt-in. `nil`/`false` off (and undoes an earlier setup), `true` binds both modifiers.
---@field copy? string # lhs for "run the next mapping, copy its result". Default `\`.
---@field insert? string # lhs for "run it, copy *and* insert at the cursor". Default `\\`.

---Which tier produced a result: `declared` (a `M.declare` producer),
---`returned` (the mapping's own return value), `observed <reg>` (a register
---moved while it ran), or `none`.
---@alias Lib.Keymap.Modifier.Tier string

---@class Lib.Keymap.Modifier
---@field setup fun(opts?: Lib.Keymap.Modifier.Opts): boolean # Bind the modifiers. Off unless `opts.experimental`.
---@field teardown fun() # Unbind whatever is bound.
---@field keys fun(): { copy: string|nil, insert: string|nil } # The bound lhs values, or `nil` each when off.
---@field declare fun(mode: string, lhs: string, fn: fun(): string|nil) # Declare a mapping's result (tier 1). `fn` must be pure.
---@field undeclare fun(mode: string, lhs: string) # Drop a declaration.

return {}
