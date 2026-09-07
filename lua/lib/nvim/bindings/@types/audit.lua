---@meta
---@module 'lib.nvim.bindings.@types.audit'

---@class Lib.Bindings.Audit.KeyAction
---@field surface string
---@field name string
---@field lhs string|nil
---@field bound boolean
---@field desc string|nil

---@class Lib.Bindings.Audit.CmdRoute
---@field name string
---@field path string
---@field desc string

---@class Lib.Bindings.Audit.KeyTier
---@field lhs string
---@field tier Lib.Keymap.Portability.Tier
---@field reason string

---@class Lib.Bindings.Audit.KeyRisk
---@field surface string
---@field name string
---@field keys Lib.Bindings.Audit.KeyTier[]  # every lhs the action binds, classified
---@field best Lib.Keymap.Portability.Tier   # the most reliable one it has
---@field desc string|nil

---@class Lib.Bindings.Audit.PrefixAmbiguity
---@field short string
---@field longer string[]

---`require("lib.nvim.bindings.audit")` itself: keymap actions vs. command
---routes, plus a handful of lints over whatever is registered in the
---current session.
---@class Lib.Bindings.Audit
---@field keymap_actions fun(root?: string): Lib.Bindings.Audit.KeyAction[]
---@field command_routes fun(root?: string): Lib.Bindings.Audit.CmdRoute[]
---@field naming_candidates fun(root?: string): (Lib.Bindings.Audit.CmdRoute|{vague: boolean})[]
---@field naming_candidate_lines fun(root?: string): string[]
---@field key_risks fun(root?: string): Lib.Bindings.Audit.KeyRisk[]  # fragile first, then common
---@field key_risk_lines fun(root?: string): string[]
---@field gaps fun(root?: string): Lib.Bindings.Audit.KeyAction[]
---@field gap_lines fun(root?: string): string[]
---@field lines fun(root?: string): string[]
---@field prefix_ambiguities fun(): Lib.Bindings.Audit.PrefixAmbiguity[]  # sorted by short
---@field prefix_ambiguity_lines fun(): string[]
---@field checklist_lines fun(root?: string): string[]
---@field create_usercmd fun(name?: string): nil

return {}
