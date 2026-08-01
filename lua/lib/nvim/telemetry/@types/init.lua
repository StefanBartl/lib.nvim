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

---@class Lib.Telemetry.StartOpts
---@field profile_args? string[]|true  # enable argument fingerprinting for these keys (or all)
---@field time? string[]|true          # enable timing for these keys (or all)
---@field errors? string[]|true        # enable error counting for these keys (or all)

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
---@field entries Lib.Telemetry.ReportEntry[]

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

---@class Lib.Telemetry.Instance
---@field namespace string
---@field wrap fun(container: table, prefix?: string, opts?: Lib.Telemetry.WrapOpts): integer
---@field wrap_fn fun(fn: function, key: string, opts?: Lib.Telemetry.WrapOpts): function
---@field wrap_lib fun(opts?: Lib.Telemetry.WrapOpts): integer
---@field unwrap fun(): nil
---@field start fun(opts?: Lib.Telemetry.StartOpts): boolean
---@field stop fun(): boolean
---@field is_running fun(): boolean
---@field report fun(opts?: Lib.Telemetry.ReportOpts): Lib.Telemetry.Report
---@field lines fun(opts?: Lib.Telemetry.ReportOpts): string[]
---@field coverage fun(): { called: string[], uncalled: string[] }
---@field reset fun(): nil
---@field flush fun(): boolean
---@field wrapped_keys fun(): string[]

---@class Lib.Telemetry
---@field new fun(opts: Lib.Telemetry.Options): Lib.Telemetry.Instance
---@field instances fun(): Lib.Telemetry.Instance[]
---@field get fun(namespace: string): Lib.Telemetry.Instance|nil
---@field report_all fun(opts?: Lib.Telemetry.ReportOpts): Lib.Telemetry.Report[]
---@field flush_all fun(): integer
---@field stop_all fun(): integer
---@field disable fun(namespace: string): nil
---@field enable fun(namespace: string): nil
---@field is_disabled fun(namespace: string): boolean
---@field disabled fun(): string[]

return {}
