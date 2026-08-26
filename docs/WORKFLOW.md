# Workflow: adopting `lib.nvim` in your own plugin

This is not an end-user manual — `lib.nvim` has no end user. Its real
consumers are ~25+ of the same author's other plugins, each declaring it as
a hard [lazy.nvim] dependency. This page is the "which module do I reach
for, and how do these pieces actually combine" reference for **writing one
of those plugins**, not for typing commands in Neovim.

## Getting `lib.nvim` into your plugin at all

Declare it as a dependency; lazy.nvim loads it on demand the first time your
plugin code `require`s something under `lib.*`:

```lua
-- your-plugin.nvim's own lazy.nvim spec, or the consuming config's
{
  "you/my-plugin.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
}
```

Inside your plugin's own Lua, prefer requiring leaf modules directly over
the `require("lib")` aggregator — it's tree-shake friendly and makes the
actual dependency surface grep-able:

```lua
local notify = require("lib.nvim.notify").create("[my-plugin]")
local fs     = require("lib.nvim.fs.find_root")
```

Reach for `require("lib")` only when you already hold `lib` and want several
pieces off of it in one place, or in an interactive/debug context where
brevity matters more than tree-shaking.

**One load-order trap that isn't your plugin's problem, but will surface as
a bug report against your plugin if you don't know it exists:** a user who
requires `lib.*` directly in their own `init.lua`/config (not just inside a
plugin) needs a `package.path` bootstrap *before* `require("lazy").setup()`
runs — lazy.nvim's own module loader ignores runtimepath entries added after
`setup()`, so a plain plugin spec is too late for config-wide use. This only
matters for a user consuming `lib.nvim` directly in their config; a plugin
that only uses `lib.*` inside its own `lua/my-plugin/*` files never hits it
— lazy.nvim resolves the dependency normally before your plugin's own code
runs. See [installation.md](installation.md) if you ever need to explain
this to a user.

## Picking the right namespace

`lib.lua.*` is editor-independent (no `vim` API at all — safe to unit-test
outside Neovim, safe to eventually move to a standalone Lua library).
`lib.nvim.*` is the Neovim adapter layer — this is what you want for
essentially everything in a real plugin.

## Registering a command: raw API, `usercmd.create`, or `composer`?

Three tiers, pick the cheapest one that fits:

- **A single command with no subcommands, simple args:**
  `require("lib.nvim.usercmd").create(name, fn, opts)`. You get
  `force = true` (safe re-registration on config hot-reload — no `E174` when
  your `BufWritePost` autocmd re-sources config), a `pcall`-wrapped callback
  reported through `lib.nvim.notify` instead of a raw traceback, and
  `opts.buffer = true`/bufnr for a buffer-local command.
- **A command with subcommands** (`:Verb sub1`, `:Verb sub2 arg`, flags,
  `<Tab>` completion at every level): `require("lib.nvim.usercmd.composer")`.
  This is **the single most depended-on piece of this whole library** — 30+
  consuming plugins build their `:Verb noun` surface on it instead of
  hand-rolling `:VerbNoun` commands and their own completion function. If
  you're about to write a second `nvim_create_user_command` for what is
  conceptually one verb with variants, stop and use composer instead — that
  is exactly the anti-pattern it exists to replace.
- **Never call `nvim_create_user_command` directly** in a plugin that
  depends on `lib.nvim` — you'd be reimplementing `usercmd.create`'s
  defensive callback and idempotent registration for no benefit.

```lua
local composer = require("lib.nvim.usercmd.composer")
composer.verb("MyPlugin", {
  routes = {
    { path = { "open" }, run = function(ctx) ... end },
    { path = { "close" }, run = function(ctx) ... end },
  },
})
```

Composer also generates your `docs/BINDINGS/Usercmds.md`-style docs straight
from the same route tree (`handle:document()`), so your command docs cannot
drift from the actual dispatch table the way hand-written command docs
eventually do.

## `lib.nvim.logger` vs. `lib.nvim.notify`: which one, when

`notify` is the right tool for a simple, immediate, user-facing message —
"saved 3 files," "no results found." One line, no history, no persistence.

`logger` is `notify`'s richer sibling: reach for it the moment you want
**any** of structured context per entry, an in-memory history you can
inspect later, a durable JSONL trail across a session for bug reports, or
crash-safe capture around a risky operation. In practice: give your plugin
one `logger` instance for its own diagnostics (`local log =
require("lib.nvim.logger").new({ name = "my-plugin" })`) and keep using
`notify` for the handful of messages actually meant for the user's eyes in
the moment — they compose, they don't compete.

```lua
local log = require("lib.nvim.logger").new({ name = "my-plugin" })
log.info("index built", { files = 412, took_ms = 38 })
M.risky_operation = log.wrap(M.risky_operation, "risky_operation")  -- swallow + log instead of crash
```

Inside an autocmd, LSP callback, or anything that might run in a fast-event
context, use `notify.safe.*` (or `notify.safe.create_safe(prefix)`) instead
of a bare `notify.create(...)` call — a direct `vim.notify` from a fast
event is a real source of the "works most of the time, mysteriously fails
under load" bug class.

## Cross-platform: what every plugin doing file/process work should know

If your plugin ever spawns a subprocess or touches a path outside the
buffer it's editing, read this section before writing your own platform
branch.

- **Never write your own `is_windows`/`uname` check.** `lib.nvim.cross.platform`
  already distinguishes WSL from native Linux correctly — a distinction
  hand-rolled detection gets wrong often enough to matter.
- **Never build your own `PATH`-completion or keyring workaround.** A
  subprocess inherits Neovim's own (often incomplete) environment, not an
  interactive shell's — `gh`/`glab`/`docker` and anything behind
  `nvm`/`pyenv`/`asdf` are the recurring victims. `cross.run.run`/
  `run_blocking` apply the fix (`cross.run.env.build()`) automatically; if
  you use the argv runners (`run_argv`, `uv.spawn_capture`/`spawn_stream`)
  instead, you must call `env.build()`/`env.apply()` yourself — it is *not*
  wired in there. This is the single most common thing a new consumer of
  `lib.nvim` forgets, because the shell-string runners make it invisible
  until you switch to an argv runner for a good reason (no shell
  interpolation) and lose the auto-wiring silently.
- **Opening a path or revealing it in a file manager are different
  actions** (`cross.open_default` vs. `cross.reveal_in_fm`) — don't reach
  for the older `fs.open.url.system_opener` for new code; `cross.open_default`
  is the more complete implementation (adds WSL `wslpath` translation).
- **File mutation on an untrusted/user-controlled path**: use
  `cross.fs.mutate` (delete/copy/rename/mkdir), not `os.remove`/`io.open`
  directly — it retries transient `EPERM`/`EACCES`/`EBUSY` errors (a file
  briefly locked by an indexer or AV scan) instead of failing on the first
  attempt.
- **Path separators**: `cross.fs.separators.*` are pure string transforms
  with no filesystem access — use them for comparing/normalizing path
  strings you don't intend to stat yet. Use `fs.normkey` when you need one
  canonical cache/dedup key for a path (resolves symlinks by default).

## Composing filesystem helpers: a realistic sequence

A plugin that needs "find the project root, cache a scan of it, and act on
the results" typically chains three separate `lib.nvim.fs.*` modules rather
than one do-everything function:

```lua
local find_root  = require("lib.nvim.fs.find_root")({ markers = { ".git" } })
local scan_cached = require("lib.nvim.fs.scan_cached")

local root  = find_root.find(vim.fn.expand("%:p"))
local files = scan_cached.scan(root, { kind = "files", ttl_seconds = 5 })
```

For a scan large enough to matter (a monorepo, `node_modules` not yet
ignored), prefer the `_async` counterpart (`scan_cached.scan_async`,
`collect_recursive.collect_async`) — the synchronous walkers block
Neovim's entire main loop (input, redraws) for the walk's duration, not
just your own code. The async versions are not a wall-clock speedup (they
walk one directory at a time, sequentially) — they exist purely so a large
scan doesn't freeze the editor while it runs.

## Building a UI: `ui.kit` vs. hand-rolled floats

Don't call `nvim_open_win` directly for a popup, hover panel, or prompt in a
plugin that already depends on `lib.nvim` — `lib.nvim.ui.kit` gives you a
themed, already-dismissable float for free, and keeps your plugin's popups
visually consistent with every other plugin in the same config that also
uses `ui.kit`. Reach for the plain `lib.nvim.window.make_scratch` +
`nice_quit` combo only when you specifically don't want kit's theming (a
raw content viewer with no chrome).

```lua
local kit = require("lib.nvim.ui.kit")
kit.popup({ type = "note", title = "Saved", message = "Wrote 3 files", timeout = 2000 })
kit.form({ fields = { { name = "name", label = "Name", required = true } },
           on_submit = function(values) end })
```

`kit`'s components are async (`on_submit`/`on_cancel` fire later); if your
call site is a synchronous chain that can't easily be recast to callback
style, `kit.sync(open_fn, opts)` bridges one call back to a plain return
value via `vim.wait()` — but never call it from a fast-event context, the
same restriction `vim.wait()` itself has.

## Soft dependencies and graceful degradation

Several modules explicitly probe for another plugin rather than requiring
it: `lib.nvim.progress`'s `style = "auto"` prefers `fidget.nvim` if it's
installed, falling back to `notify` otherwise; `lib.nvim.system.info`
prefers `fastfetch`, falls back to `neofetch`, falls back to a
platform-native probe. When you're building something similar in your own
plugin — an optional integration with another plugin that might not be
installed — this is the established pattern: probe, don't hard-require, and
degrade to the next-best option rather than erroring.

`lib.nvim.deps` is the dedicated module for the more general version of this
problem — an *external CLI tool* your plugin needs, not another Neovim
plugin. Declare your tool requirements in a `docs/INSTALL.md`/
`docs/install.json` your plugin ships, and call
`require("lib.nvim.deps").show_once("my-plugin")` once during setup — it
detects what's missing and offers a confirmation-gated install, never
running anything without an explicit user action.

## Gotchas worth knowing before you hit them

- **`cross.run`'s environment enrichment does not extend to argv runners.**
  Covered above, but worth repeating: this is the #1 real bug this
  ecosystem has hit migrating a plugin onto `lib.nvim` (see
  [guides/subprocess-env.md](guides/subprocess-env.md)'s "Adoption"
  section for the list of plugins still migrating, and why each one's
  argv-runner call sites need an explicit fix, not just a dependency bump).
- **`opts.buffer` and `opts.pattern` are mutually exclusive** in
  `lib.nvim.autocmd.create`, matching the underlying API — passing both
  routes to buffer-local scoping and silently ignores `pattern`, rather than
  merging them into a global `"*"` pattern. If your plugin exposes both as
  user-configurable, validate that only one is set.
- **A promoted composer route's `check` is only consulted if `run` actually
  resolves.** If you're using `run` as a lazily-required module path string
  and it's typo'd, `check()` never even runs — `handle:check()`/
  `composer.check_all()` report the resolution failure directly instead.
- **`window.nice_quit` only binds in normal mode, on purpose** — don't
  "fix" this by adding insert/terminal-mode bindings; it's what gives you
  the double-`<Esc>` behavior (leave insert, then close) for free without
  stealing Escape from an embedded terminal program.
- **`fs.mkdirp` is libuv-only, deliberately** — if you're calling directory
  creation from inside a uv timer, an `fs_event` callback, or a spawn
  callback (any fast-event context), `vim.fn.mkdir` aborts with `E5560`
  there; `fs.mkdirp` doesn't, because it never touches `vim.fn`.
- **`lib.nvim.selection` and `lib.nvim.buf_win_tab.selection` are not the
  same module** — the former *restores* a Visual selection after your
  mapping mutates the buffer, the latter only *reads* the current/last
  selection. Reaching for the wrong one is an easy mixup given the similar
  names.

## Where to look next

- [docs/FEATURES/](FEATURES/README.md) — problem → solution write-ups for
  the cross-cutting capabilities referenced above, organized by theme.
- [docs/API/](API/README.md) — full function-signature index, if you need
  exact parameter shapes rather than narrative usage.
- [docs/modules.md](modules.md) — the flat namespace index with links to
  every module's own `README.md`.
- [templates/README.md](../templates/README.md) — copy-paste patterns for
  resolving `lib.nvim` inside your own plugin's headless test suite.
