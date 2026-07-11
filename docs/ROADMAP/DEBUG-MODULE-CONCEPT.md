# Concept: `lib.nvim.debug` — structured logging, diagnostics & crash dumps

> Status: **concept / design proposal** (no code yet). Working name
> `lib.nvim.debug` is a placeholder — see [Open decisions](#open-decisions).
> Everything here is **cross-platform** (paths via `stdpath` / `system.env`,
> writes via `fs.write` / `vim.uv`; no shell-outs, no OS-specific assumptions).

## 1. Purpose

Every custom plugin re-invents the same diagnostics glue: a `vim.notify`
wrapper, some ad-hoc `print` debugging, and — when something breaks in the
field — no record of *what led up to it*. `notify` today
([lib.nvim.notify](../../lua/lib/nvim/notify/init.lua)) gives us a clean
prefixed `info/warn/error/debug`, but it is **fire-and-forget**: a message is
shown and gone, it carries no structured context, and nothing survives a crash.

`lib.nvim.debug` is the missing layer: **one logging strategy every plugin can
adopt** instead of hand-rolling its own. It provides a logger object that, next
to a normal notify, can carry structured context, persist to disk, keep a
rolling in-memory history, and **reliably dump that history when a plugin
blows up** — so a bug report comes with the last N events and a traceback
instead of "it crashed".

Concretely, the original sketch —

```lua
lib.nvim.SOMENAME("Some normal message", 5, { SOME_KEY = VAL, DUMPINGPATH = "c:/Project/logs" })
```

— becomes a logger method that takes `(message, context)`, with the file
destination configured **once** at logger creation (per-call override allowed),
plus a crash-capture mechanism behind it.

## 2. Relationship to `lib.nvim.notify` (and why a new module)

`notify` stays exactly as-is and keeps its ~call sites. `debug` is a **superset
that composes notify**, it does not replace it:

| | `lib.nvim.notify` | `lib.nvim.debug` |
| --- | --- | --- |
| Surface a message to the user | ✅ `vim.notify` wrapper | ✅ via its **notify sink** (calls `notify.create`) |
| Structured context (`{ key = val }`) | ✗ | ✅ recorded per entry |
| Persist to a file | ✗ | ✅ file sink (JSONL) |
| In-memory history | ✗ | ✅ bounded ring buffer |
| Survive / dump on crash | ✗ | ✅ crash capture |
| Levels (TRACE…ERROR/OFF) | partial | ✅ reuses `resolve_log_level` |
| Safe from fast events | ✅ `notify.safe` | ✅ reuses `notify.safe` |

A logger's **notify sink** delegates to
[`notify.create(prefix)`](../../lua/lib/nvim/notify/init.lua) and, for
fast-event contexts, to
[`notify.safe`](../../lua/lib/nvim/notify/safe/init.lua). Level parsing reuses
[`resolve_log_level`](../../lua/lib/nvim/notify/resolve_log_level/init.lua).
Nothing is duplicated.

## 3. The core object — a logger

Created per plugin, like `notify.create`, but richer:

```lua
local log = require("lib.nvim.debug").new({
  name         = "myplugin",     -- scope / prefix
  level        = "debug",        -- min level to RECORD (into ring + file)
  notify_level = "warn",         -- min level to ALSO surface via vim.notify
  file         = nil,            -- file sink path; nil = stdpath default, false = off
  capture      = true,           -- install crash capture (guard/flush)
  history      = 200,            -- ring-buffer size (recent records kept in memory)
})

log.info("cache warm", { entries = 128, took_ms = 12 })
log.warn("slow query", { ms = 340, query = q })
log.error("write failed", { path = p, err = err })   -- also flushes to disk immediately
```

- **Message + context** — `log.<level>(msg, context?)`. `msg` is a plain
  string (what `notify` shows); `context` is an arbitrary table recorded with
  the entry (never shown in the notify unless `notify_level` includes it and
  the user opts into verbose notifies).
- **Level gate up front** — if the level is below the logger's threshold, the
  call returns *before* touching `context`. For expensive context, pass a
  thunk: `log.debug("state", function() return expensive_snapshot() end)` — the
  thunk is only invoked when the level is active. Zero overhead when off.
- **Every method also accepts** the classic `(msg, level_number, opts)` shape
  for a smooth migration from `notify`.

A **record** (one log entry) is:

```lua
---@class Lib.Debug.Record
---@field ts     integer   # os.time / uv.hrtime for ordering
---@field iso    string    # human timestamp (os.date, local)
---@field level  integer   # vim.log.levels value
---@field scope  string    # logger name
---@field msg    string
---@field ctx    table?    # structured context (safely serialized)
---@field src    string?   # "file:line" via debug.getinfo (opt-in; cost-gated)
```

## 4. Sinks — where records go

A record fans out to zero or more **sinks**, each independently level-gated:

1. **notify sink** — surfaces `msg` through `notify.create` /
   `notify.safe` when `level >= notify_level`. Fast-context-safe.
2. **memory sink (ring buffer)** — keeps the last `history` records in a
   bounded ring (a fixed-capacity structure like
   [`lib.lua.memo.lru`](../../lua/lib/lua/memo/lru.lua) — predictable eviction,
   no unbounded growth). This is the crash-dump payload and the inspector
   source.
3. **file sink** — appends serialized records to disk (see §5). Off unless a
   `file` path is set (or the stdpath default is enabled).
4. **echo sink** *(opt-in)* — `nvim_echo` for immediate inline visibility
   during development.

Sinks are pluggable: `log.add_sink(fn)` lets a plugin add a custom one (e.g.
ship errors to a health check or a status line).

## 5. File sink & path resolution (cross-platform)

- **Default location** (when `file = nil` but persistence is enabled):
  `stdpath("log")/lib-debug/<name>.jsonl`, resolved via `vim.fn.stdpath` — the
  canonical cross-platform per-OS location. `system.env`
  ([system/env.lua](../../lua/lib/nvim/system/env.lua)) supplies `pathsep` /
  `home` where a manual join is needed.
- **Explicit path** (the sketch's `DUMPINGPATH`, renamed `file`): any absolute
  path; parent dirs are created for you. Per-call override via
  `log.error(msg, ctx, { to = "…" })` when a single entry must go elsewhere.
- **Format: JSONL** — one JSON object per line. Greppable, appendable, machine-
  readable, and trivially tailable. (Note: the current
  [`lib.lua.json`](../../lua/lib/lua/json/init.lua) only *decodes*; the debug
  module needs a small, safe **encoder** for records — a genuine new primitive,
  candidate to live in `lib.lua.json` so others can reuse it.)
- **Safe serialization** — `context` tables are serialized defensively:
  functions → `"<function>"`, userdata/threads → tagged, cycles broken, depth-
  capped. Human inspection uses `vim.inspect`; the file uses the JSONL encoder.
- **Writing** — appends via `vim.uv` (non-blocking) reusing the
  [`lib.nvim.cross.uv`](../../lua/lib/nvim/cross/uv) spawn/fs helpers, with a
  synchronous `io.open(path, "a")` fallback. (The existing
  [`fs.write.to_file`](../../lua/lib/nvim/fs/write/to_file/init.lua) truncates
  (`"w"`); the sink needs an **append** path — small addition, either an
  `fs.write.append` sibling or an internal helper.)
- **Optional rotation** — cap file size / keep last K files, so a long session
  doesn't grow unbounded. Phase 4.

## 6. Crash capture — the reliable "dump on failure" mechanism

This is the trickiest requirement, so the design is explicit about **what
Neovim actually allows**. There is *no* global "uncaught Lua error" hook, and a
hard editor crash (segfault) is unrecoverable. What *is* reliable is a
combination of four mechanisms, in order of strength:

1. **Flush-on-error (always on).** The moment an `ERROR` record is logged, the
   ring buffer is flushed **synchronously** to the file sink. So even if the
   editor dies immediately afterward, the last N events + the error are already
   on disk. This is the single most important guarantee and needs no
   cooperation from the caller.
2. **`log.guard(fn)` / `log.wrap(fn)` (primary catch).** `xpcall` wrappers with
   a traceback handler. A plugin wraps its entrypoints — command handlers,
   autocmd/keymap callbacks, async completions — and any error inside is caught,
   recorded as an `ERROR` with the **full traceback + a ring-buffer snapshot**,
   flushed, and then either re-raised or swallowed per option. This is how you
   capture the errors Neovim would otherwise just print to `:messages`.
   ```lua
   vim.keymap.set("n", "<leader>x", log.guard(function() risky() end))
   -- or wrap a whole module's public fns:
   M.run = log.wrap(M.run)   -- named for the traceback
   ```
3. **`VimLeavePre` flush (safety net).** An autocmd (via
   [`lib.nvim.autocmd`](../../lua/lib/nvim/autocmd/init.lua) +
   [`augroup`](../../lua/lib/nvim/autocmd/augroup.lua)) flushes the ring buffer
   on exit, covering `:qa!` and clean-ish shutdowns where nothing errored but
   the session history is still wanted.
4. **Opt-in `vim.notify` interception.** When `capture = true` *and* the user
   opts into it, wrap `vim.notify` so any `ERROR`-level notify from *anywhere*
   (even code that doesn't use this module) snapshots the ring buffer. Invasive
   (monkeypatch), hence off by default and clearly documented.

Honest scope note (in the doc, not hidden): mechanisms 1–3 are robust and need
no external process; mechanism 4 is best-effort; a native segfault is out of
reach for any Lua-level logger.

## 7. Diagnostics extras (the "weitere Features")

Cheap, high-value additions that ride on the same records/sinks:

- **Scopes & timing** — `local done = log.scope("index build")` returns a
  child logger; `done()` logs the elapsed duration (reusing
  [`lib.lua.time.diff`](../../lua/lib/lua/time/diff/init.lua)). Great for "why
  is startup slow".
- **Counters / one-shot** — `log.once(key, msg, ctx)` logs a given key only the
  first time (deduplicate noisy warnings); `log.count(key)` for frequency.
- **Assertions** — `log.assert(cond, msg, ctx)` records + raises through
  `guard`, so a failed invariant lands in the dump.
- **`:LibDebug` command** (via
  [`lib.nvim.usercmd`](../../lua/lib/nvim/usercmd/init.lua)) — runtime control
  without restarting: `:LibDebug show` (recent records in a float — a natural
  consumer of the future `ui.kit`), `:LibDebug level <n>`, `:LibDebug dump`
  (flush now), `:LibDebug tail`, `:LibDebug clear`.
- **Redaction** — a `redact = { "token", "password" }` option scrubs matching
  context keys before they hit any sink (don't leak secrets into logs).
- **Health integration** — `:checkhealth lib` surfaces the active loggers,
  their levels, and the file-sink path; probe added to
  [`lib/health.lua`](../../lua/lib/health.lua).

## 8. Architecture — layers

```
┌───────────────────────────────────────────────────────────┐
│ Extras     scope/timing · once/count · assert · :LibDebug   │
├───────────────────────────────────────────────────────────┤
│ Capture    flush-on-error · guard/wrap · VimLeavePre flush  │
├───────────────────────────────────────────────────────────┤
│ Sinks      notify · memory(ring) · file(JSONL) · echo · …   │
├───────────────────────────────────────────────────────────┤
│ Core       logger factory · record · level gate · serialize │
└───────────────────────────────────────────────────────────┘
   ↑ reuses: notify(.create/.safe), resolve_log_level, memo(ring),
              fs.write, cross.uv, system.env, time.diff, usercmd, autocmd
```

Each layer is usable alone: a plugin that only wants "notify + structured
history" uses Core + Sinks; crash capture and the inspector are additive.

## 9. Cross-platform notes

- Paths through `vim.fn.stdpath` + `system.env.pathsep`; never a hardcoded
  separator. The sketch's `"c:/Project/logs"` works, and so does a POSIX path.
- Writes through `vim.uv` (async) / `io.open` (sync fallback); newline `\n`
  only — fine on every OS.
- No shell-outs, no external tools. Timestamps via `os.date`/`os.time`
  (portable).

## 10. Registration & documentation plan

Per the task's requirement, every feature is wired into the three surfaces the
library already uses:

1. **Module layout** — `lua/lib/nvim/debug/` with `init.lua` per submodule and
   `@types/` folders (repo convention). Likely: `debug/init.lua` (factory),
   `debug/record.lua`, `debug/sinks/{notify,memory,file,echo}.lua`,
   `debug/capture.lua`, `debug/serialize.lua`, `debug/command.lua`,
   `debug/config/` + `debug/config/DEFAULTS.lua`.
2. **Aggregator** — add a key to all three strategies so `require("lib").debug`
   resolves: `MODULE_MAP` in
   [strategies/metatable.lua](../../lua/lib/strategies/metatable.lua), plus
   [lazy.lua](../../lua/lib/strategies/lazy.lua) and
   [eager.lua](../../lua/lib/strategies/eager.lua)
   (e.g. `debug = "lib.nvim.debug"`).
3. **`@types/all_functions.lua`** — add
   [`---@field debug Lib.Debug`](../../lua/lib/@types/all_functions.lua) so
   `require("lib").debug` gets full LSP types.
4. **Vimdoc** — a new section in
   [doc/lib.nvim.txt](../../doc/lib.nvim.txt) tagged `*lib.nvim-debug*` (+ per-
   feature tags), plus a dedicated `doc/lib.nvim-debug.txt`, following the two-
   tier docs convention in `*lib.nvim-conventions*`; per-module `README.md`
   next to the source.
5. **Health** — extend [lib/health.lua](../../lua/lib/health.lua)'s `PROBE`
   list with a `debug` module and report active loggers / sink paths.

## 11. Phased roadmap

| Phase | Deliverable | Notes |
| ----- | ----------- | ----- |
| **1** | Logger factory + levels + **notify sink** + **memory ring** + safe serialization | Drop-in richer than `notify.create`; `(msg, ctx)` API; zero-cost level gate |
| **2** | **File sink** (JSONL append, async via uv, stdpath default + `file` override) + flush-on-error + JSON **encoder** primitive | The "DUMPINGPATH" feature, done cross-platform |
| **3** | **Crash capture** (`guard`/`wrap` + `VimLeavePre` flush) + `:LibDebug` inspector | The reliable "dump on failure" mechanism |
| **4** | Scopes/timing, `once`/`count`, assertions, redaction, rotation, opt-in `vim.notify` interception | Diagnostics polish |

## 12. Open decisions

1. **Name.** Recommendation: `lib.nvim.debug` (matches the request).
   Alternative: `lib.nvim.log` (more conventional; "debug" can read as
   "debug-level only", but the request explicitly says *Debug Modul*). *Pick
   before Phase 1.* Note: as a module *path* it does not shadow Lua's global
   `debug`.
2. **`DUMPINGPATH` key name & scope.** Recommendation: rename to **`file`**,
   configured **once** at `new()` (per-call `{ to = … }` override), rather than
   repeated on every call — cleaner and less error-prone than the sketch's
   per-call key.
3. **File format.** Recommendation: **JSONL** (machine + grep friendly) for the
   file; `vim.inspect` for the human inspector. Requires a small JSON *encoder*
   (new; propose it lands in `lib.lua.json` for reuse).
4. **Append helper.** `fs.write.to_file` truncates; Phase 2 needs an append
   path — decision: add `lib.nvim.fs.write.append` (reusable) vs. keep it
   internal to the file sink. Recommendation: **`fs.write.append`** sibling.
5. **`vim.notify` interception.** Recommendation: **off by default**, opt-in
   only — monkeypatching a global is powerful but invasive; the other three
   capture mechanisms cover the common cases without it.
