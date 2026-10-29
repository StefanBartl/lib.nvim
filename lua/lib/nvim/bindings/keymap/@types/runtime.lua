---@meta
---@module 'lib.nvim.bindings.keymap.@types.runtime'

---Where an effective mapping comes from.
---
--- - `builtin` -- Neovim's own defaults (script id 1, or a file under `$VIMRUNTIME`).
--- - `lib` -- bound through lib.nvim's registry.
--- - `other` -- anything else: the user's config, a plugin.
---@alias Lib.Keymap.Origin "builtin"|"lib"|"other"

---One mapping in effect.
---@class Lib.Keymap.RuntimeEntry
---@field mode string                 # n, x, s, o, i, c, t or l.
---@field lhs string                  # As Neovim reports it.
---@field key string                  # Canonical spelling, comparable across notations.
---@field rhs? string                 # A string target; nil for a Lua callback or an empty one.
---@field callback boolean            # The target is a Lua function.
---@field desc? string
---@field sid? integer                # Script id that set it (1 = Neovim's defaults).
---@field lnum? integer               # Line in that script.
---@field source? string              # File of `sid`, when Neovim knows one.
---@field origin Lib.Keymap.Origin
---@field buffer? integer             # Buffer-local scope; nil = global.
---@field expr boolean

---A default Neovim binds that this session changed.
---@class Lib.Keymap.OverriddenDefault
---@field default Lib.Keymap.RuntimeEntry
---@field live Lib.Keymap.RuntimeEntry

---Result of `runtime.diff_defaults`.
---@class Lib.Keymap.DefaultsDiff
---@field overridden Lib.Keymap.OverriddenDefault[]  # Bound now, but not by the default any more.
---@field removed Lib.Keymap.RuntimeEntry[]          # The pristine default; not bound at all now.
---@field unchanged integer

---One action that seems to sit on several keys. A candidate, never a verdict.
---@class Lib.Keymap.DuplicateCandidate
---@field kind "desc"|"rhs"           # Grouped by normalized description or by identical string target.
---@field mode string
---@field buffer? integer
---@field value string                # The shared description or target.
---@field entries Lib.Keymap.RuntimeEntry[]

---`require("lib.nvim.bindings.keymap.runtime")` itself.
---@class Lib.Keymap.Runtime
---@field snapshot fun(opts?: { buffers?: boolean }): Lib.Keymap.RuntimeEntry[]
---@field pristine_defaults fun(opts?: { refresh?: boolean, timeout?: integer }): Lib.Keymap.RuntimeEntry[]|nil, string|nil
---@field diff_defaults fun(pristine: Lib.Keymap.RuntimeEntry[], live: Lib.Keymap.RuntimeEntry[]): Lib.Keymap.DefaultsDiff
---@field action_duplicates fun(live: Lib.Keymap.RuntimeEntry[], opts?: { builtin?: boolean }): Lib.Keymap.DuplicateCandidate[]
---@field defaults_lines fun(diff: Lib.Keymap.DefaultsDiff, info?: { version?: string, total?: integer }): string[]
---@field duplicate_lines fun(candidates: Lib.Keymap.DuplicateCandidate[]): string[]
---@field version_tag fun(): string

return {}
