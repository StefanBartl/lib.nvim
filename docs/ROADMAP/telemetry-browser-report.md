# `lib.nvim.telemetry` — report renderers, and a browser report via mdview.nvim

> **Status:** concept, not implemented. Written in response to: "prüfe eine
> Implementation von mdview.nvim, also quasi dass der Report gleich mit
> mdview.nvim im Browser angezeigt wird — das einfach als `:LibTelemetry show
> mdview` oder irgendwie so".
>
> **Verdict: worth doing, and cheaper than it looks** — but the valuable half
> is the *Markdown renderer*, not the mdview bridge. The bridge is ~20 lines
> on top of it, because `:MDView standalone` already does exactly the right
> thing. Everything below was checked against mdview.nvim's actual source.

## The split that makes this cheap

Two separable things, and conflating them is what would make this expensive:

1. **Render a report as Markdown.** Useful on its own — paste into an issue,
   commit a snapshot, diff two weeks, feed any Markdown renderer. No
   dependency on anything.
2. **Hand that Markdown to a browser.** One plugin-specific bridge, optional,
   soft-dependency.

Today `report.lua` has exactly one renderer: `M.lines(report)` → fixed-width
terminal text with box-drawing indentation, built for `kit.viewer`. It is not
reusable as Markdown (the `└`/`ⓘ` prefixes and column padding are terminal
artifacts), and `:LibTelemetry export` writes raw JSON, which is a data format,
not a readable one.

So step 1 is a second renderer next to `M.lines`, not a rewrite of it.

## Step 1 — `report.markdown(report)`

```lua
t.markdown({ since = "7d", top = 30 })   -- -> string[]
telemetry.markdown_all(opts)             -- every instance, one document
```

Output shape — deliberately a table, because the interesting operation on a
report is *sorting and scanning*, which a table does and a nested list does
not:

```markdown
# lib.nvim — telemetry

**running** · counting · 282 wrapped · 48 210 calls · 12 sessions · last 7d
Collecting since 2026-07-25 09:14.

| Function | Calls | Ø ms | Errors |
| --- | ---: | ---: | ---: |
| `fs.find_root` | 12 480 | 0.42 | — |
| `strings.trim` | 8 021 | — | — |

### `fs.find_root` — argument profile

| Share | Argument |
| ---: | --- |
| 91 % | `("/repo/lib.nvim")` |
| 6 % | `("/repo/mdview.nvim")` |
| 3 % | `<other: 47 distinct>` |

> **91 % of calls share one argument** — candidate for memoization
> (`lib.lua.memo.memo` / `.lru`).
```

Argument-profile subsections only appear for functions that actually have a
profile, so a counting-only instance (the default, and what the nvim config
uses) renders as one clean table and nothing else.

`M.lines` and `M.markdown` must both build from the same `M.build()` result —
that is already how `lines` works, so this is additive. Neither may re-derive
numbers.

## Step 2 — the mdview bridge

**mdview.nvim already solved the hard part**, and not the part I expected.
`:MDView standalone` (`lua/mdview/bindings/usrcmds/standalone.lua`) hands a
**file path** to the relay binary's own `--watch` mode and steps out of the
chain entirely: the relay watches the file on disk and broadcasts changes to
the browser itself.

Its documented trade-offs are *exactly the ones a generated report does not
care about*:

| standalone's trade-off | Effect on a telemetry report |
| --- | --- |
| previews the file **as saved** — no unsaved-buffer push | We write the file. It is always "saved". |
| no scroll sync | A report is not being edited. |
| no cursor marker | Same. |
| outlives `:qa`, costs one small process | **A feature here**, not a cost. |

Compare `M.open()` (the live path), which needs `state.is_attached()`, a
running server session, and a buffer whose `nvim_buf_get_name()` is a real
path. Routing a report through that would mean opening a scratch-ish buffer,
giving it a fake path, and seeding a room — all to get something standalone
mode gives for free.

So the bridge is:

```lua
-- lua/lib/nvim/telemetry/renderers/mdview.lua
local path = vim.fn.stdpath("cache") .. "/lib.nvim/telemetry/report.md"
-- write report.markdown(...) to `path`
vim.cmd(("MDView standalone %s"):format(vim.fn.fnameescape(path)))
```

### The property that makes this better than a static export

The relay **watches** the file. Telemetry **already** rewrites its state on a
debounced periodic flush (`flush_interval_ms`, default 60 s) and on
`VimLeavePre`. Wire the report write into that same flush and the browser tab
becomes a **live dashboard that updates itself** — counts climbing while you
work — with no new machinery on either side. Neither plugin gains a poller,
a socket, or a timer it did not already have.

That is the actual argument for doing this at all. A one-shot "render the
report to HTML" is barely better than the kit float; a self-updating browser
tab is a different thing.

Opt-in, obviously — writing a Markdown file every 60 s for someone who never
opened a browser is waste:

```lua
telemetry.new({ namespace = "lib.nvim", report_file = true })
```

## Command surface

The user's suggested `:LibTelemetry show mdview` does not survive contact with
the existing grammar. Second token is already **the namespace**
(`:LibTelemetry stop markdown.nvim`, `:LibTelemetry report lsp.nvim`), and
`mdview` sitting in that slot is ambiguous with the real `mdview.nvim`
namespace. Proposed instead:

```vim
:LibTelemetry open            " render + open in the browser, all instances
:LibTelemetry open lsp.nvim   " one namespace
```

`open` reads as "open this somewhere external", which is what distinguishes it
from `report` (in-editor float). It keeps the one-namespace-per-second-token
rule intact, so completion needs no special case.

**Which renderer `open` uses is configuration, not a subcommand** — the exact
shape `lib.nvim.progress` already uses (`progress_style = "notify" |
"statusline" | "fidget" | "float" | "kit"`, resolved by
`progress/styles/resolve_style.lua`, which only picks `fidget` once fidget is
confirmed loadable):

```lua
require("lib.nvim.telemetry").setup({
  report_style = "auto",   -- "auto" | "kit" | "mdview" | "file"
})
```

`"auto"` = mdview if loadable, else the kit float. Same
`pcall(require, ...)`-then-degrade discipline `progress/styles/fidget.lua`
documents: an external plugin's surface is not stability-guaranteed, so a
broken or incompatible version must fall back, never error out of the caller.

## Why this belongs in lib.nvim rather than mdview.nvim

Direction of dependency. mdview.nvim already **hard-depends** on lib.nvim (its
`init.lua` probes for it and errors with an actionable line if missing). A
`telemetry` feature living in mdview would be a plugin reaching back into its
own dependency's internals; a `mdview` renderer living in lib.nvim is the
`fidget` pattern, which this repo already ships and has already reasoned
through.

lib.nvim must not gain a hard dependency on mdview — hence `pcall`, hence
`"auto"` degrading silently.

## Honest limits

- **The browser shows the last flush, not this instant.** Bounded by
  `flush_interval_ms`. `:LibTelemetry open` should force a flush first so the
  initial render is current; after that it is as live as the flush interval.
- **`:MDView standalone` needs the relay binary** (v0.3.0+, `--watch`
  support — standalone.lua probes for it). Missing or too old ⇒ fall back to
  the kit float, do not fail.
- **One report file per namespace, or one combined?** Leaning one combined
  `report.md` plus per-namespace files on demand — a browser tab per plugin is
  not obviously wanted, and the relay watches one path per invocation.
- **No HTML of our own.** Markdown out, mdview renders. Generating HTML here
  would duplicate mdview's themes/highlighter and immediately drift from them.

## Phases

1. **`report.markdown()`** + `:LibTelemetry export --format=md` (or a second
   `export_markdown`). Standalone value, no dependencies, testable in the
   existing spec. This is the phase worth doing even if the rest never lands.
2. **`report_file = true`** — write the Markdown at flush time.
3. **`renderers/mdview.lua` + `:LibTelemetry open` + `report_style`.** The
   thin part.
