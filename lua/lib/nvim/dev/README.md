# `lib.nvim.dev`

Tooling for whoever is developing *across* the plugin ecosystem lib.nvim sits
under, not for a single plugin's own runtime. Occupants: `duplicates.lua`,
`reload.lua`, `notify_scan.lua`, `deprecations/`.

## `reload.lua` — reload a config module on save

```lua
require("lib.nvim.dev.reload").watch()
```

One line in **your own config's** startup, not in a plugin: registers a
`BufWritePost` autocmd that reloads whatever module under
`stdpath("config")/lua` you just saved (`package.loaded[name] = nil`,
`require(name)` again) — matched lazily per save, not by pre-globbing every
`*.lua` file at startup. `M.module(name)` is the reload alone, if you already
have your own autocmd wiring.

## `duplicates.lua` — cross-repo function duplication

Identical function bodies across sibling repos — candidates for extraction
into lib.nvim itself, not a general clone-detector. Promoted from a
throwaway `python duplicate_functions.py` that walked a hardcoded path;
this is the same detection (normalize each top-level function body, group by
the normalized text, keep groups spanning two or more different repos),
parameterized by a root directory instead.

```lua
local duplicates = require("lib.nvim.dev.duplicates")

duplicates.scan("E:/repos")   -- default: cwd
duplicates.lines("E:/repos")  -- the same, as printable lines
```

**Scope: `root`'s immediate subdirectories, not `root` itself.** A hit only
means something when the *same* body shows up in *two different repos*, so
point this at a directory holding several sibling checkouts — `root`'s own
`lua/` (if it has one) is never itself scanned as a repo. Pointing it at a
single plugin's own root, with no sibling checkouts underneath, correctly
finds nothing: there is no second repo to duplicate against.

lib.nvim's own directory is always excluded from the repo set — the question
this answers is "what should move INTO lib.nvim", so lib.nvim's own code is
never itself a candidate.

`duplicates.create_usercmd()` registers `:LibDuplicateScan [path]`. Put that
one line in **your own config**, not in a plugin. `path` is optional and
defaults to cwd — run it from the directory that holds your sibling repos.

```lua
require("lib.nvim.dev.duplicates").create_usercmd()
```

## `notify_scan.lua` — where do sibling repos emit user messages?

Scans every immediate subdirectory of a root for `vim.notify`, `nvim_echo`,
`nvim_err_write(ln)`, `:echoerr`/`:echomsg`, `print(` and `lib.nvim.notify`
usage — the worklist for moving repos onto
[`lib.nvim.notify.popup`](../notify/README.md). Per finding: kind, level (when
spelled out), literal head, and two migration flags: `dynamic` (a wrapper —
converting it converts every caller) and `bound` (`local notify = vim.notify`
at load, which bypasses hooks installed later).

```lua
local scan = require("lib.nvim.dev.notify_scan")
scan.scan("B:/repos")      -- Finding[]
scan.summarize(findings)   -- per-repo totals
scan.lines("B:/repos")     -- Markdown: summary table + findings per repo
```

`notify_scan.create_usercmd()` registers `:LibNotifyScan [path]` (call it from
your own config). A line scanner, not a parser: it skips `TESTS/`, `.deps/`,
`lib.nvim` and `ui.nvim`, and counts `lib.nvim.notify` *creation* sites, not
each `notifier.info(...)` call.

## `deprecations/` — deprecated Neovim calls, on save and in `:checkhealth`

```lua
require("lib.nvim.dev.deprecations").watch()   -- in your own config
```

`watch()` registers one `BufWritePost` autocmd (pattern `*.lua`): after a save
it scans the buffer and, only if it still holds deprecated calls, warns once
with the locations — `12:5 vim.loop -> vim.uv (deprecated since 0.10)`. A
clean save is silent. `opts.on_findings(findings, buf)` replaces the warning
(quickfix, diagnostics, ...); `unwatch()` removes it. Nothing runs at startup
beyond creating that autocmd; the rule table loads on the first scan.

`:checkhealth lib` has a **deprecated API calls** section scanning
`stdpath("config")`. A plugin can report on its own tree from its
`health.lua`:

```lua
require("lib.nvim.dev.deprecations").health({ plugin_root }, { title = "myplugin: deprecated calls" })
```

The rest of the surface: `scan_lines(lines)`, `scan_buffer(buf)`,
`scan_file(path)`, `scan_roots(roots)` (skips dot-directories such as `.git/`
or `.claude/worktrees/`, `node_modules/` and `---@meta` annotation files,
never follows a symlink, stops at `max_files`), `format(f)`,
`active_rules()`. `opts.rules` replaces the default table
([`rules.lua`](deprecations/rules.lua): `vim.loop`, `nvim_buf_set_option` and
the other option getters/setters, `vim.highlight`, `vim.tbl_flatten`,
`vim.lsp.get_active_clients`, `termopen`, `nvim_buf_add_highlight`,
`vim.diagnostic.goto_next`, ...), `opts.extra_rules` adds to it. A rule only
applies on a Neovim at least as new as its `since`, because on an older one
the replacement may not exist.

A line scanner, not a parser: comments and string contents are blanked
before matching, with open long strings / block comments carried across
lines, so a name inside a string or comment is not reported. A call built at
runtime is not seen. `---@diagnostic disable-next-line: deprecated` (or
`disable-line: deprecated`) silences a line — the marker LuaLS honours, so a
deliberate fallback for older Neovim is waived once for both.

**Why here and not in migrate.nvim or a mini plugin:** migrate.nvim rewrites
calls and deliberately has no watcher; the watcher is a dependency-free
scanner plus a few lines of autocmd and health wiring, and every config and
plugin already has lib.nvim on the runtime path — a separate plugin would add
an install step for the same code.
