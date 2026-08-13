# Infrastructure & misc utilities

Everything that doesn't fit "windows," "filesystem," "commands," or
"cross-platform" cleanly, but that a real plugin still ends up needing:
persistent per-project storage, caching, external-dependency handling,
treesitter gating, progress reporting, Git queries, HTTP, and a handful of
small validated-API/normalization helpers.

## Persistent per-project storage

State keyed by project (git root, normalized via `find_root`) that survives
a restart — for a plugin's own last-used settings, a per-project index, or
anything that shouldn't leak across unrelated repos.

- **Module:** `lib.nvim.store.project` (`save`, `load`, `clear`, `root`,
  `stats`), re-exported as `lib.nvim.store`

```lua
local store = require("lib.nvim.store.project")
store.save("last-branch", "feature/x")
local branch = store.load("last-branch")   -- nil if missing/unreadable/(with ttl) expired
```

## Disk and in-memory caching

Two independent backends for two different lifetimes: `cache.disk`
persists a namespaced JSON file across restarts with TTL support;
`cache.memory` is a faster, restart-lossy namespace with per-key TTL and/or
buffer-`changedtick` validation, hit/miss stats, and opt-in autocmd
auto-invalidation.

- **Module:** `lib.nvim.cache.disk` (`save`, `load`, `clear`, `stats`),
  `lib.nvim.cache.memory` (`namespace`, `setup_auto_invalidation`)

```lua
local ns = require("lib.nvim.cache.memory").namespace("my-plugin")
ns.set("key", value, bufnr)   -- optionally tied to this buffer's changedtick
ns.get("key", bufnr)          -- nil once the buffer's tick has moved past it
```

`cache.memory.setup_auto_invalidation()` is idempotent and wires
`TextChanged` (prune stale) / `BufWritePost` (clear all) automatically.

## External-dependency detection and confirmed install

Detects whether a plugin's declared external CLI tools are present,
composes an OS-appropriate install command, and only ever hands the
command to a terminal — typed, never submitted — on an explicit user
action. **Requiring any module here executes nothing.**

- **Module:** `lib.nvim.deps` (aggregator: `show_once`, `plugins`, `show`,
  `install_for`), `lib.nvim.deps.spec` (parses a plugin's declared tools
  from Markdown/JSON), `lib.nvim.deps.pm` (package-manager detection, pure),
  `lib.nvim.deps.install` (`plan`, `run`), `lib.nvim.deps.health`,
  `lib.nvim.deps.first_run` (show a plugin's tools popup exactly once, ever)

```lua
require("lib.nvim.deps").show_once("my-plugin")   -- first-run popup, persisted
require("lib.nvim.deps.health").report_for("my-plugin")   -- from your own health.lua
```

## Treesitter parser gating and install policy

A filetype allowlist gate for treesitter-dependent features, plus a
prompt-or-auto-install policy for a parser that's available but not yet
installed — so a plugin doesn't have to hand-roll "is treesitter even safe
to use here" logic per callback.

- **Module:** `lib.nvim.treesitter.guard` (`is_enabled`,
  `DEFAULT_WHITELIST`), `lib.nvim.treesitter.parser_policy` (`setup`,
  `get_mode`, `ensure`, `declined`)

```lua
if require("lib.nvim.treesitter.guard").is_enabled(bufnr) then
  require("lib.nvim.treesitter.parser_policy").ensure("lua")
end
```

`parser_policy` mode defaults to `"prompt"` (ask once, remember a decline
via `lib.nvim.cache.disk`); `"auto"` installs silently; `"off"` never
touches a parser.

## Progress reporting, decoupled from its display

A handle for "report on a long-running operation" that doesn't know or care
whether the result is shown via `vim.notify`, a statusline segment,
`fidget.nvim`, or an interactive float — the caller picks a style, or lets
it auto-detect.

- **Module:** `lib.nvim.progress` (`create`)
- **Config:** `opts.style` — `"auto"` (default, prefers fidget if installed
  else notify), `"notify"`, `"statusline"`, `"fidget"`, `"float"`, `"kit"`;
  `opts.delay_ms` (default 150, suppresses flicker on fast operations)

```lua
local h = require("lib.nvim.progress").create({ title = "Indexing" })
h:update({ current = 3, total = 10 })
h:finish("done")
```

`h:finish()` is a silent no-op if the delay guard never elapsed — a
sub-150ms operation never flashes a progress indicator at all.

## Harvest: collect, render, output

Three independent building blocks for "collect something from a scope, then
show or export it" — no framework glue holding them together, so a plugin
can use just the piece it needs.

- **Module:** `lib.nvim.harvest.scope` (resolve buffer/range/buffers/cwd/path
  into source records), `lib.nvim.harvest.render` (`markdown_table`, `csv`,
  `lines`), `lib.nvim.harvest.sink` (`clipboard`, `file`, `scratch`,
  `select`), `lib.nvim.harvest` (`emit`, `outputs`)

```lua
local harvest = require("lib.nvim.harvest")
local sources = require("lib.nvim.harvest.scope").resolve("buffers")
harvest.emit(text, "clipboard")   -- or "buffer", "echo", "file:<path>", "table"
```

## Composable Git query helpers

Side-effect-free Git queries, every one shelling out via the argv runner
(no shell interpolation), returning `nil`/`false` on failure rather than
throwing — safe to call speculatively without checking "am I in a repo"
first.

- **Module:** `lib.nvim.git` (`in_git_repo`, `repo_root`, `current_branch`,
  `is_dirty`, `is_tracked`, `upstream`, `ahead_behind`, `head_short_hash`,
  `status_porcelain`, `info`)

## Async/blocking HTTP via curl

Spawns `curl` through `vim.system` (Neovim 0.10+, no `jobstart` fallback).
Handles the gotcha that curl's own exit code is not the HTTP status — the
raw/JSON fetch variants parse status straight off the response's status
line instead of trusting the exit code.

- **Module:** `lib.nvim.net.curl` (`fetch_raw`, `fetch_raw_blocking`,
  `fetch_json`, `fetch_json_blocking`)

## Config-boundary normalization and validation

A strict coercion toolkit for the exact place a plugin's user-facing config
table meets real code — pure functions returning `nil` on unparseable input
rather than raising, plus a stricter `(ok, val, err)` validator family for
call sites that need to surface a real error message.

- **Module:** `lib.nvim.normalize` (`to_bool`, `to_int`, `to_float`,
  `to_string`, `to_enum`, `to_string_list`, `to_argv`, `to_path`, `as_int`,
  `as_bool`, `buf_valid`, `win_valid`, `clamp`, `coalesce`, `dedup_strings`)

```lua
local port = require("lib.nvim.normalize").to_int(opts.port, 1, 65535)  -- nil if out of range/unparseable
```

## Validated, pcall-wrapped `vim.api` accessors

Every buffer/window API call here shares one return shape —
`(success, result, error)` — instead of the mix of throw-on-invalid-handle
and silent-failure behavior the raw `vim.api` functions have individually.

- **Module:** `lib.nvim.safe_api` (`safe_call`, `is_valid_buffer`,
  `is_valid_window`, `buf_get_lines`, `buf_set_extmark`, `win_close`,
  `with_retry`)

`with_retry(fn, max_retries, ...)` specifically retries only
"invalid"/"closed"-looking errors — a window that closed between a check and
a use, not an arbitrary bug being papered over.

## Safe/extended require

- **Module:** `lib.nvim.require` (`safe`, `dir`, `lazy`)

`safe(name)` is `pcall(require, name)` with a friendlier return shape.
`dir(dir, calls?)` non-recursively requires every `*.lua` directly under
`stdpath("config")/lua/<dir>/` and optionally calls a named function
(`.setup({})` by default) on each — the "load every module in this
directory" pattern a config's own `plugins/` folder often wants. `lazy(name)`
returns a function that requires-and-caches on first call, for a value that
must not be resolved at load time (avoiding require cycles).

## Host-environment snapshot and system info

A memoized snapshot of platform/shell facts (avoids re-probing per call),
optional Windows named-pipe RPC for external tooling, and a cross-platform
system-information probe with backend fallback.

- **Module:** `lib.nvim.system.env` (`get`, `publish_globals`),
  `lib.nvim.system.rpc_pipe` (Windows-only, no-op elsewhere),
  `lib.nvim.system.info` (`get`, `show`, `create_usercmd`)

`system.info` tries `fastfetch` → `neofetch` → a platform-native probe, in
that order, and `show()` copies the result to the clipboard by default.

## Call-duration tracing

Instruments `vim.fn.system`/`systemlist`, `vim.system`, and
`vim.fn.jobstart` to measure call duration and log a traceback above a
threshold — a diagnostic for "something is calling out to a process too
often or too slowly" without manually wrapping every call site.

- **Module:** `lib.nvim.system.proc_trace` (`start`, `stop`, `is_active`,
  `log_path`)
- **Config:** `opts.threshold_ms` (default 200)

## Memoized executable lookup

A small grab-bag distinct from `cross.executable`: a memoized "does this
binary exist" check plus a first-available-candidate helper, for a hot path
that would otherwise re-run `executable()` on every call.

- **Module:** `lib.nvim.core` (`has_exec`, `first_available`, `forget_exec`)

## Ephemeral session tokens

A short random hex token generator for session-scoped nonces (correlating a
request/response pair, a one-time UI key). **Not cryptographically secure**
— explicitly not for anything security-sensitive.

- **Module:** `lib.nvim.token` (`gen_token`)

## Neo-tree node extraction and Windows watch-handle fix

Pure node/path extraction for Neo-tree state (works the same whether one
node or a marked selection is active), plus a fix for a real Windows bug:
neo-tree's file watcher can hold a lock that intermittently blocks
renaming/deleting a directory it's watching.

- **Module:** `lib.nvim.neotree.node` (`get_current`, `get_path`,
  `collect_nodes`, `extract_paths`), `lib.nvim.neotree.watch` (`install`,
  `release`, `with_release`, `list`)

```lua
require("lib.nvim.neotree.watch").with_release(path, function()
  os.rename(path, new_path)  -- watch handle released for the duration, then re-armed
end)
```

## LuaLS module-path helpers

Two small editor-integration helpers for writing correct `---@module`
annotations without hand-typing a dotted path: resolving an absolute file
path to its `require`-style module path, and inserting the annotation at a
buffer position.

- **Module:** `lib.nvim.lua_ls.get_module_path`,
  `lib.nvim.lua_ls.insert.module_annnotation` (directory name is spelled
  with a triple-n in the source tree)
