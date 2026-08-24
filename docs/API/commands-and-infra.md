# API Reference — commands, automation, infrastructure

Part of the [lib.nvim API reference](README.md). Covers `lib.nvim.usercmd`
(including the `composer` subsystem), `autocmd`, `map`, `dotrepeat`,
`debounce`, `deps`, `treesitter`, `store`, `logger`, `progress`, `harvest`,
`git`, `net.curl`, `lua_ls`, `cache`, `core`, `normalize`, `require`,
`safe_api`, `system`, `token`, and `neotree`.

---

## `lib.nvim.usercmd` and `lib.nvim.usercmd.composer`

### `lib.nvim.usercmd` (see README)
Standardized wrapper around `nvim_create_user_command`/
`nvim_buf_create_user_command` with sane defaults (`force=true`,
`desc=""`, `nargs=0`) and a `pcall`-wrapped, notify-on-error callback.

```
M.create(name: string, callback: string|fun(args:Lib.UserCommand.Args), opts: LibUserCommandOpts|nil)
  -- opts.buffer (true=current buf, or bufnr) routes to nvim_buf_create_user_command; stripped before the native call
M.composer   -- lazy proxy table onto lib.nvim.usercmd.composer (avoids a require cycle)
```

### `lib.nvim.usercmd.composer` (see README — extensive, read it for the full narrative)

**The most widely-used module in the whole library — 30+ consuming
plugins.** Compose a declarative route-tree spec into ONE Neovim user
command with subcommand dispatch, `<Tab>` completion, argument/flag/kv
coercion, and generated Markdown docs, all driven from the same tree.

Access: `require("lib.nvim.usercmd.composer")` (direct, most efficient),
`require("lib").composer`, `require("lib").usercmd.composer`.

#### `M.verb(name: string, spec?: Lib.UserCmd.Composer.Spec): Lib.UserCmd.Composer.Handle|table`
Core entry point. With a `spec`, registers immediately and returns a
`Handle`. Without one, returns a fluent builder (chain
`:desc()/:default()/:bang()/:range()/:count()/:buffer()/:route()/:build()`).

**`spec` shape:**
```
desc?: string                          -- command description
default?: fun(ctx)                     -- handler for bare :Verb (no route path)
routes?: RouteSpec[]                   -- the route tree; each route:
  path: string[]                       -- literal subcommand tokens ({} = verb's root route)
  args?: ArgSpec[]                     -- { name, type, optional?, enum?, values? }
                                        --   types: STRING (default), INT, FLOAT, BOOL, PATH, DIR, FILE, BUFFER, WINDOW, custom
  flags?: FlagSpec[]                   -- --flag/-x parsing: { name, short?, bool?, type?, enum?, repeatable? }
  kv?: KvSpec[]                        -- bare key=value parsing: { key, type?, enum?, default? }
  run: fun(ctx)|string                 -- handler, or a module path required lazily on first dispatch
  desc?, check?: fun(): boolean, string?, bang?, range?, count?, visual?: string[]
bang?: boolean                         -- verb-level default (explicit route.bang wins if set)
range?: boolean|integer                -- verb-level default (first route's range wins if unset)
count?: integer                        -- verb-level :N Verb default (first route's count wins if unset)
buffer?: true|integer                  -- buffer-local registration
visual?: string[]                      -- verb-level default for routes declaring none
notify_prefix?: string                 -- overrides the deferred-notifier's prefix (default "[" .. name .. "]")
```

**`ctx` (handler context):** `ctx.args` (coerced positionals by name),
`ctx.pos` (by order), `ctx.flags` (by name), `ctx.kv` (by key), `ctx.rest`
(leftover tokens), `ctx.path` (matched literal path), `ctx.bang`,
`ctx.range` (`{ line1, line2, count, range, mode, col1, col2 }`), `ctx.raw`
(raw nvim callback args).

**`Handle`** (returned by `verb()` with a spec, or the builder's `:build()`):
```
handle:name(): string
handle:spec(): Lib.UserCmd.Composer.Spec
handle:document(path?: string): boolean ok, string|nil err
handle:check(): Lib.UserCmd.Composer.CheckResult[]
```

**Other module functions:**
```
M.document(path?: string): boolean ok, string|nil err   -- docs for EVERY verb registered in this process
M.setup(opts?: Lib.UserCmd.Composer.SetupOpts)
  -- opts.docs = { path?, mode? }; mode "replace" (default, whole file) | "section" (delimited block in-place)
M.register_type(name: string, def: Lib.UserCmd.Composer.TypeDef)
  -- def = { validate = fun(raw): boolean, any, string|nil, complete = fun(lead): string[] }
M.registry(): table<string, Lib.UserCmd.Composer.Handle>
M.check_all(): table<string, Lib.UserCmd.Composer.CheckResult[]>
M.checkhealth(name_or_handle: string|Lib.UserCmd.Composer.Handle)
  -- call from your plugin's own health.lua; composer cannot self-register a :checkhealth target
M.notify_check_all(): boolean ok_overall   -- notification-based alternative to checkhealth
```

**Behavior notes:** flags are parsed anywhere in the tail; `--` sentinel
stops flag parsing; unknown `--name` is a hard error; short-flag `-x`
aliases via `short = "x"` (value flags only take the *next* token, never
`-x=value`); an unrecognized `-x` falls through as positional. Undeclared
`key=value` tokens are left positional (not an error, unlike flags).
Composer's internals (`parse.lua`, `tree.lua`, `flags.lua`, `kv.lua`,
`argtypes.lua`, `docgen.lua`, `complete.lua`, `check.lua`, `registry.lua`,
`format.lua`) are reached only through the public functions above.

---

## `lib.nvim.autocmd` (see README)

Standardized autocommand creation on top of `nvim_create_autocmd` —
automatic augroup lookup/caching, a defensive `pcall`-wrapped callback,
event/pattern normalization.

```
M.augroup   -- lazily-required proxy onto lib.nvim.autocmd.augroup
M.group(name: string, clear?: boolean): integer          -- memoized in an internal cache
M.get_augroup(name: string, opts?: { clear?, prefix? }): integer   -- separate cache from M.group
M.create(event: string|string[], callback: fun(args), opts?: LibAutocmdOpts): integer
  -- callback pcall-wrapped, notify-on-error tagged [lib.nvim.autocmd]; opts.buffer/opts.pattern mutually exclusive
M.norm_events(ev: any, fallback: string[]): string[]
M.norm_pattern(pat: any): string|string[]                -- nil -> "*"
```

### `lib.nvim.autocmd.augroup` (no separate README)
A third, unrelated, uncached one-off augroup helper — always
creates/clears unconditionally (no memoization).

```
M.create.clear(name: string): integer
```

---

## `lib.nvim.map` (see README)

Convenience wrapper around `vim.keymap.set` with sane defaults and
defensive argument validation. **The module itself is a function** —
`require("lib.nvim.map")` returns the callable directly.

```
return function(modes: string|string[], lhs: string, rhs: string|function, opts?: Lib.Map.Opts, desc?: string)
```
Defaults: `opts.noremap = true`, `opts.silent = true`, `opts.desc = ""`. A
string `desc` positional overrides `opts.desc`. `opts.buffer = true`
normalizes to `0`. On validation failure, `vim.keymap.set` is **not**
called — reports every failing field plus the real caller's call site
instead.

---

## `lib.nvim.count` (see README)

Count-prefix helpers for keymaps (`3<leader>xy`). Reading, plus the two ways
an action repeats.

```
M.DEFAULT_MAX: integer                                   -- 1000; cap for times/chain
M.get(): integer                                         -- vim.v.count1 ("no count means once")
M.raw(): integer                                         -- vim.v.count (0 when none typed)
M.given(): boolean                                       -- was a count typed at all
M.clamp(min: integer, max: integer): integer             -- vim.v.count1 clamped into a range
M.times(fn: fun(i: integer): boolean|nil, opts?: { count?: integer, max?: integer }): integer
  -- runs fn once per count, synchronously; fn returning false stops early; returns times actually run
M.chain(opts: Lib.Count.ChainOpts): boolean
  -- repeats an async action, each call gated on the caller's completion signal; returns whether it chained
```

`chain` generalizes dap.nvim's `counted_step()`: `opts.subscribe(advance,
abort)` registers the caller's listeners and returns an unsubscribe.
`advance` releases the next call, `abort` drops the chain. With no count,
`action` is called directly and `subscribe` is never invoked. A missing or
raising `subscribe` reports and runs the action **once** — it deliberately
does not fall back to a synchronous loop, which is the unpaced repetition
`chain` exists to prevent. The chain also refuses to advance after `abort`,
so a completion signal that was already queued cannot resurrect it.

---

## `lib.nvim.dotrepeat` (see README)

Native Vim `.`-repeat wiring through `operatorfunc`, no `vim-repeat`
dependency.

```
M.run(fn: Lib.Dotrepeat.Fn)
  -- runs fn now, stores it as pending, points operatorfunc at the stable dispatcher, fires once via `normal! g@l`
M.repeatable(fn: Lib.Dotrepeat.Fn): Lib.Dotrepeat.Fn   -- wrapped equivalent, usable directly as a keymap callback
M._invoke(motion_type: string|nil)   -- dispatcher reached from Vimscript via v:lua; technically public
```

---

## `lib.nvim.debounce.*`

### `lib.nvim.debounce` (see README)
Generic debounce primitive built on `(vim.uv or vim.loop).new_timer()`.

```
M.new(fn: fun(...:any), ms: integer): Lib.Debounce.Handle   -- { call, cancel }
M.new_with_counter(fn: fun(...:any), ms: integer): (Lib.Debounce.Handle handle, fun(): integer skipped)
  -- returns TWO values (handle, get_skipped), not one table; skipped = calls coalesced since the last fire
```

### `lib.nvim.debounce.buffer` (see README)
Buffer-scoped debounce — one independent timer per `bufnr`, auto-armed
cleanup autocmd.

```
new(fn: fun(bufnr:integer, ...:any), opts?: Lib.Debounce.BufferOpts): Lib.Debounce.BufferHandle
  -- { call, cancel, cancel_all }
```
`opts.ms` (default 200), `opts.adaptive` (default false — effective delay
= `min(ms*4, ms + floor(line_count/50))`), `opts.cleanup_events` (default
`{ "BufDelete", "BufWipeout" }`).

---

## `lib.nvim.deps.*`

Directory README is extensive — external-tool detection, declared-dependency
spec parsing (`docs/INSTALL.md`/`docs/install.json`), confirmation-gated
install handoff. **Requiring any deps module executes nothing** — only
`install.run()` (reached via an explicit user action) ever opens a
terminal, and even then the command is only typed, never submitted.

### `lib.nvim.deps` (see README) — top-level aggregator/facade
```
M.spec, M.health, M.pm, M.install, M.view, M.first_run   -- re-exports, see below
M.show_once(plugin_name: string, opts?: { manager?, cache? }): boolean shown
M.plugins(): string[]                       -- every plugin on rtp shipping a deps spec
M.show(plugin_name: string): boolean shown
M.install_for(plugin_name: string): boolean started
M.routes(): table[]                          -- :Lib deps show|install|reset-first-run composer routes
```

### `lib.nvim.deps.health`
Generic replacement for hand-rolled `check_exe`/`probe` loops.
```
M.report(entries: Lib.Deps.HealthEntry[])            -- { bin?, python_module?, label?, hint?, required? }
M.from_tools(tools: Lib.Deps.Tool[])
M.report_for(plugin_name: string)
```

### `lib.nvim.deps.spec`
Parse/validate a plugin's declared external-tool requirements.
```
M.parse_markdown(text: string): Lib.Deps.ParseResult   -- { tools, errors }
M.parse_json(text: string): Lib.Deps.ParseResult
M.load(path: string): (result|nil, string|nil err)
M.find(plugin_name: string): string|nil path
M.plugins(): string[]
```

### `lib.nvim.deps.pm`
OS package-manager detection and install-command composition — pure,
never executes anything.
```
M.get(id: string): Lib.Deps.Manager|nil
M.ids(): string[]
M.available(): Lib.Deps.Manager[]
M.detect(): Lib.Deps.Manager|nil
M.is_root(): boolean
M.commands(manager, packages: string[]): string[][]
M.needs_terminal(manager): boolean
M.render(argv: string[]): string   -- display/paste only, never handed to a shell
```

### `lib.nvim.deps.install`
Turn a parsed tool spec into an install plan (pure), and — only on an
explicit confirmed call — open a terminal with the composed command typed.
```
M.plan(tools: Lib.Deps.Tool[], opts?: { manager? }): Lib.Deps.Plan
M.run(plan: Lib.Deps.Plan, opts?: { confirm? }): boolean started
```

### `lib.nvim.deps.view`
Render a plugin's declared tools into buffer lines, show in a popup.
```
M.render(plugin_name, result, opts?, ui?): { lines, line_tools }
M.lines(plugin_name, result, opts?): string[]
M.show_split(plugin_name, result): integer bufnr, integer winid
M.show(plugin_name, result, opts?): integer bufnr, integer winid
```

### `lib.nvim.deps.first_run`
Show a plugin's declared-tools popup exactly once, ever, persisted across restarts.
```
M.seen(plugin_name, cache_opts?): boolean
M.mark_seen(plugin_name, cache_opts?)
M.reset(plugin_name?, cache_opts?)
M.show_once(plugin_name, opts?): boolean shown
  -- opt-out via vim.g.lib_nvim_deps_disable_first_run / vim.g.lib_nvim_deps_disabled_plugins
```

---

## `lib.nvim.treesitter.*`

### `lib.nvim.treesitter.guard` (see README)
Filetype allowlist gate for treesitter-dependent features.
```
M.DEFAULT_WHITELIST: table<string, boolean>
M.is_enabled(bufnr: integer, whitelist?: table<string, boolean>): boolean
```

### `lib.nvim.treesitter.parser_policy` (see README)
Prompt-or-auto-install policy for missing-but-available treesitter parsers.
```
M.setup(opts?: Lib.Treesitter.ParserPolicy.SetupOpts)
M.get_mode(): "off"|"prompt"|"auto"     -- default "prompt"
M.set_mode(mode): boolean ok, string? err
M.declined(): string[]                   -- persisted via lib.nvim.cache.disk
M.reset_declined()
M.ensure(lang: string, opts?: Lib.Treesitter.ParserPolicy.EnsureOpts)
```

---

## `lib.nvim.store.*`

### `lib.nvim.store` (see README) — thin re-export of `store.project`.

### `lib.nvim.store.project` (see README)
Persistent state keyed by project (git root, normalized).
```
M.save(key: string, data: any, opts?): boolean ok, string|nil err
M.load(key: string, opts?): any|nil        -- nil if missing/unreadable/(with ttl_seconds) expired
M.clear(key: string, opts?): boolean ok
M.root(opts?): string
M.stats(key: string, opts?): Lib.Cache.Stats   -- { exists, saved_at, age_seconds, size_bytes }
```

---

## `lib.nvim.logger` (see README)

Structured logging, diagnostics and crash-dump facility — richer sibling
of `lib.nvim.notify`: structured context, bounded in-memory history,
optional JSONL file sink, crash-dump wiring, near-zero-cost kill switches.

**Module-level (global):**
```
M.new(opts?: Lib.Logger.Options): Lib.Logger.Instance
  -- opts: name, level (default "debug"), notify_level (default "warn"), file (nil=default path/false=off/string),
  --       capture (flush on VimLeavePre, default true), history, redact
M.setup(opts?: table)                    -- merges into global defaults for future M.new() calls
M.set_enabled(on: boolean) / M.is_enabled(): boolean
M.set_level(level?: Lib.Logger.LevelInput)
M.disable_tag(tag) / M.enable_tag(tag)
M.only_tags(tags?: string[])
M.tags(): { disabled, only }
M.loggers(): Lib.Logger.Instance[]
```

**Instance methods:**
```
inst.log(level, msg, ctx?, call_opts?) / inst.trace/debug/info/warn/error(msg, ctx?, call_opts?)
inst.set_enabled(on) / inst.is_enabled() / inst.set_level(level)
inst.flush(): boolean         -- writes the whole ring to the file sink now
inst.snapshot(): Lib.Logger.Record[]
inst.clear()
inst.once(key, level, msg, ctx?): boolean
inst.timer(label, level?): fun(ctx?)   -- returned closure logs elapsed ms
inst.guard(fn, fname?): function        -- xpcall wrapper, logs + flushes + RE-RAISES
inst.wrap(fn, fname?): function         -- same, but SWALLOWS the error
inst.assert(cond, msg, ctx?)
inst.count(key): integer                -- frequency tally, not a log record
inst.counters(): table<string,integer>
inst.add_sink(fn: fun(record))
```

`:LibLogger` command (installed on first `logger.new()`): `show [n]`,
`on|off`, `level <l>`, `dump`, `clear`, `tags`.

---

## `lib.nvim.progress` (see README)

Cross-platform, style-agnostic progress-indicator handle — decouples
"reporting on a long-running operation" from how it's shown (`vim.notify`,
statusline, `fidget.nvim`, or an interactive float).

```
M.create(opts?: Lib.Progress.Opts): Lib.Progress.Handle
```
`opts`: `title` (default `""`), `style` (`"auto"|"notify"|"statusline"|"fidget"|"float"|"kit"`,
default `"auto"` — prefers fidget if installed else notify), `delay_ms`
(default 150), `level`, `kit_theme`.

**Returned handle:**
```
h:update(fields?: { text?, current?, total? })
h:finish(text?: string)      -- silent no-op if the delay guard never elapsed
h:cancel(text?: string)
h:on_cancel(fn: fun())
h:request_cancel()           -- sets h.cancelled=true, runs every on_cancel callback, then h:cancel()
h.cancelled: boolean
```

---

## `lib.nvim.harvest.*`

Building-block library for "collect something from a scope, then show or
export it" — three independent pieces, no framework glue.

### `lib.nvim.harvest` (see README) — top level
```
M.scope, M.render, M.sink   -- re-exports, see below
M.emit(text: string, out?: string, opts?): boolean ok, string|nil err
  -- out: "table"/"buffer" (scratch), "clipboard"/"clip", "echo", "file:<path>" (or "file" with opts.path)
M.outputs(): string[]   -- { "buffer", "clipboard", "echo", "file:", "table" }
```

### `lib.nvim.harvest.scope`
Resolve a "where should I look?" descriptor into a flat list of
`Lib.Harvest.Source` records (lines + provenance).
```
M.resolve(kind: "buffer"|"range"|"buffers"|"cwd"|"path"|nil, opts?): (sources[], string|nil err)
M.resolve_token(token: string|nil, opts?): (sources[], string|nil err)
  -- "" / "%" -> buffer; "cwd"/"buffers"/"buffer"/"range" -> themselves; else -> treated as path
```
`Source = { file?, bufnr?, lines: string[], first: integer }`.
`opts`: `bufnr, line1/line2, path, recursive (default true), match, ignore
(default fs.ignore.list), max_files (default 2000), max_filesize (default 1 MiB)`.

### `lib.nvim.harvest.render`
Header list + row matrix -> text.
```
M.markdown_table(headers: string[], rows: any[][], opts?: { align? }): string
M.csv(headers: string[]|nil, rows: any[][], sep?: string): string   -- default ",", RFC 4180 quoting
M.lines(rows: any[][], sep?: string): string                        -- default "  "
```

### `lib.nvim.harvest.sink`
```
M.clipboard(text: string): boolean ok, string|nil err
M.file(text: string, path: string): boolean ok, string|nil err
M.scratch(text: string, opts?: Lib.Harvest.ScratchOpts): integer bufnr
M.select(items: T[], opts?, on_choose: fun(item, idx))   -- kit.select if available, else vim.ui.select
```

---

## `lib.nvim.git` (see README)

Composable Git query helpers; every function shells out via
`lib.nvim.cross.run_argv` (argv, no shell), side-effect free. Returns
`nil`/`false` (not throw) on failure/no-repo.

```
M.in_git_repo(git_cmd?: string): boolean
M.repo_root(git_cmd?: string): string|nil
M.current_branch(git_cmd?: string): string|nil
M.is_detached_head(git_cmd?: string): boolean
M.is_dirty(git_cmd?: string): boolean
M.is_tracked(path: string, git_cmd?: string): boolean
M.upstream(git_cmd?: string): string|nil        -- "origin/main"-style
M.ahead_behind(git_cmd?: string): boolean ahead, boolean behind   -- vs @{u}
M.head_short_hash(git_cmd?: string): string|nil
M.info(dir: string, git_cmd?: string): { branch, version, commit }
M.status_porcelain(git_cmd?: string): table<string, {code, orig_path}>|nil
M.clear_line_diff(ns: integer): fun(buf: integer): nil
```

---

## `lib.nvim.net.curl` (see README)

Async/blocking HTTP-via-curl. Spawns via `vim.system` (Neovim 0.10+, no
`jobstart` fallback). curl's exit code ≠ HTTP status — `fetch_raw*` parse
status from the response's status line.

```
M.fetch_raw(url, opts: Lib.Net.Curl.FetchOpts|nil, cb: fun(ok, response_or_err, raw_obj))          -- async
M.fetch_raw_blocking(url, opts?): boolean ok, response_or_err, raw_obj
M.fetch_json(url, opts, cb: fun(ok, data_or_err, raw_obj))                                          -- async, JSON-decoded
M.fetch_json_blocking(url, opts?): boolean ok, data_or_err, raw_obj
```

---

## `lib.nvim.lua_ls.*`

### `lib.nvim.lua_ls.get_module_path` (see README)
Absolute file path -> the `require`-style dotted module path (finds the
first `/lua/` segment, strips `.lua`/trailing `/init`, dot-joins).

```
return function(filepath: string): string|nil module_path
```

### `lib.nvim.lua_ls.insert.module_annnotation` (see README — note: directory
literally spelled `module_annnotation`, triple-n, in the source tree)
Inserts a `---@module '...'` annotation at a buffer position.

```
return function(opts?: { bufnr?, row?, col? }): boolean success
  -- no args -> current buffer + cursor; explicit position overrides cursor
```

---

## `lib.nvim.cache.*`

### `lib.nvim.cache` (aggregator, see README) — two backends: `disk` and `memory`.

### `lib.nvim.cache.disk`
Persistent JSON disk cache with TTL, one JSON file per namespace under
`stdpath("cache")/lib.nvim/cache/<namespace>.json`.
```
M.save(namespace: string, data: any, opts?): boolean ok, string|nil err
M.load(namespace: string, opts?): any|nil
M.clear(namespace: string, opts?): boolean ok
M.stats(namespace: string, opts?): Lib.Cache.Stats
```

### `lib.nvim.cache.memory`
In-memory cache namespaces: per-key TTL and/or buffer-`changedtick`
validation, hit/miss/eviction stats, opt-in autocmd auto-invalidation.
Does not survive restart; monotonic clock (`vim.uv.hrtime`).
```
M.namespace(name: string, opts?): Lib.Cache.Memory.Namespace
  -- ns.get(key, bufnr?), ns.set(key, value, bufnr?), ns.invalidate(key), ns.clear(), ns.stats()
M.setup_auto_invalidation(opts?: { prefix? })   -- idempotent; TextChanged prunes, BufWritePost clears all
M.disable_auto_invalidation()
M.is_auto_invalidation_enabled(): boolean
M.get_all_stats(): Lib.Cache.Memory.Stats[]
M.print_all_stats()
```

---

## `lib.nvim.core` (see README)

Grab-bag: memoized executable lookup, preallocated `nvim_echo` wrapper.

```
M.has_exec(bin: string): boolean            -- memoized per binary name
M.first_available(candidates: string[]): string|nil
M.forget_exec(bin: string): nil             -- drops cached result
M.simple_echo   -- = require("lib.nvim.core.simple_echo") (lazy)
```

### `lib.nvim.core.simple_echo` (no README)
```
return function(msg: string, hl: string|nil, is_error: boolean|nil): integer|string
```

---

## `lib.nvim.normalize.*` (aggregator, see README)

Strict coercion toolkit for plugin configs at config boundaries, plus
schema-merge utilities. Pure; uses `vim.fs.normalize`/`vim.uv` with fallback.

**Direct value normalizers** (return `nil` on unparseable input, not an error):
```
M.to_bool(v): boolean|nil
M.to_int(v, min?, max?): integer|nil          -- truncates toward zero, clamps
M.to_float(v, min?, max?, precision?): number|nil
M.to_string(v, allow_empty?, do_trim?): string|nil
M.to_enum(v, allowed, case_insensitive?): string|nil
M.to_string_list(v, opts?: {sep?, trim?, dedup?}): string[]|nil
M.to_argv(v): string[]|nil                     -- best-effort shell-token split, double-quote segments only
M.to_diagnostic_severity(v): integer|nil       -- -> vim.diagnostic.severity.*
M.to_log_level(v): integer|nil                 -- -> vim.log.levels.*
M.to_path(v, type_filter?, must_exist?): string|nil
```

**Validators, `(ok, val, err)` contract:**
```
M.as_int(name, v, min, allow_nil): boolean ok, integer|nil val, string|nil err
M.as_bool(name, v): boolean ok, boolean|nil val, string|nil err   -- only real Lua booleans, no coercion
M.is_one_of(v, candidates): boolean
M.buf_valid(bufnr): boolean
M.win_valid(winid): boolean
```

**Utilities:**
```
M.trim(s): string
M.clamp(n, min, max): number
M.coalesce(...): T|nil                          -- first non-nil
M.path_kind(p): "file"|"directory"|""
M.normalize_path(p): string                     -- ~/$VAR/%VAR% expansion then vim.fs.normalize
M.dedup_strings(list): string[]                 -- order-preserving
```

---

## `lib.nvim.require` (see README)

Safe/extended `require` utilities.

```
M.safe(name: string): boolean ok, any result       -- pcall(require, name)
M.dir(dir: string, calls?: string|string[]|"")
  -- non-recursively requires every *.lua directly in stdpath("config").."/lua/"..dir, then
  --   nil -> mod.setup({}); string -> call that name (""=require only); string[] -> call each in order
M.lazy(module_name: string): fun(): table          -- requires+caches on first call
```

---

## `lib.nvim.safe_api` (see README)

Validated, `pcall`-wrapped `vim.api` accessors for buffers/windows — every
call shares return shape `(success, result, error)`.

```
M.safe_call(fn: function, ...): boolean success, any|nil result, string|nil error
M.is_valid_buffer(bufnr): boolean       -- fast, no pcall
M.is_valid_window(winnr): boolean       -- fast, no pcall
M.buf_get_lines(bufnr, start, end_, strict_indexing): boolean, string[]|nil, string|nil
M.buf_line_count(bufnr): boolean, integer|nil, string|nil
M.buf_get_option(bufnr, name): boolean, any|nil, string|nil
M.buf_set_option(bufnr, name, value): boolean, nil, string|nil
M.buf_set_extmark(bufnr, ns_id, line, col, opts): boolean, integer|nil, string|nil
M.set_extmark(bufnr, ns_id, line, col_start, col_end, hl_group, line_content, priority?): boolean, integer|nil, string|nil
M.buf_clear_namespace(bufnr, ns_id, line_start, line_end): boolean, nil, string|nil
M.win_get_option(winnr, name): boolean, any|nil, string|nil
M.win_set_option(winnr, name, value): boolean, nil, string|nil
M.win_get_buf(winnr): boolean, integer|nil, string|nil
M.win_close(winnr, force): boolean, nil, string|nil
M.buf_delete(bufnr, opts?): boolean, nil, string|nil
M.with_retry(fn, max_retries, ...): boolean, any|nil, string|nil   -- retries only "invalid"/"closed"-looking errors
```

---

## `lib.nvim.system.*` (aggregator, see README)

Host-environment namespace: cached OS/shell/paths snapshot, Windows
named-pipe RPC helper, cross-platform system-info probe. Pure by default;
side effects opt-in via `setup()`.

```
M.setup(opts?: Lib.System.SetupOptions)
  -- flags: publish_globals, rpc_pipe, info_usercmd (each true=defaults or table/string forwarded)
```

### `lib.nvim.system.env`
Memoized host-environment snapshot.
```
M.get(opts?: { refresh? }): Lib.System.Env   -- is_windows, is_wsl, is_linux, is_macos, is_pwsh, repo_base, pathsep, home
M.publish_globals(opts?: { fields? })         -- mirrors snapshot fields to vim.g.*
```

### `lib.nvim.system.rpc_pipe`
Predictable RPC server on a Windows named pipe (no-op off Windows).
```
M.setup(opts?: { debug?, allow_override? })
M.is_active(): boolean
M.get_address(): string|nil
M.clear()
```

### `lib.nvim.system.info`
Cross-platform system information (OS/CPU/RAM/GPU/uptime); backend:
`fastfetch` -> `neofetch` -> platform-native probe.
```
M.build_cmd(opts?): string[] argv
M.get(opts?): string[]|nil lines, string|nil err
M.show(opts?): integer|nil winid, integer|nil bufnr   -- centered float, copies to clipboard by default
M.create_usercmd(name?, opts?)                          -- registers :SystemInfo or custom name
```

### `lib.nvim.system.proc_trace`
Instruments `vim.fn.system`/`systemlist`, `vim.system`, `vim.fn.jobstart`
to measure call duration and log a traceback above a threshold.
```
M.start(opts?: { threshold_ms? (default 200), path? }): { path, active }   -- idempotent
M.stop(): { path, active }
M.is_active(): boolean
M.log_path(): string|nil
```

### `lib.nvim.system.job`
Thin `vim.system` wrapper restoring plenary.job-like ergonomics.
```
M.start(opts: Lib.System.Job.Opts): vim.SystemObj
  -- on_stdout/on_stderr: one call per complete line, trailing \r stripped, already vim.schedule-wrapped
```

---

## `lib.nvim.token` (see README)

Ephemeral session-nonce/token generator. **Not cryptographically secure.**

```
M.gen_token(len?: integer): string   -- default length 16, lowercase hex
```

---

## `lib.nvim.neotree.*`

### `lib.nvim.neotree.node` (see README)
Pure, side-effect-free Neo-tree node/path extraction utilities.
```
M.get_current(state): Lib.Neotree.RawNode|nil
M.get_path(node): string path, boolean is_dir       -- never nil; falls back to "", false
M.collect_nodes(state): Lib.Neotree.RawNode[]        -- marked nodes, else [cursor node]
M.extract_paths(nodes): string[] paths, string[] names
M.get_line_number(state, node_id): integer|nil
```

### `lib.nvim.neotree.watch` (see README)
File-watcher handle registry + proactive release — fixes a Windows
file-lock that intermittently blocks renaming/deleting a directory
neo-tree is watching.
```
M.install(): boolean ok       -- patches neo-tree's fs_watch; idempotent; false if neo-tree absent
M.installed(): boolean
M.release(paths: string|string[]): integer released
M.with_release(paths, fn: fun(): any): any
M.count(): integer
M.list(): { path, active, exists }[]   -- exists=false is the leak signature
M.clear()
```
