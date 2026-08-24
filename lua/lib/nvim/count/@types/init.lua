---@meta
---@module 'lib.nvim.count.@types'

---@class Lib.Count.ChainOpts
---@field action fun() # Fires one unit of work.
---@field subscribe fun(advance: fun(), abort: fun()): fun()|nil # Register completion/abort listeners; return an unsubscribe.
---@field count? integer # Defaults to `vim.v.count1`.
---@field max? integer # Cap on chained repeats; defaults to `Lib.Count.DEFAULT_MAX`.

---@class Lib.Count
---@field DEFAULT_MAX integer # Default upper bound for `times`/`chain` (1000).
---@field get fun(): integer # `vim.v.count1` -- "no count means once".
---@field raw fun(): integer # `vim.v.count` -- 0 when none was typed.
---@field given fun(): boolean # Whether a count was typed at all.
---@field clamp fun(min: integer, max: integer): integer # `vim.v.count1` clamped into a range.
---@field times fun(fn: fun(i: integer): boolean|nil, opts: { count?: integer, max?: integer }|nil): integer # Run `fn` once per count, synchronously; `false` stops early.
---@field chain fun(opts: Lib.Count.ChainOpts): boolean # Repeat an async action, each call gated on a completion signal.

return {}
