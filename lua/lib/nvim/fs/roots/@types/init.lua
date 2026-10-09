---@meta
---@module 'lib.nvim.fs.roots.@types'

---@class Lib.Fs.Roots.Config
---@field enable? boolean  `false` turns `fold` and `remap` off (`expand` keeps working). Default `true`.
---@field vars? string[]  Environment variable names that are roots. Default `{ "REPOS_DIR" }`; replaces, never merges.
---@field nvim_config? boolean  Register `NVIM_CONFIG_DIR` (= `stdpath("config")`) as a root. Default `true`.
---@field extra? table<string, string|(fun(): string?)>  User-defined roots: a path, or a function returning one. Sorted by name; wins over `vars`.
---@field source? (table<string, string|(fun(): string?)>)|(fun(name: string): string?)  Injected origin of the `vars` values AND of `NVIM_CONFIG_DIR`, replacing `vim.env` and `stdpath("config")` -- for tests. No fallback to the real ones.
---@field windows? boolean  Force the Windows (`true`) or POSIX (`false`) spelling and comparison rules; `nil` follows the platform.

---@class Lib.Fs.Roots.Root
---@field name string  Root name as configured, e.g. `"REPOS_DIR"`.
---@field root string  Absolute, forward slashes, no trailing slash.

---@class Lib.Fs.Roots.Status
---@field name string
---@field kind "extra"|"var"|"nvim_config"
---@field raw? string  The value before normalization.
---@field root? string  The normalized root; nil when `problem` is `"unset"` or `"not_absolute"`.
---@field exists? boolean  Whether `root` is an existing directory (set by `status()` / `json()` only).
---@field problem? "unset"|"not_absolute"|"missing_dir"

---@class Lib.Fs.Roots
---@field setup fun(cfg?: Lib.Fs.Roots.Config)
---@field enabled fun(): boolean
---@field roots fun(): Lib.Fs.Roots.Root[]
---@field names fun(): string[]
---@field status fun(): Lib.Fs.Roots.Status[]
---@field match fun(s: string): string|nil, string|nil, string|nil
---@field expand fun(s: string): string
---@field folder fun(opts?: Lib.Fs.Roots.FoldOpts): fun(p: string): string, string|nil
---@field fold fun(p: string, opts?: Lib.Fs.Roots.FoldOpts): string, string|nil
---@field remap fun(p: string): string[]
---@field json fun(): string
---@field print_json fun()
---@field export_env fun(): boolean
