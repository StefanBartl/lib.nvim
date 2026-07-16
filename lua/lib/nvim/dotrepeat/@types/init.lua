---@meta
---@module 'lib.nvim.dotrepeat.@types'

---Callback matching Vim's `operatorfunc` contract: called with the
---motion-type string (`"char"|"line"|"block"`) once dot-repeat re-invokes
---it, or with `nil` on the initial manual invocation via `M.run`.
---@alias Lib.Dotrepeat.Fn fun(motion_type?: string)

---@class Lib.Dotrepeat
---@field run fun(fn: Lib.Dotrepeat.Fn) Run `fn` now and make it repeatable via `.`
---@field repeatable fun(fn: Lib.Dotrepeat.Fn): Lib.Dotrepeat.Fn Wrap `fn` into a reusable, repeat-aware function suitable for `vim.keymap.set`
---@field _invoke fun(motion_type?: string) Internal `operatorfunc` dispatcher; reached via `v:lua`, do not call directly
