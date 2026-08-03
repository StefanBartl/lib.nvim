---@meta
---@module 'lib.nvim.telemetry.@types'

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

--- Reminder trigger. `false` opts out entirely; otherwise the first of the two
--- thresholds to be reached fires the (single) reminder.
---@class Lib.Telemetry.RemindAfter
---@field days? integer   # calendar days since collection started (default 7)
---@field calls? integer  # total recorded calls (default 50000)

---@class Lib.Telemetry.Options
---@field namespace string                              # required; also the on-disk cache key
---@field dir? string                                   # override the cache directory (passed to lib.nvim.cache.disk)
---@field retention_days? integer                       # drop day buckets older than this (default 30)
---@field flush_interval_ms? integer                    # debounced periodic flush (default 60000; 0 disables)
---@field remind_after? Lib.Telemetry.RemindAfter|false # lifecycle reminder (default { days = 7, calls = 50000 })
---@field persist? boolean                              # false keeps everything in memory (default true)
---@field max_arg_values? integer                       # distinct fingerprints kept per function (default 32)
---@field report_file? boolean                          # keep this namespace's Markdown report on disk, rewritten at every flush (default false); see lua/lib/nvim/telemetry/report_file.lua
---@field info? table<string, string>                   # free-form metadata bundled with the report (branch, version/release tag, commit, …) — see lib.nvim.git.info() for a ready-made source; the caller supplies it, this module never inspects a repo to guess it

--- "auto" (default) prefers mdview if loadable, else the kit float — same
--- degrade-silently discipline as `lib.nvim.progress`'s style resolution.
---@alias Lib.Telemetry.ReportStyle "auto"|"kit"|"mdview"|"file"

--- Scoping options for `wrap()`. `only` and `except` are exact names, never
--- patterns — `filter` is the single escape hatch for anything else.
---@class Lib.Telemetry.WrapOpts
---@field only? string[]                       # wrap only these field names
---@field except? string[]                     # wrap everything but these
---@field filter? fun(name: string, fn: function): boolean
---@field profile_args? boolean                # fingerprint arguments for these functions
---@field time? boolean                        # measure duration for these functions
---@field errors? boolean                      # count raised errors for these functions
---@field outermost_only? boolean              # recursive calls count once (costs a pcall)
---@field module_id? string                    # the real Lua module path `container` came from, if known (set automatically by wrap_loaded()). Enables a consumer to resolve a wrapped key back to source; omit when the wrap prefix is not a real module path.

--- Scoping for `wrap_loaded()`: the per-function `only`/`except`/`filter`
--- vocabulary, plus the same three one level up for whole modules.
---@class Lib.Telemetry.WrapLoadedOpts : Lib.Telemetry.WrapOpts
---@field module_only? string[]                      # wrap only these exact module names
---@field module_except? string[]                    # wrap everything but these modules
---@field module_filter? fun(name: string): boolean  # predicate over the full module path

--- Each field takes a key list, `true` for everything, or a predicate over the
--- key — the predicate form matters once `wrap_loaded()` produces structured
--- keys, where "everything under `core.`" is a one-liner but a list is not.
---@class Lib.Telemetry.StartOpts
---@field profile_args? string[]|true|fun(key: string): boolean  # argument fingerprinting
---@field time? string[]|true|fun(key: string): boolean          # duration measurement
---@field errors? string[]|true|fun(key: string): boolean        # count raised errors

---@class Lib.Telemetry.ReportOpts
---@field sort? "calls"|"name"|"time"  # default "calls"
---@field top? integer                 # keep only the N busiest entries
---@field since? string|integer        # "7d" / "24h" / a day count; filters the day buckets

-- ---------------------------------------------------------------------------
-- Collected data
-- ---------------------------------------------------------------------------

---@class Lib.Telemetry.Timing
---@field n integer
---@field total_ms number
---@field min_ms number
---@field max_ms number

---@class Lib.Telemetry.ArgStats
---@field values table<string, integer>  # fingerprint -> count
---@field other integer                  # calls whose fingerprint did not fit in `values`
---@field distinct integer               # distinct fingerprints seen, including evicted ones
---@field n? integer                     # size of `values`, tracked so the hot path never counts keys

---@class Lib.Telemetry.FnStats
---@field calls integer
---@field errors? integer
---@field timing? Lib.Telemetry.Timing
---@field args? Lib.Telemetry.ArgStats

---@class Lib.Telemetry.Data
---@field version integer
---@field started_at integer                                  # os.time() of the first collection
---@field sessions integer
---@field functions table<string, Lib.Telemetry.FnStats>
---@field days table<string, table<string, integer>>          # "YYYY-MM-DD" -> key -> calls
---@field reminded table<string, boolean>                     # threshold name -> already notified
---@field modules table<string, string>                       # wrapped key -> real Lua module path, only for keys lib.nvim can resolve (see WrapOpts.module_id / wrap_loaded); a key with no entry is unmatched, not zero-calls
---@field info table<string, string>                          # free-form metadata from Options.info — last-write-wins on merge, not accumulated, since a newer session's branch/version supersedes an older one rather than adding to it

---@class Lib.Telemetry.ReportEntry
---@field key string
---@field calls integer
---@field errors integer
---@field mean_ms? number
---@field min_ms? number
---@field max_ms? number
---@field args? { fingerprint: string, count: number, share: number }[]
---@field other? integer
---@field distinct? integer
---@field hint? string   # e.g. the "dominant argument -> memoize" suggestion

---@class Lib.Telemetry.Report
---@field namespace string
---@field running boolean
---@field disabled boolean
---@field modes { counting: boolean, args: boolean, timing: boolean, errors: boolean }
---@field started_at integer
---@field sessions integer
---@field total_calls integer
---@field wrapped integer
---@field since? string
---@field info table<string, string>
---@field entries Lib.Telemetry.ReportEntry[]

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

---@class Lib.Telemetry.Instance
---@field namespace string
---@field wrap fun(container: table, prefix?: string, opts?: Lib.Telemetry.WrapOpts): integer
---@field wrap_fn fun(fn: function, key: string, opts?: Lib.Telemetry.WrapOpts): function
---@field wrap_lib fun(opts?: Lib.Telemetry.WrapOpts): integer
---@field wrap_loaded fun(prefix: string, opts?: Lib.Telemetry.WrapLoadedOpts): integer, integer
---@field unwrap fun(): nil
---@field start fun(opts?: Lib.Telemetry.StartOpts): boolean
---@field stop fun(): boolean
---@field is_running fun(): boolean
---@field report fun(opts?: Lib.Telemetry.ReportOpts): Lib.Telemetry.Report
---@field lines fun(opts?: Lib.Telemetry.ReportOpts): string[]
---@field markdown fun(opts?: Lib.Telemetry.ReportOpts): string[]
---@field coverage fun(): { called: string[], uncalled: string[] }
---@field resolved_modules fun(): table<string, string>
---@field reset fun(): nil
---@field flush fun(): boolean
---@field wrapped_keys fun(): string[]

---@class Lib.Telemetry
---@field new fun(opts: Lib.Telemetry.Options): Lib.Telemetry.Instance
---@field instances fun(): Lib.Telemetry.Instance[]
---@field get fun(namespace: string): Lib.Telemetry.Instance|nil
---@field load fun(namespace: string, opts?: Lib.Cache.Opts): Lib.Telemetry.Data|nil
---@field report_all fun(opts?: Lib.Telemetry.ReportOpts): Lib.Telemetry.Report[]
---@field markdown_all fun(opts?: Lib.Telemetry.ReportOpts): string[]
---@field setup fun(opts?: { report_style?: Lib.Telemetry.ReportStyle }): nil
---@field flush_all fun(): integer
---@field stop_all fun(): integer
---@field disable fun(namespace: string): nil
---@field enable fun(namespace: string): nil
---@field is_disabled fun(namespace: string): boolean
---@field disabled fun(): string[]

return {}
