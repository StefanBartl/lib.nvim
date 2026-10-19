---@meta
---@module 'lib.lua.config.@types'

---@alias Lib.Config.MergeRule "replace"|"entries"

---@class Lib.Config.Spec
---@field name? string  Prefix of messages; default "config".
---@field schema? table<string, Lib.Config.Schema.Spec>  Exceptions to the schema inferred from DEFAULTS, by dotted path.
---@field optional? table<string, Lib.Config.Schema.Spec>  Keys that are allowed but have no default (an opt-in feature whose absence means off).
---@field merge? table<string, Lib.Config.MergeRule>  Merge rule per dotted path: "replace" or "entries".
---@field layers? string[]  Rank of the layers, lowest first, DEFAULTS below all; must contain "setup". Default { "setup" }.
---@field normalize? fun(opts: table, issues: string[], layer: string): table?  Before the check, on a private copy: liberal in, canonical out. May return a new table.
---@field resolve? fun(cfg: table, issues: string[]): table?  After the merge: derived values, joint constraints. May return a new table.
---@field on_change? fun(cfg: table, prev: table?)  After every recompute: invalidate caches, rebuild lookups.
---@field stable? boolean  Write into the same table every time (consumers hold references into it).
---@field notify? fun(message: string)  Called with the problems of a layer when it is set.

---@class Lib.Config.Instance
---@field name string
---@field setup fun(opts: table?)
---@field layer fun(name: string, opts: table?)
---@field get fun(path?: string): any
---@field snapshot fun(): table
---@field source fun(path: string): string?
---@field issues fun(): string[]
---@field reset fun()
---@field verify fun(): string?

---@class Lib.Config
---@field copy fun(t: any, seen?: table<table, table>): any
---@field merge_into fun(out: table, override: table, rules?: table<string, Lib.Config.MergeRule>, path?: string)
---@field deep_merge fun(base: table, override: table, rules?: table<string, Lib.Config.MergeRule>): table
---@field get fun(tbl: table, path: string?): any
---@field new fun(defaults: table, spec?: Lib.Config.Spec): Lib.Config.Instance
---@field set_checked fun(on: boolean)
---@field is_checked fun(): boolean

return {}
