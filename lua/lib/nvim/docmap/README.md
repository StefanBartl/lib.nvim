# `lib.nvim.docmap`

Generates a **module map** from an annotated Lua tree: scan → LuaLS enrichment
(opt-in) → check → render. Doxygen-shaped, but scoped to the part that is
actually useful for a Lua utility library — hierarchy, module purpose, links,
type relationships, and drift detection.

The generated map for this repo lives in [`docs/map/`](../../../../docs/map/):
[`index.html`](../../../../docs/map/index.html) (interactive — Tree and
Hierarchy tabs) and [`overview.md`](../../../../docs/map/overview.md) (renders
on GitHub).

## Usage

```vim
:LibMap              " regenerate the artifacts
:LibMap check        " verify without writing; findings go to the quickfix list
:LibMap full         " regenerate WITH LuaLS enrichment (class/alias detail, type edges)
:LibMap open         " open the generated HTML in the system browser
```

```bash
nvim --headless -l scripts/gen_map.lua               # regenerate
nvim --headless -l scripts/gen_map.lua --check       # verify: stale or drift -> exit 1
nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
nvim --headless -l scripts/gen_map.lua --full        # + LuaLS enrichment
```

The `:LibMap` command is opt-in — call `require("lib.nvim.docmap.command").setup()`
to register it. Requiring `lib.nvim.docmap` alone never creates a command.

## Live objects: `install()` / `uninstall()`

`generate()` and `:LibMap` are one-shot: scan, write files, done. `install()`
is the other half — a live `Lib.Docmap.Handle` another plugin's source code
reaches for directly, instead of parsing `module_map.json` off disk:

```lua
local handle = require("lib.nvim.docmap").install({
  root = vim.fn.getcwd(),
  source = "lua/myplugin",
  watch = true,      -- rescan on BufWritePost under source/**.lua, debounced
})

handle.ir()                          -- current Lib.Docmap.IR, in memory
handle.node("lua/myplugin/init.lua") -- single node lookup
local unsub = handle.on_change(function(ir, findings)
  -- runs after the initial scan and after every rescan (manual or watched)
end)

handle.uninstall()  -- or: require("lib.nvim.docmap").uninstall(handle)
```

`uninstall()` is idempotent — tearing down twice, or a handle that was never
installed, is a no-op, not an error, matching this repo's own
`usercmd.create`'s tolerance for repeated setup under hot-reload configs.

`:LibMap`/`docmap.command.setup()` is itself built on `install()`: it reuses
(or creates) a handle for `opts.root` rather than scanning separately, so a
plugin that calls `install()` first and later also calls `command.setup()`
gets the *same* IR both ways, and `on_change` subscribers see every `:LibMap`
run too. `opts.command_name` (default `"LibMap"`) exists so two independent
`setup()` calls — this repo's own map and a consuming plugin's — don't
register the same command name (`usercmd.create` defaults to `force = true`,
so that collision would silently overwrite one of them, not error).

## LuaLS enrichment (`opts.luals`)

Off by default — a full-repo `lua-language-server --doc` run costs several
real seconds (measured: ~4.5s over this repo's ~250 files). Merges parsed
`@class`/`@alias` definitions onto the node that owns the file, plus directed
**type-reference edges** extracted from field types (`node.types_detail`,
`ir.edges`) — see [`luals.lua`](luals.lua). This is what the Hierarchy tab's
dashed edges draw from; without it, the tab still works off plain parent/child
structure, just with no dashed edges.

```lua
require("lib.nvim.docmap").generate({ ..., luals = true })
-- or: :LibMap full / nvim --headless -l scripts/gen_map.lua --full
```

If `lua-language-server` isn't on `PATH`, or the run fails, this degrades to
an `info`-severity `luals-unavailable` finding rather than failing the scan —
everything else in the IR is still valid.

## Using it for another plugin

Nothing outside [`config.lua`](config.lua) knows lib.nvim's layout. Another
plugin points docmap at its own tree:

```lua
require("lib.nvim.docmap").generate({
  root = "/path/to/my-plugin",
  source = "lua/myplugin",
  lua_root = "lua",
  title = "myplugin.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/me/my-plugin",
})
```

The only requirement on the tree is that files carry `---@module`. Everything
else — module prefix, directory layout, types directory name — is an option.

## Pipeline

| Stage | Module | Produces |
|---|---|---|
| Scan | [`scan.lua`](scan.lua) | `Lib.Docmap.IR` — hierarchy, summaries, links |
| LuaLS (opt-in) | [`luals.lua`](luals.lua) | class/alias detail + type-reference edges merged into the IR |
| Check | [`check.lua`](check.lua) | `Lib.Docmap.Finding[]` — documentation drift |
| Render | [`render/`](render/) | HTML (Tree + Hierarchy tabs), Markdown, Mermaid |
| Encode | [`json.lua`](json.lua) | deterministic JSON |
| Live | [`registry.lua`](registry.lua) | `install()`/`uninstall()` — an in-memory `Handle` instead of files |

`scan_full()` in [`init.lua`](init.lua) is `scan` + optional `luals` + `check`
in one call — the step `generate()` and `install()`'s rescan both build on, so
the enrichment wiring exists exactly once. The IR itself is the contract
between scan/LuaLS and render/check: renderers never touch the filesystem,
and the scanner never knows what will be drawn.

### What the scanner does *not* do

It does not parse Lua. It reads each file's leading comment block — everything
before the first non-comment line — and stops. That is reliable here because
`---@module` coverage in this tree is 226/226, and it costs ~200 lines instead
of a Lua front end.

The consequence: the scanner alone knows *that* a module exists and what it
says about itself, not what its functions are — that's what the opt-in LuaLS
step above is for.

## Structure of the map

| Node kind | What it is |
|---|---|
| `module` | A directory containing `init.lua` |
| `namespace` | A directory without `init.lua`, grouping others |
| `file` | A non-`init.lua` Lua file |

Helper files stay visible as leaves rather than being folded into their
parent — `find_upward_dir/matcher.lua` is real, documented, and worth finding.
A `@types/` directory is an **attribute** of its module, not a sibling node:
types belong to the thing they type, and promoting them doubles the tree for
no navigational gain.

## Hierarchy tab

A second view in the generated HTML, alongside the Tree/detail pane: `<div>`
node boxes laid out in layers by depth from a centered node, with an SVG
overlay drawing solid parent/child connectors and (once `opts.luals` ran)
dashed type-reference connectors. Center on any module or namespace via its
detail-pane "Hierarchy ↳" link, or double-click a box to re-center on a
smaller subtree — capped at 90 nodes per view (`MAX_HNODES` in
[`render/html.lua`](render/html.lua)), since a box-and-connector diagram of
the whole ~250-node tree at once is not something either box-and-connector
diagrams or the people reading them handle well.

Box positions are computed analytically from the IR (layer index × row
position), not measured off the DOM — deliberately, so the diagram renders
correctly whether or not the pane is currently visible, with no
measure-after-show step to get right. The view auto-scrolls to center the
node it was centered on, since a shallow layer (the root has one box) sharing
a horizontal axis with a much wider deeper layer means the centered node can
sit thousands of pixels from the left edge on a large map.

### Modules vs Types

Two "aufbereitungen" (renderings) of the same annotation data, toggled via
buttons in the Hierarchy toolbar:

- **Modules** — the directory/module hierarchy above: boxes are IR nodes,
  solid edges are `children`, dashed edges are `ir.edges` filtered to the
  laid-out subtree.
- **Types** — a materially different graph, not a relabeling: boxes are
  individual `@class`/`@alias` definitions from `node.types_detail`, and
  edges are walked directly from `ir.edges`' `from_class`/`to_class` (which
  can cross node boundaries freely — a field can reference a class owned by
  any module in the map, and that's the point of this view). Requires
  `opts.luals` to have run; shows a message pointing at `:LibMap full`
  otherwise, or if the centered node has no types of its own.

### Search re-centers, not just filters

The same `#q` input that filters Tree rows re-centers the Hierarchy view on
the best-matching module while typing, when the Hierarchy tab is active.
Matching prefers an exact name/module match, then a name/module prefix, then
a substring anywhere (including the summary).

Typing updates the diagram live but does **not** touch browser history — see
[Back/Forward](#backforward-navigation) for why that matters here
specifically, not just as a nicety. Press Enter to commit the current match
as a real, navigable stop.

### Clickable findings

Each row in the "Drift findings" table that names a real IR node (most of
them — a couple of repo-specific checks report against synthetic paths that
were never scanned nodes, and those rows just stay inert) is clickable:
selects that node in the Tree tab.

### Back/forward navigation

Every discrete action (selecting a tree node, switching tabs, centering the
Hierarchy view, toggling Modules/Types) pushes a real `history` entry, so the
browser's own Back/Forward buttons step through the app's actual states —
not just react to a directly-edited URL hash, which is all the original
single-node `#<id>` scheme supported.

The state serialized into the hash is `{tab, id, center, view}` — see
`serializeState`/`parseState`/`applyState`/`navigate` in
[`render/html.lua`](render/html.lua). One non-obvious rule worth knowing if
you touch this: **live-preview updates (the Hierarchy search box while
typing) must never call `history.replaceState`.** An earlier version did,
and it silently broke Back — `replaceState` overwrites whatever entry is
currently on top of the stack, which right after switching to the Hierarchy
tab is the tab-switch entry itself. The first keystroke clobbered it, so
committing the search with Enter ended up pushing a *duplicate* of the
already-overwritten entry instead of a distinct new stop, and Back from the
committed search landed on an indistinguishable copy of itself instead of
the pre-search tab state. Live preview now calls `drawHierarchy()` directly,
bypassing history entirely; only Enter (or any other discrete action) calls
`navigate()`.

## Drift checks

The rendered map is the visible half; the checks are the half that catches
bugs. Generic checks (any annotated Lua tree):

| Check | Severity | Catches |
|---|---|---|
| `missing-module-tag` | error | A source file with no `---@module`. |
| `module-path-mismatch` | error | Declared `@module` ≠ where the file lives — copy-pasted or stale headers. |
| `missing-summary` | warn | `@module` present but no description line. |
| `dead-readme-link` | warn | A relative link in a README pointing at nothing. |
| `missing-readme` | info | Module without a README — should be a decision, not an accident. |
| `unreferenced-module` | info | Required by no other file in the tree. |

Repo-specific checks are passed in via `opts.extra_checks`. lib.nvim adds one:

| Check | Severity | Catches |
|---|---|---|
| `type-not-exported` | error | A `---@field` on the aggregate `Lib` class that does not resolve at runtime. |

That last one exists because `lib.find_root` was declared on the `Lib` class
and wired into none of the export strategies — the published type was simply
false, and it was found by accident. The check resolves against
`require("lib")` rather than by scanning the strategy sources: an early regex
version produced a false positive on `json_decode_to_string_array`, which is
wired through `SPECIAL_HANDLERS` in a shape the pattern did not match.
Indexing the real table is ground truth.

## Determinism

Two decisions make `--check` possible:

- **No timestamp in the IR.** A `generated_at` field would make every
  regeneration a diff even when nothing changed.
- **Sorted-key JSON** via [`json.lua`](json.lua), not `vim.json.encode`, whose
  object key order is unspecified. Without it, two runs over an unchanged tree
  produced byte-different files and `--check` reported the map as stale
  immediately after generating it.

Output is byte-identical across runs on unchanged input.

## Why `--check` does not regenerate

A hook that regenerates and stages output produces diffs the author never
intended, and interacts badly with `--amend` and rebase. `--check` fails with
"module map is stale — run `:LibMap`" and leaves regeneration explicit.

`--check` fails on both staleness and error-severity drift. Enforcing drift
was originally opt-in, because the tree carried a backlog of it and a check
that is red before anyone touches anything gets disabled. That backlog is
cleared, so enforcement is the default and `--lenient` is the escape hatch.

## Git hook

```bash
git config core.hooksPath scripts/hooks   # once per clone
```

[`scripts/hooks/pre-commit`](../../../../scripts/hooks/pre-commit) runs
`--check` when `lua/`, `docs/map/` or the generator changed, and prints the
findings plus the one command that fixes them. It never regenerates or stages
anything itself. Bypass with `git commit --no-verify`.
