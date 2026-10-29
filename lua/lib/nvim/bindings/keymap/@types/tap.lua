---@meta
---@module 'lib.nvim.bindings.keymap.@types.tap'

---Where a binding call came from.
---
--- - `lib` -- through lib.nvim's `bindings.keymap` (`set`, `register`).
--- - `lazy` -- lazy.nvim's `keys` handler (`lazy/core/handler/keys.lua`).
--- - `raw` -- any other caller of `vim.keymap.set` / `vim.api.nvim_set_keymap`.
---@alias Lib.Keymap.Via "lib"|"lazy"|"raw"

---One recorded `set` or `del` of one mode.
---
---A call with a list of modes (or a mode that stands for several, like `""`)
---yields one event per real mode.
---@class Lib.Keymap.TapEvent
---@field op "set"|"del"
---@field mode string                 # A real mode: n, x, s, o, i, c, l or t.
---@field lhs string                  # As written.
---@field key string                  # Canonical spelling (`<M-h>` and `<A-h>` are one key).
---@field buffer? integer             # Buffer-local scope; nil = global.
---@field desc? string
---@field rhs? string                 # Only for a string target.
---@field rhs_kind "string"|"function"|"none"
---@field source string               # "file:line" of the first frame outside Neovim's and lib.nvim's keymap code.
---@field via Lib.Keymap.Via
---@field fp string                   # Identity of what was bound (site + desc + target); equal = the same binding made again.

---`require("lib.nvim.bindings.keymap.tap")` itself.
---@class Lib.Keymap.Tap
---@field install fun(): boolean
---@field uninstall fun(): boolean, string[]
---@field is_installed fun(): boolean
---@field log fun(): Lib.Keymap.TapEvent[]
---@field clear fun(): integer
---@field collisions fun(events?: Lib.Keymap.TapEvent[]): Lib.Keymap.Conflict[]

return {}
