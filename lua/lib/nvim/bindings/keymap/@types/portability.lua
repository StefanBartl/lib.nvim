---@meta
---@module 'lib.nvim.bindings.keymap.@types.portability'

---How reliably a key reaches Neovim.
---
--- - `portable` -- a plain byte or a terminfo/xterm sequence. Arrives
---   everywhere; nothing to think about.
--- - `common` -- arrives in nearly every terminal, but through a mechanism
---   with a known off switch (Alt as an ESC prefix, Ctrl+Space as NUL). Fine
---   as the everyday key, not fine as the *only* key.
--- - `fragile` -- needs an extended encoding ("CSI u"/modifyOtherKeys) or a
---   GUI. On a terminal without it, the key silently never arrives.
---@alias Lib.Keymap.Portability.Tier "portable"|"common"|"fragile"

---`require("lib.nvim.bindings.keymap.portability")` itself: static
---reachability classification for an `lhs` notation string.
---@class Lib.Keymap.Portability
---@field classify fun(lhs: string|nil): (tier: Lib.Keymap.Portability.Tier, reason: string)
---@field is_portable fun(lhs: string|nil): boolean

return {}
