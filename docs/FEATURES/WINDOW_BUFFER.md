# Windows, buffers & selection

Small, focused, individually-testable helpers for overlay/floating windows,
buffer/window metadata, and Visual-selection handling — the boilerplate every
plugin that builds a hover popup, a picker, or a debug panel otherwise
rewrites from scratch.

## Scratch-buffer floats in one call

Creates an unlisted, `nofile`/`bufhidden=wipe` scratch buffer inside a
centered floating window and returns both handles in one call, instead of
the usual four-or-five-line boilerplate (`nvim_create_buf` +
`nvim_open_win` + option setting + content + lock).

- **Module:** `lib.nvim.window` (`make_scratch`)
- **Config:** `opts.lines`, `width`/`height` (derived from content by
  default), `relative`, `row`/`col` (centered by default), `border`
  (default `"rounded"`), `title`, `nice_quit`, `filetype`, `modifiable`
  (default `false`), `wo`/`bo` overrides

```lua
local winid, bufnr = window.make_scratch({
  lines = { "Line 1", "Line 2" }, title = "Hover", nice_quit = true,
})
```

## Close-on-key and close-on-focus-lost

Two independent, composable dismiss patterns for a transient window: an
explicit keybind, and an automatic close the instant focus leaves it.

- **Module:** `lib.nvim.window` (`nice_quit`, `close_on_focus_lost`)

`nice_quit(winid)` binds `q`/`<Esc>` buffer-local, **normal mode only** — the
first `<Esc>` leaves insert/terminal mode (Vim default) and the second, now
in normal mode, closes the window, so a TUI program embedded in a terminal
buffer (fzf, lazygit) still receives its own Escape. The tabpage's last
window is never closed. `close_on_focus_lost(winid)` registers a one-shot
autocmd (`WinLeave`/`BufLeave` by default) and returns the augroup id for
manual cancellation.

## Float title and re-centering

- **Module:** `lib.nvim.window` (`set_title`, `center`)

`set_title(winid, title, opts?)` sets or clears (`nil`) a floating window's
title — a safe no-op on non-floats, and only visible when the float has a
border. `center(winid)` re-centers an existing float from the current
width/height and editor size.

## Named vs. one-shot scratch splits

Two related but distinct scratch-split constructors for different UX
patterns: a de-duplicated named split for a persistent panel, and a fresh
split every call for report-style output that should never silently
overwrite a previous run.

- **Module:** `lib.nvim.window` (`open_named_scratch`, `open_scratch_split`)

```lua
window.open_named_scratch("my-plugin://log", lines)   -- find-or-replace by name
window.open_scratch_split(report_lines, { filetype = "my-plugin-report" })  -- always a new window
```

## Window tagging

Find a window later without maintaining your own registry (a hand-rolled
registry can go stale the moment a window closes through a path you never
observed).

- **Module:** `lib.nvim.window` (`tag.set`, `tag.get`, `tag.find`)

```lua
window.tag.set(winid, "my-plugin://report")
local found = window.tag.find("my-plugin://report")  -- nil if closed
```

Uses the same `vim.w[win].custom_tag` convention as
`lib.nvim.buf_win_tab.capture`'s `tag` option, so a window tagged by either
side can be found by the other.

## Bound window handle (`attach`)

- **Module:** `lib.nvim.window` (`attach`)

```lua
local w = window.attach(winid)
w.nice_quit(); w.set_title("New title"); w.center()
```

Pure sugar: every method delegates to the matching free function with
`winid` pre-bound. The free functions remain the single source of truth.

## Cached window/buffer context

Two mirrored accessors — one per window, one per buffer — that answer "what
is this window/buffer actually doing right now" in one call instead of five
separate `nvim_*` lookups, cached so repeated reads in the same event are
cheap.

- **Module:** `lib.nvim.window.context` (`get`, `invalidate`,
  `clear_cache`, `get_stats`), `lib.nvim.buffer.context` (`get`,
  `invalidate`, `clear_all`, `get_stats`)

`window.context.get(winid)` returns `{ winid, is_valid, bufnr, cursor,
topline, botline, width, height, is_cursor_in_range(...),
get_visible_lines() }`. `buffer.context.get(bufnr)` returns `{ bufnr,
is_valid, name, filetype, buftype, modifiable, modified, tick, line_count,
size_bytes, lines (lazy), is_normal(), has_filetype(ft) }`, keyed and
auto-invalidated by `changedtick` with weak-keyed, auto-GC'd entries.

## Visual-selection reselection after a mutation

Neovim drops the Visual selection the instant a mapped function returns —
this restores it, so a mapping that reformats or moves the selected text
doesn't leave the cursor in normal mode with the selection gone.

- **Module:** `lib.nvim.selection` (`lines`, `reselect_lines`,
  `keep_lines`, `chars`, `reselect_chars`, `keep_chars`)

```lua
require("lib.nvim.selection").keep_lines(function(srow, erow)
  -- mutate lines srow..erow
end)  -- selection is restored afterward
```

Distinct from `lib.nvim.buf_win_tab.selection`, which only *reads* the
current/most-recent selection without restoring anything.

## Buffer/window/tab inspection utilities

A grab-bag of read-only inspection helpers for buffers, windows, and
tabpages — buffer counting/listing, tab formatting, aggregated state
reports — useful for a status line, a debug panel, or a `:checkhealth`
section.

- **Module:** `lib.nvim.buf_win_tab.buffer_utils`,
  `lib.nvim.buf_win_tab.tabs_utils`, `lib.nvim.buf_win_tab.windows_utils`

```lua
require("lib.nvim.buf_win_tab.windows_utils").show_aggregated_state()
```

## Deterministic Ex-command capture

Detects exactly which buffers/windows an arbitrary Ex command created, via
delta detection plus optional polling — for a plugin that needs to know
"what did `:command` just open" without that command exposing its own hook.

- **Module:** `lib.nvim.buf_win_tab.capture` (`capture`)

```lua
local result = require("lib.nvim.buf_win_tab.capture").capture(":Git blame")
-- result.wins, result.bufs
```

Synchronous when called without a callback (blocks until timeout); async
with one, returning immediately and calling back later.

## Word-under-cursor and visual-selection extraction

- **Module:** `lib.nvim.buf_win_tab.word_under_cursor`,
  `lib.nvim.buf_win_tab.selection` (`get_visual_selection`,
  `reselect_visual`)

`word_under_cursor()` returns `{ word, start_col, end_col, row }` with a
configurable word-character pattern (default `"[%w_']"`); `end_col` is
0-based exclusive so it slices directly. `selection.get_visual_selection()`
reads the current or most-recently-active Visual range whether or not
Visual mode is still active.

## Quickfix and location lists

Hands a plugin's already-collected entries to Vim's quickfix/location list
with a title, in one call — the mechanical "show the user what I found"
step, not the entry-building itself, which stays with the caller.

- **Module:** `lib.nvim.ui.list` (`set`, `qf`, `loc`)
- **Config:** `opts.action` (default `" "` pushes a new list; `"r"`
  replaces; `"a"` appends), `opts.open` (default `true`; `"auto"` opens
  only when non-empty), `opts.focus` (default `"list"`; `"source"` hands
  the cursor back)

Deliberately does not wrap `vim.diagnostic.setqflist`/`setloclist` — those
have their own severity handling and a version-dependent signature.

## Statusline segment

A short status badge pinned to one row of one window, auto-choosing between
a window-local `&statusline` and a floating overlay depending on whether
`laststatus` is global (`>= 3`).

- **Module:** `lib.nvim.ui.statusline` (`attach`, `is_global`,
  `resolve_mode`)

```lua
local segment = require("lib.nvim.ui.statusline").attach(winid, { mode = "auto" })
segment.set("-- INSERT --", "ModeMsg")
segment.clear()
```

## Idempotent highlight-group definition

Wraps `nvim_set_hl` so re-running setup (config hot-reload, colorscheme
change) never redefines a group inconsistently, with optional namespace
scoping.

- **Module:** `lib.nvim.ui.hl` (`namespace`, `set`)

## Terminal-buffer helpers

- **Module:** `lib.nvim.terminal` (`escape`, `is_terminal_buf`,
  `delete_terminal_buf`, `is_kitty`)

Narrow shell-escaping for building terminal commands, terminal-buffer
detection and forced cleanup, and Kitty-terminal detection for
Kitty-specific integrations (image protocol, remote control).

## Buffer-content helpers

- **Module:** `lib.nvim.buffer.*` — `insert_lines`, `get_alternate`,
  `is_markdown_buf`, `open_background`, each its own leaf module.

**CDX:** there is no `buffer/init.lua` aggregator, so `require("lib.nvim.buffer")`
alone does not resolve — require the leaf path directly (e.g.
`require("lib.nvim.buffer.insert_lines")`), or go through `require("lib")`,
which flattens these functions directly (`lib.insert_lines`,
`lib.is_markdown_buf`, `lib.buffer_context`). Same stale-aggregator shape
already flagged on `Lib.Buffer`/`Lib.Buffer.ALL` in
`lua/lib/nvim/buffer/@types/init.lua`.

`insert_lines(lines, pos?)` inserts at the buffer start, the cursor row, or
an explicit `{row, col}` (0-based). `open_background(path)` adds a file to
the buffer list without creating or focusing a window — for prefetching or
background indexing.
