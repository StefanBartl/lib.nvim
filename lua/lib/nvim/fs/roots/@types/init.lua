---@meta
---@module 'lib.nvim.fs.roots.@types'

---@class Lib.Fs.Roots.Config
---@field enable? boolean  `false` turns `fold` and `remap` off (`expand` keeps working). Default `true`.
---@field vars? string[]  Environment variable names that are roots. Default `{ "REPOS_DIR" }`; replaces, never merges.
---@field nvim_config? boolean  Register `NVIM_CONFIG_DIR` (= `stdpath("config")`) as a root. Default `true`.
---@field extra? table<string, string|(fun(): string?)>  User-defined roots: a path, or a function returning one. Sorted by name; wins over `register`ed roots and `vars`.
---@field source? (table<string, string|(fun(): string?)>)|(fun(name: string): string?)  Injected origin of the `vars` values AND of `NVIM_CONFIG_DIR`, replacing `vim.env` and `stdpath("config")` -- for tests. No fallback to the real ones. `~` still reads the real home directory.
---@field windows? boolean  Force the Windows (`true`) or POSIX (`false`) spelling and comparison rules; `nil` follows the platform.

---Per-call options of `roots`. An unknown key raises.
---@class Lib.Fs.Roots.Opts
---@field names? string[]  Extra environment variable names to treat as roots for this call, after the configured `vars`.
---@field nvim_config? boolean  Override `Config.nvim_config` for this call.

---Per-call options of `fold`, `folder` and `root_of`. An unknown key raises.
---@class Lib.Fs.Roots.FoldOpts : Lib.Fs.Roots.Opts
---@field force? boolean  Fold even when `enable` is false -- for an action the user asked for by name.

---@class Lib.Fs.Roots.Root
---@field name string  Root name as configured, e.g. `"REPOS_DIR"`.
---@field root string  Absolute, forward slashes, no trailing slash, uppercase drive letter.

---@alias Lib.Fs.Roots.Problem
---| "unset"           # no value (variable not set, empty, function returned nothing)
---| "unresolved_var"  # the value starts with `$VAR` / `~` that has no value (`detail` names it)
---| "error"           # the function raised (`detail` is the message)
---| "bad_type"        # the value is neither a string nor a function (`detail` is its type)
---| "not_absolute"    # relative after expansion
---| "too_broad"       # the filesystem root or a whole drive: it would fold every path
---| "invalid_path"    # contains a NUL byte
---| "invalid_name"    # the name is not letters, digits and underscores (`expand` could not read it back)
---| "missing_dir"     # `root` is not an existing directory (set by `status()` / `json()` only)

---@class Lib.Fs.Roots.Status
---@field name string
---@field kind "extra"|"registered"|"var"|"nvim_config"
---@field raw? string  The value before normalization.
---@field root? string  The normalized root; nil when there is a `problem` other than `"missing_dir"`.
---@field exists? boolean  Whether `root` is an existing directory (set by `status()` / `json()` only).
---@field problem? Lib.Fs.Roots.Problem
---@field detail? string  What `problem` is about (variable name, error message, type).
---@field env? string  `nvim_config` only: the root `$NVIM_CONFIG_DIR` has in the environment when that differs from `root` (`status()` only).

---@class Lib.Fs.Roots
---@field setup fun(cfg?: Lib.Fs.Roots.Config)
---@field register fun(name: string, value: string|(fun(): string?)): fun()
---@field unregister fun(name: string): boolean
---@field enabled fun(): boolean
---@field roots fun(opts?: Lib.Fs.Roots.Opts): Lib.Fs.Roots.Root[]
---@field names fun(): string[]
---@field status fun(): Lib.Fs.Roots.Status[]
---@field match fun(s: string): string|nil, string|nil, string|nil
---@field relative fun(p: string, name: string): string|nil
---@field expand fun(s: string): string
---@field folder fun(opts?: Lib.Fs.Roots.FoldOpts): fun(p: string): string, string|nil
---@field fold fun(p: string, opts?: Lib.Fs.Roots.FoldOpts): string, string|nil
---@field root_of fun(p: string, opts?: Lib.Fs.Roots.FoldOpts): string|nil
---@field remap fun(p: string): string[]
---@field json fun(): string
---@field print_json fun()
---@field export_env fun(): boolean
