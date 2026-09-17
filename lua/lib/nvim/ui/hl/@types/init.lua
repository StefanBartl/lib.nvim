---@meta
---@module 'lib.nvim.ui.hl.@types'

---@class Lib.Highlight.Opts
---@field fg string|integer|nil Foreground color (name or RGB integer)
---@field bg string|integer|nil Background color (name or RGB integer)
---@field sp string|integer|nil Special color (name or RGB integer)
---@field bold boolean|nil Enable bold text
---@field underline boolean|nil Enable underline
---@field undercurl boolean|nil Enable undercurl
---@field italic boolean|nil Enable italic
---@field reverse boolean|nil Enable reverse
---@field nocombine boolean|nil Prevent combining with other highlights
---@field link string|nil Link this highlight group to another

--- Options for `lib.nvim.ui.hl.persist`.
---@class Lib.UI.HL.PersistOpts
---@field name string # Augroup name, and the prefix of every autocmd description. Required: it is also the identity used to replace a previous registration.
---@field background? boolean # Also re-apply on `OptionSet background` (default `true`). Switching background selects the other half of a light/dark palette and does not always fire `ColorScheme`.
---@field ns? string|integer # Highlight namespace, passed through to `set`. Default: the global namespace.
---@field immediate? boolean # Apply once right away (default `true`). `false` registers the autocommands only.

--- What `persist` hands back.
---@class Lib.UI.HL.PersistHandle
---@field apply fun(): nil # Re-apply on demand; the same guarded callback the autocommands run.
---@field detach fun(): nil # Remove the augroup and with it both autocommands.

---@class Lib.UI.HL
---@field namespace fun(name: string): integer
---@field set fun(group: string, opts: Lib.Highlight.Opts, ns: string|integer|nil)
---@field persist fun(spec: table<string, Lib.Highlight.Opts>|fun(): table<string, Lib.Highlight.Opts>|nil, opts: Lib.UI.HL.PersistOpts): Lib.UI.HL.PersistHandle

return {}
