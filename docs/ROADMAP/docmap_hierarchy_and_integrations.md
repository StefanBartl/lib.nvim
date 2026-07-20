# docmap: hierarchy tab, LuaLS type graph, `install()`, and mdview.nvim

> **Status:** concept, not implemented. Sequel to
> [`module_map.md`](module_map.md), which shipped as `lib.nvim.docmap`. That
> concept intentionally deferred two things as "planned enrichment, not
> built": LuaLS `--doc` merging, and any interactive diagram beyond the
> collapsible tree. Both are now asked for directly, plus a third thing that
> wasn't scoped at all — a live, in-editor consumer via `mdview.nvim` — so this
> is a full plan for all three rather than a patch to the old one.
>
> Everything below was checked against the actual source of both repos
> (`lib.nvim` on `feat/docmap`, `mdview.nvim` at `C:/repos/mdview.nvim`), not
> assumed. Where I could not verify something without deeper cross-repo
> tracing, it's called out as an open question rather than asserted.

## The three asks, and how they depend on each other

1. **`lib.docmap.install()` / `.uninstall()`** — a programmatic entry point
   that sets everything up "as objects in the source code": not just a
   `:LibMap` command, but a live, in-memory IR other Lua code can read and
   react to, built with the full annotation surface (EmmyLua/LuaCATS classes,
   fields, aliases via LuaLS), not just the header prose the scanner reads
   today.
2. **A new Hierarchy tab** in the generated HTML — `<div>`-based node boxes
   plus connector lines drawn between them, built from type annotations, as a
   second view alongside the existing collapsible tree.
3. **mdview.nvim integration** — a specialized rendering of the module map
   inside mdview's live browser preview, not just "open `overview.md` as a
   plain markdown file."

These aren't independent. (2) needs relationship data that (1)'s annotation
merge produces; (3)'s most useful form is "push the live IR from (1) into an
open mdview session whenever it changes." The plan below is written as four
parts with an explicit dependency order at the end, because building them in
ask-order would mean building the tab before the data it needs to be
interesting exists.

## Part 1 — LuaLS enrichment (the shared prerequisite)

### What's there today

Verified against `feat/docmap`: the IR (`Lib.Docmap.Node`) carries `module`,
`summary`, `body`, `readme`, `types` (file paths), `export` — header prose and
filesystem facts. Nothing about `@class`/`@field`/`@alias` content. `scan.lua`
and `check.lua` never shell out to `lua-language-server`; the "Phase 3" from
the original concept was never built. So today there is no data anywhere in
docmap that says "`Lib.Docmap.Node` has a field `parent` of type
`Lib.Docmap.Node?`" — only "this module has a `@types/init.lua` file."

This was already prototyped once, in the original concept's research: running

```
lua-language-server --doc=<path> --doc_out_path=<dir>
```

against `lua/lib/nvim/fs` produced 232 structured entries — `type` records
with `name`, `desc`, `fields[].{name, desc, extends.view}`, and
`defines[].{file, start}` pointing back at the exact source line. That JSON is
the data source for both (1)'s "full annotation surface" and (2)'s
relationship edges.

### Design

New module `lua/lib/nvim/docmap/luals.lua`:

- `available() -> boolean` — `vim.fn.executable("lua-language-server") == 1`.
- `run(root, source) -> table?` — invokes `--doc`, reads `doc.json` from a
  temp dir, returns the parsed table (or `nil` + a reason on failure — missing
  binary, timeout, malformed output). Should use `cross.uv.spawn_capture`
  (already async, argv-safe) rather than a blocking call, since a full-repo
  `--doc` run is not instant.
- `merge(ir, doc_json)` — for every `type` entry, match `defines[].file`
  against the `types` paths already recorded on IR nodes, and attach the
  parsed class/fields to that node as `node.types_detail` (new IR field,
  `nil` when LuaLS didn't run — the map already promised graceful degradation
  without `lua-language-server` on `PATH`, and this keeps that promise).
- **Edge extraction**, which is the part that actually feeds the Hierarchy
  tab: for every `@field name SomeType` where `SomeType` (after stripping
  `?`/`[]`/generics) matches another class name present in the same
  `doc.json`, record a directed edge `{ from = node_id, to = target_node_id,
  via = field_name }`. This is the graph "so kann man tree bauen" cashes out
  to concretely: not just "this class has fields" but "this class points at
  that class."

### Cost, and why it must be opt-in

A `--doc` run over ~250 files is not free — the earlier prototype took a
couple of seconds over a subtree of 267 entries; a full-repo run will be
slower. `:LibMap` should stay fast by default. Proposed gate:
`opts.luals = false` by default; `:LibMap full` (new subcommand alongside the
existing `check`/`open`) or `opts.luals = true` (for CI / `install()` with
`watch = true`, see Part 3) opts in. Cache `doc.json` by source-tree mtime so
a rescan without file changes skips the shell-out entirely.

## Part 2 — the Hierarchy tab

This is the most self-contained of the four parts and the one to build
first: a first version needs nothing from Part 1 at all.

### Current state

Verified against `render/html.lua` on `feat/docmap`: the page is a single
`<main>` two-pane CSS grid (`#tree`, `#detail`) with **no tab bar** — the
"new tab" is not an extension of an existing tab system, it's the first one.
Everything is vanilla JS/CSS in one file (no framework, per the
self-contained-artifact constraint this file was already built under), so the
tab bar itself is small: two buttons, a `.pane` show/hide toggle.

### Node boxes and connectors

- **Boxes**: reuse the existing `.row` visual language (kind-colored name,
  summary, badges) but as a `<div class="hnode">` positioned by a layout pass
  rather than nested indentation.
- **Layout**: a simple **layered layout** is enough for a first version —
  `node.depth` (already on every IR node) assigns each node to a layer, boxes
  within a layer are spaced evenly. This is a well-known ~50-line algorithm,
  not a full Sugiyama/dagre port. Good enough for a directory tree; revisit
  only if the type-relationship edges from Part 1 turn out to need something
  smarter (a field reference can point to a class anywhere in the tree, not
  just a parent/child, which a pure layered-by-depth layout draws as long
  diagonal lines — acceptable for a first cut, ugly at scale).
- **Connectors**: an absolutely-positioned `<svg>` overlay sized to the
  container. Box positions come from `getBoundingClientRect()` on each
  `.hnode`, recomputed on window resize **and** on tab-show (a box inside a
  `display:none` pane cannot be measured, so switching to the Hierarchy tab
  must trigger a re-layout, not just a repaint). Parent/child edges (solid)
  come free from `node.children`; Part 1's type-reference edges (dashed, once
  merged) are a second edge set layered on top of the same SVG.

### Scale

The real tree is 120+ modules, depth 1–6. A layered layout over the *whole*
map at once will be very wide. Two options, and this is a call for you to
make rather than one I've made for you:

- Horizontal scroll (the CSS already has an `overflow-x:auto` `.wrap`
  pattern used for the findings table — same trick applies).
- Scope the diagram to **one selected subtree at a time** — click a namespace
  in the Tree tab, the Hierarchy tab draws just that subtree. Mirrors how the
  detail pane already works (one node at a time) and keeps the SVG small
  enough to read. My inclination is this option; a 250-node force-directed or
  fully laid-out graph is rarely readable regardless of the rendering
  technique, and the existing tree+detail split already established
  "drill into one thing at a time" as this map's interaction model.

### First cut vs. second cut

The layered layout and connector SVG work off `node.children` alone — no
LuaLS, no Part 1. Ship that first: directory-hierarchy boxes and solid
connectors, immediately useful, and it validates the box+connector rendering
approach before anything else (including a possible mdview Tier B, see Part
4) tries to reuse it. Dashed type-reference edges are a second cut, layered
on top once Part 1's `merge()` exists.

## Part 3 — `lib.docmap.install()` / `.uninstall()`

### What's there today

`docmap.command.setup()` registers `:LibMap` and nothing else — there is no
persistent in-memory IR. Every `:LibMap` invocation rescans from scratch and
the result lives only for the duration of that command; another plugin's Lua
code has no way to reach it except by reading `module_map.json` off disk and
parsing it itself.

### Design

```lua
local handle = require("lib.nvim.docmap").install({
  root = "...", source = "lua/lib", title = "lib.nvim",
  watch = true,   -- rescan on BufWritePost under source/**.lua, debounced
  luals = false,  -- Part 1 enrichment; off by default, see cost note above
})

handle.ir()               -- current Lib.Docmap.IR, in memory
handle.node(id)            -- single node lookup
handle.on_change(function(ir) ... end)  -- returns an unsubscribe fn
handle.uninstall()          -- or: require("lib.nvim.docmap").uninstall(handle)
```

- `install()` runs an initial scan, stores IR + findings in a module-local
  registry keyed by `root` (so lib.nvim's own map and a consuming plugin's map
  don't collide), and registers `:LibMap` by delegating to the existing
  `command.lua` — `:LibMap`'s behavior for lib.nvim itself does not change,
  since `command.setup()` becomes a thin `install({ watch = false })` call.
- `watch = true` attaches a debounced `BufWritePost` autocmd
  (`lib.nvim.debounce`, already exists — no new primitive needed) over
  `source/**.lua`, so the in-memory IR updates itself as files change instead
  of requiring a manual `:LibMap`. This is what "als Objekte im source code
  eingerichtet werden kann" cashes out to: the tree is a live object with
  subscribers, not a static file.
- `uninstall()` removes the `:LibMap` command, clears the autocmd group, drops
  the IR from the registry. Idempotent by design — calling it twice, or on an
  already-torn-down handle, is a no-op with a warning rather than an error,
  because this repo's own `usercmd.create` already defaults `force = true`
  specifically for hot-reload configs that re-run `setup()` repeatedly
  (NvChad-style `BufWritePost` re-source), and `install/uninstall` needs the
  same tolerance.

## Part 4 — mdview.nvim integration

Split into two tiers by whose repository the work actually belongs to. This
split is the main finding of the investigation, not a hedge: **Tier A is real
and buildable entirely from lib.nvim's side today; Tier B requires a change to
mdview.nvim's client that does not exist and should not be designed twice.**

### What I verified in `mdview.nvim`

- It already **hard-depends on lib.nvim** — `init.lua` probes
  `require("lib.nvim.cross.platform.is_windows")` at load and errors with an
  actionable message if it's missing. Requiring `lib.nvim.docmap` from
  mdview.nvim costs nothing dependency-wise; the direction (mdview depends on
  lib, not the reverse) is already established and should stay that way.
- The rendering pipeline is exactly one thing: `comrak::markdown_to_html`
  piped through `ammonia::Builder::default()` (confirmed by reading
  `native/wasm-render/src/lib.rs`). The only additions beyond ammonia's stock
  allowlist are the `<input type=checkbox>` tag (for GFM task lists) and the
  `data-sourcepos` attribute (for scroll-sync). There is **no Mermaid support,
  no diagram engine, no alternate render mode** anywhere in `src/client` —
  grepped for it, found nothing. Whatever gets sent is markdown, gets
  sanitized as markdown, and is displayed as the resulting HTML. There is also
  no `kind`/`type` discriminator on the wire protocol — every message is
  implicitly "markdown content for room X."
- There *is* a usable integration seam without touching mdview at all:
  `ws_client.send_markdown(path, markdown, opts)` pushes arbitrary markdown
  into a room keyed by any string, independent of whether a real buffer with
  that path exists. `live_push.lua`'s normal path always routes through a real
  buffer, but `send_markdown` itself has no such requirement.

### Tier A — buildable now, zero mdview.nvim changes

A new renderer, `lua/lib/nvim/docmap/render/mdview.lua`, producing markdown
shaped for what ammonia's *default* builder actually keeps: `<details>` /
`<summary>` per top-level namespace (both are standard tags in ammonia's
default allowlist), GFM tables for the module list (already how `overview.md`
renders modules today), inline `` `code` `` for paths. Explicitly **not**
using custom CSS classes or `style` attributes for anything — ammonia is
deliberately conservative about attributes beyond tag names, and mdview only
extended the generic-attribute allowlist with `data-sourcepos`, nothing else.
Badges/severity need to be conveyed through text/emoji, not `class="error"`.
This needs a final check against ammonia's actual attribute allowlist before
relying on it (see open questions) — the tag-level allowance I did confirm
from `Builder::default()`, the attribute-level one I reasoned from the code
being conservative rather than reading ammonia's own source.

Wiring: `install()`'s `on_change` hook (Part 3) calls, guarded by
`pcall(require, "mdview.core.state")`, `state.is_attached()` — and if an
mdview session is running, pushes the freshly generated markdown via
`ws_client.send_markdown("docmap://" .. root, markdown)`. Editing lib.nvim's
own source with an mdview preview open on that synthetic room then live-
updates the rendered module map. Entirely optional, entirely one-directional
(lib.nvim never requires mdview), and it's a genuinely "specialized" render —
distinct from generically opening `overview.md` as a file — because the
generator can tailor the markdown to mdview's sanitizer instead of to GitHub's
renderer, which is what `overview.md` is already tuned for.

### Tier B — real diagram inside mdview's own preview, not scoped here

A box+connector hierarchy *rendered inside mdview's browser tab* needs a
client-side render mode that does not exist: mdview's entire pipeline is
markdown-in, sanitized-HTML-out, with nothing that draws from structured JSON.
Getting there needs, on mdview's side: a `kind` field on the WS protocol (today
implicit and singular), and a client branch that skips comrak/ammonia
entirely for a `kind = "structured"` payload — which could be exactly
docmap's own `module_map.json`, already schema-stable.

Recommendation: don't design this twice. Build Part 2's Hierarchy tab first,
validate the layered-layout + SVG-connector approach there, and only then
write a concept doc *in mdview.nvim's own repo* proposing the client-side
reuse of that same rendering code. Out of scope for this document and for
`lib.nvim`.

## Recommended build order

Dependency-driven, not ask-order:

1. **Hierarchy tab, directory edges only** (Part 2, first cut) — no
   prerequisites, immediately useful, and it's the piece a future mdview
   Tier B would want to borrow from, so validating it first de-risks that
   later write-up too.
2. **LuaLS enrichment** (Part 1) — unlocks type-relationship edges, and is
   the concrete meaning behind "mit allen Annotationen... so kann man tree
   bauen."
3. **Hierarchy tab, type edges layered on top** (Part 2, second cut) — dashed
   edges from step 2's data.
4. **`install()` / `uninstall()`** (Part 3) — most valuable once there's a
   reason to react to live changes (an open Hierarchy tab, or a pushed mdview
   preview); building it earlier would ship an API nothing exercises yet.
5. **mdview Tier A** (Part 4) — thin, sits directly on step 4's `on_change`
   hook.
6. **mdview Tier B** — write-up only, in `mdview.nvim`'s own repo, not
   scheduled here.

## Open questions

1. **Ammonia's exact default attribute allowlist.** I confirmed the sanitizer
   uses `ammonia::Builder::default()` (tags: permissive, GFM-oriented,
   includes `div`/`span`/`details`/`summary`/`table`) and that mdview only
   adds `data-sourcepos` and the checkbox `<input>` beyond that default. I did
   not read ammonia's own crate source to enumerate exactly which attributes
   its *default* allows (e.g. whether `id` survives). Worth five minutes
   before Tier A ships, since it decides how much visual structure the
   mdview-flavored markdown can actually carry.
2. **Room-key routing for a synthetic key.** `send_markdown` accepts any
   string as the room key, but I did not trace how a browser tab gets pointed
   at a *specific* room versus the currently-open buffer's path
   (`state.set_preview_key` / the URL scheme in `launcher.resolve_browser_url`
   looked buffer-oriented on a first read). Needs tracing before Tier A's
   "push to `docmap://<root>`" design is provably reachable from a browser
   tab, not just theoretically postable.
3. **Diagram scope** (whole map vs. selected subtree, Part 2). My inclination
   is documented above; this is a UX call for you to make, not one I've made
   unilaterally.
4. **LuaLS run trigger for `watch = true`.** Running `--doc` on every debounced
   file save is almost certainly too slow for a tight edit loop. Likely
   answer: `watch` reruns the cheap header-only rescan every save, and the
   LuaLS merge runs on a much coarser trigger (manual `:LibMap full`, or a
   longer separate debounce) — flagged here rather than decided, since it
   trades off freshness against editor responsiveness.
