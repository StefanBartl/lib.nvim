---@meta
---@module 'lib.nvim.bindings.keymap.@types'

---@class Lib.Map.ErrorFlags
---@field modes boolean
---@field lhs boolean
---@field rhs boolean
---@field buffer boolean

---@class Lib.Map.Opts
---@field noremap? boolean
---@field silent? boolean
---@field buffer? integer|boolean
---@field desc? string
---@field expr? boolean
---@field nowait? boolean
---@field remap? boolean

---@class Lib.Map
---@field _call fun(modes: string|string[], lhs: string, rhs: string|function, opts: Lib.Map.Opts|nil, desc: string?): nil

--- Extras which-key cannot infer from a mapping on its own.
---
--- `desc` is absent on purpose: which-key reads it from the mapping itself, and
--- passing it a second time only creates a copy that can disagree.
---@class Lib.Keymap.WhichKey
---@field prefix? string         # Only in the list form: the prefix this group labels.
---@field group? string          # Label for a prefix, e.g. "Spotlight" for `<leader>s`.
---@field icon? string|table
---@field mode? string|string[]  # Defaults to the action's own mode.

--- One mode's binding of an action, when the modes differ in more than name.
---
--- Fields left unset fall back to the action's own.
---@class Lib.Keymap.Bind
---@field mode? string|string[]
---@field rhs? string|function
---@field desc? string
---@field opts? Lib.Map.Opts

--- One named, user-overridable action.
---
--- `binds` covers the common case of one key meaning the same *intent* in two
--- modes while calling different functions -- normal mode acting on the token
--- under the cursor, visual mode on the selection. That is one action to a
--- user (one name, one key, one override), so it stays one action here.
---@class Lib.Keymap.Action
---@field default? string|string[]        # Default `lhs`, or several. Absent = no key by default.
---@field rhs? string|function            # Absent = declared but not bindable (docs/health only).
---@field mode? string|string[]           # Default "n".
---@field desc? string                    # Prefixed with the plugin name when bound.
---@field opts? Lib.Map.Opts
---@field binds? Lib.Keymap.Bind[]        # Per-mode variants; each yields its own registered entry.
---@field which_key? Lib.Keymap.WhichKey|false  # `false` hides it from which-key.

--- What a plugin declares.
---@class Lib.Keymap.Spec
---@field actions table<string, Lib.Keymap.Action>
---@field order? string[]                       # Declaration order for docs/health; sorted when absent.
---@field prefix? string                        # The group prefix, e.g. "<leader>s".
---@field which_key? Lib.Keymap.WhichKey|Lib.Keymap.WhichKey[]|false # Group label(s); a list carries its own `prefix` per entry.

--- One resolved action, as recorded in the registry.
---@class Lib.Keymap.Registered
---@field plugin string
---@field name string
---@field lhs string|nil                  # nil = disabled or no default.
---@field mode string|string[]
---@field desc string|nil
---@field rhs string|function|nil
---@field which_key? Lib.Keymap.WhichKey|false
---@field bound boolean                   # False when disabled, preset off, or no rhs.

--- One `lhs` claimed by more than one registered plugin.
---@class Lib.Keymap.Conflict
---@field mode string
---@field lhs string
---@field claimants Lib.Keymap.Registered[]

---@class Lib.Keymap : Lib.Map
---@field set fun(modes: string|string[], lhs: string, rhs: string|function, opts: Lib.Map.Opts|nil, desc: string?): nil
---@field register fun(plugin: string, spec: Lib.Keymap.Spec, user: table|false|nil): Lib.Keymap.Registered[]
---@field registered fun(plugin: string|nil): table<string, Lib.Keymap.Registered[]>|Lib.Keymap.Registered[]
---@field conflicts fun(): Lib.Keymap.Conflict[]

return {}
