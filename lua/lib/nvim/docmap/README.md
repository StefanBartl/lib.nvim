# `lib.nvim.docmap`

Generates a **module map** from an annotated Lua tree: scan → LuaLS enrichment
(opt-in) → check → render. Doxygen-shaped, but scoped to the part that is
actually useful for a Lua utility library — hierarchy, module purpose, links,
type relationships, and drift detection.

The generated map for this repo lives in [`docs/map/`](../../../../docs/map/):
[`index.html`](../../../../docs/map/index.html) (interactive — Tree, Hierarchy
and Notes tabs) and [`overview.md`](../../../../docs/map/overview.md) (renders
on GitHub).

## Usage

```vim
:LibMap                    " regenerate the artifacts
:LibMap check              " verify without writing; findings go to the quickfix list
:LibMap full               " regenerate WITH LuaLS enrichment (class/alias detail, type + inheritance edges)
:LibMap open               " open the generated HTML in the system browser
:LibMap graph deps         " open the HTML on the dependency graph
:LibMap graph calls lib.nvim.fs   " …or on one module's call graph
:LibMap why lib.nvim.ui.kit lib.nvim.fs   " shortest require path between two
:LibMap dot deps           " the require graph as Graphviz DOT, in a buffer
:LibMap diff HEAD~5        " what this branch changed about the tree's shape
:LibMap dot calls lib.nvim.fs   " …scoped to one module's neighbourhood

:LibBrowse                 " navigate the same map inside the editor
:LibBrowse live            " …re-scanning on every write
:LibBrowse lib.nvim.fs     " …opened on one module
```

`:LibBrowse` is the editor-side counterpart to the generated page — a
drill-down navigator over the same edges rather than a diagram, because a
terminal cannot draw one better than the browser already does. What it can do
instead is jump to the source (`gd`), fill the quickfix list (`gq`) and stay
live. See [browse/README.md](browse/README.md).

`why` answers the question the Deps view can only be walked by hand to
answer. The chain goes to the **quickfix list**, not to a message, because
every hop *is* a location: the edge carries the line its `require` is written
on, so each entry jumps straight to the line that creates that link. The
summary says up front whether the path is load-time throughout or goes through
a lazy require somewhere — usually the difference between "has to go" and "is
fine".

`diff` is where the committed artifact stops being a picture and becomes a
*comparison point*: it is already in every commit, so `git show
<ref>:docs/map/module_map.json` is the whole retrieval and any two revisions
compare without generating anything. What comes out — modules and functions
added or removed, dependencies gained or lost, load-time cycles introduced,
blast radii that moved — is a review summary nobody writes by hand.

Two decisions worth knowing. Functions are split by whether the declared name
is qualified (`M.compare`, the module's surface) or bare (`node_set`, a
file-local helper); listing both equally buried the six entries that mattered
under eleven that did not, so the helpers are counted rather than listed. And
comparing against an **older schema** suppresses the dependency, cycle and
impact sections with the reason stated: schema 1 predates the require graph
entirely, so reporting every dependency in the tree as "added" would be
technically true and completely useless.

`dot` is the third renderer for the same edges, and it exists because the
other two cannot do what Graphviz does: the HTML page lays boxes out in BFS
layers and cannot route an edge around anything, and Mermaid is rendered by the
code host, which is worth a lot and costs all control over the result. It is
deliberately **not** wired to a `dot` binary — that would add an external
dependency and a "dot not found" failure mode to a feature whose whole output
is text. The buffer is something to yank, `:w`, or pipe through
`:%!dot -Tsvg`.

Its `scope` is a bounded neighbourhood, not unbounded reachability. That
sounds like the right answer and is not: measured over this tree, unbounded
scope kept 750 of 872 lines, because in a connected dependency graph almost
everything reaches almost everything. A scope that excludes nothing is not a
scope.

`graph` completes both the kind and, after it, the names the map knows — it is
the same page as `open`, opened at a state instead of at the root, since the
whole navigable state of the HTML lives in its URL fragment. Two things that
had to be right for that to work at all: the target is handed over as a
`file://` **URL**, because a fragment appended to a bare filesystem path just
becomes part of the filename and every opener then fails silently; and a name
resolves against a declared `@module`, a raw node id, *or* the module path a
**namespace**'s location implies — `lua/lib/nvim/fs` has no `init.lua` and so
declares no module, yet `lib.nvim.fs` is exactly what someone types, and
namespaces are the aggregation points a dependency graph is most useful at.

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

-- Graph queries, against whatever the handle currently holds — including
-- after a watch-triggered rescan, which is the reason they live on the handle
-- rather than as free functions over an IR someone captured earlier.
handle.requires("lua/myplugin/fs")   -- require edges out
handle.required_by("lua/myplugin/fs")
handle.callees("lua/myplugin/fs#M.read")   -- "<node id>#<declared name>",
handle.callers("lua/myplugin/fs#M.read")   -- the same ids the HTML map uses

local unsub = handle.on_change(function(ir, findings)
  -- runs after the initial scan and after every rescan (manual or watched)
end)

handle.uninstall()  -- or: require("lib.nvim.docmap").uninstall(handle)
```

`uninstall()` is idempotent — tearing down twice, or a handle that was never
installed, is a no-op, not an error, matching this repo's own
`usercmd.create`'s tolerance for repeated setup under hot-reload configs.

`registry.ensure_watch(root)` starts watching a root that is already
installed, without replacing its handle. That distinction is the point:
`install()` treats a collision as replace, which drops every `on_change`
subscriber — so upgrading by re-installing would silently unsubscribe
everyone. The case that needed it: `command.setup()` installs with the plain
config, which sets no `watch`, so a `:LibMap` earlier in the session left
exactly the handle `:LibBrowse live` then reused, and "live" meant a view that
never re-scanned.

The watch itself is covered end to end in
[`docs/TESTS/docmap_spec.lua`](../../../../docs/TESTS/docmap_spec.lua) — a
real `:write` through a real buffer, with `vim.wait` pumping the event loop
until the debounced rescan lands. Both directions are asserted: a write under
`source` rescans, and a write outside it does **not**. The second matters more
than it looks. Scoping this with an autocmd glob pattern is the obvious
approach and silently never fires on Windows, because Vim matches the raw
OS-native buffer path against a forward-slash pattern; the explicit
`is_subpath` check replaced it, and the test guards the opposite failure of
over-matching (verified by removing the check and watching the assertion
fail).

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
`@class`/`@alias` definitions onto the node that owns the file, plus two kinds
of directed edge (`node.types_detail`, `ir.edges`) — see
[`luals.lua`](luals.lua):

- **type-reference edges** (`kind="type"`) extracted from field types — "this
  class's field points at that class", what the Hierarchy tab's dashed edges
  and the Types view draw from;
- **inheritance edges** (`kind="extends"`) from `---@class Child : Parent`,
  what the Inheritance view draws from. A class's parents also stay readable
  on `types_detail[].extends` as written, *including* parents that resolve to
  nothing in the scanned tree — those produce no edge, the same rule
  `requires_external` follows for requires that point outside the map.

Without it, the Hierarchy tab still works off plain parent/child structure,
just with no dashed edges and no Inheritance view — which is why the committed
artifact under `docs/map/` is generated **without** `--full`: CI's `--check`
compares it byte for byte and would then need `lua-language-server` installed
to reproduce it. Both class-based views say so explicitly when opened against
such an artifact instead of rendering blank.

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
| Scan | [`functions.lua`](functions.lua) | `node.functions` — per-function docs via `vim.treesitter`, unconditional (no LuaLS needed) |
| Scan | [`symbols.lua`](symbols.lua) | `node.symbols` — module-scope tables, constants and bindings |
| Graph | [`deps.lua`](deps.lua) | `kind="require"` edges + `node.requires`/`required_by` |
| Graph | [`calls.lua`](calls.lua) | `kind="call"` edges — which function calls which |
| LuaLS (opt-in) | [`luals.lua`](luals.lua) | class/alias detail + `kind="type"` and `kind="extends"` edges merged into the IR |
| Check | [`check.lua`](check.lua) | `Lib.Docmap.Finding[]` — documentation drift |
| Render | [`render/`](render/) | HTML (Tree + Hierarchy + Notes tabs), Markdown, Mermaid, DOT |
| Encode | [`json.lua`](json.lua) | deterministic JSON |
| Diff | [`diff.lua`](diff.lua) | `Lib.Docmap.Diff` — what one revision changed about the shape |
| Live | [`registry.lua`](registry.lua) | `install()`/`uninstall()` — an in-memory `Handle` instead of files |

`deps` and `calls` run inside `scan()` itself, unlike the LuaLS merge: they
need no external tool and cost only in-memory resolution over data the walk
already read, so every caller of `scan()` — checks, renderers, a live handle —
sees the same fully-formed IR rather than some seeing a half-built one.

### One edge array, four kinds

`ir.edges` carries a `kind` discriminator (`"type"`, `"extends"`, `"require"`,
`"call"`) rather than living in four parallel arrays, so layout, filtering and
drawing exist once each instead of once per relationship. Each producer sorts
its own block and appends it; there is deliberately **no** shared comparator
over the merged array, because the optional fields are disjoint per kind and
one sort would have to special-case all of them (an early version did, and
compared `from_class` against `nil` the first time a require edge appeared —
and `"extends"` would have been the next casualty, since it is the one kind
with no `via`).

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
says about itself, not what its functions are — that's [`functions.lua`](functions.lua)'s job.

## Function-level scanning (`node.functions`)

Unlike the header scanner, this one *does* need to find code, not just a
leading comment block — but it still isn't `lua-language-server --doc`.
Verified against real `doc.json` output: `--doc` only surfaces symbols
reachable through a `@class`/`@alias` type graph, so an ordinary
`function M.foo(...)` in a module with no aggregate class declaration for its
exports simply never appears. Retrofitting every module with a redundant
aggregate class (duplicating what `---@param`/`---@return` already say above
each function) would have been a drift risk, not a shortcut.

So [`functions.lua`](functions.lua) uses `vim.treesitter` instead — already a
lib.nvim dependency (`lib.nvim.treesitter`), no new one added. A query finds
the three function shapes this repo actually uses (`function M.foo(...)`,
`local function foo(...)`, `M.foo = function(...)`), matched via
`iter_matches` rather than `iter_captures` (the two shapes put `@fname`
before or after `@fdef` in source order depending on which matched — only
match-grouped iteration handles both correctly). Only functions declared
directly in a file's top-level scope are scanned; a `local function` nested
inside another function's body is an implementation detail, not part of the
module's documented surface, and is walked past.

Each function's doc-comment block (the contiguous `---` lines immediately
above it, tracked by row-contiguity, not indentation guessing) is parsed for:

- the already-common tags: `@param`, `@return`, `@generic`
- previously-unused-in-this-repo LuaLS tags now given real value:
  `@deprecated` (rendered as a banner), `@see` (rendered as a link, validated
  by the `dead-see-target` check below), `@async`, `@nodiscard`, `@overload`
- two tags outside the LuaCATS spec: `@example` (a fenced code block,
  multi-line) and `@since` (deliberately not `@version`, which LuaLS defines
  as a required-Lua-runtime declaration — a different question from "since
  when has this existed in this project")
- `@internal`, which marks a function as implementation rather than published
  surface

`@internal` earns its place by sharpening every question of the form "is this
used". `undocumented-param` skips it, because an internal function's
documentation bar is the author's own and nagging is how a heuristic check
earns a spot on someone's ignore list; the structural diff counts it as a
helper rather than listing it as an API change; and the map badges it. Without
the tag those all have to guess from the *shape* of the declared name —
`M.compare` looks public, `node_set` looks private — which is a decent guess
and only a guess.

See [`docs/ANNOTATIONS.md`](docs/ANNOTATIONS.md) for the full survey of which
tags this repo already uses heavily, which real ones it doesn't (and why
they'd be worth adopting), and where the two custom tags fit in.

Two new generic checks build on this: `dead-see-target` (warn — an `@see`
target that resolves to nothing, same idea as `dead-readme-link`) and
`undocumented-param` (info — a text-based heuristic comparing the raw
signature's parameter count to the number of `@param` lines; deliberately
`info`-only since the heuristic can be wrong on complex signatures).

## What a module *is*, not just what it exports

Two things the detail pane could not answer before, both filled during the
same scan and the same parse:

**Module-scope tables, constants and bindings** ([`symbols.lua`](symbols.lua)).
`functions.lua` answers "what can I call"; this answers the rest of "what is in
here" — the lookup tables a module dispatches through, the constants that
encode its thresholds, the singletons it holds at load time. Reading a module's
source those are usually the first thing you look for, and no generated
documentation showed them.

Top level only, anchored on `(chunk …)` in the query rather than by walking
ancestors: a `local seen = {}` inside a function body is an implementation
detail, exactly as a nested `local function` is. Two shapes are deliberately
*not* reported, because another stage already owns them and reporting them
twice would be two places to keep in sync:

| Not reported | Owned by |
|---|---|
| `local fs = require("…")` | `deps.lua` — it is a dependency, and the alias is what makes call resolution work |
| `M.foo = function(…)` | `functions.lua` — it is a function |

A third exclusion is the module's own export table. It is not state a reader
wants listed — it *is* the module, already represented by the node and by
`node.export` — and it appears in essentially every file: measured over
lib.nvim, 188 of 600 entries, 159 of them literally named `M`. It is
identified by the chunk's `return`, covering both `return M` and
`return setmetatable(M, {…})`, rather than by "empty table", which would have
been wrong in the other direction: `local cache = {}` is real module state
that happens to start empty.

**Subtree stats** (`node.stats`). Modules, namespaces, `.lua`/`.md`/other
files, lines of Lua, functions, symbols and types, aggregated over the node
*and everything below it* — the question a directory answers is "how big is
this part of the tree". The roll-up walks `ir.order` backwards, which is a
valid post-order because `scan` appends a node before descending into it, so
every child sits after its parent.

Line counting happens in `functions.scan_file`, the one place the whole file is
already in memory; only `@types/` members — which carry no functions and so
never go through it — get their own cheap read. `stats.types` is the exception
that `scan` cannot fill, since the class/alias count only exists once LuaLS
enrichment ran, so `luals.merge` fills and rolls it up the same way.

## Call-graph scanning (`kind="call"` edges)

[`calls.lua`](calls.lua) reuses the tree [`functions.lua`](functions.lua)
already parsed — extraction and resolution are split, because resolution is
not a per-file question. `fs.read()` only means something once you know this
file bound `fs` to `lib.nvim.fs` and that some node declares that module,
which is why require-alias collection in [`deps.lua`](deps.lua) is a
prerequisite rather than a coincidence.

Four shapes resolve **exactly**, each a syntactic fact rather than a guess:

| Written | Resolved because |
|---|---|
| `fs.read(x)` | `fs` is bound by `local fs = require("lib.nvim.fs")` |
| `require("lib.nvim.fs").read(x)` | the module path is in the call itself |
| `M.helper(x)` | `M` is a prefix this file's own functions are declared on |
| `helper(x)` | a bare name matching a file-local `local function` |

The inline-require form is checked before the alias form, because its callee
text starts with the identifier `require`, which the alias branch would
otherwise try to look up as a local binding. It is worth its own branch rather
than being written off as rare: it is how this tree calls a lazily-required
dependency without a top-level binding, and supporting it added 25 real edges.

Everything else is dropped: `obj:method()` on an unknown receiver,
`vim.fs.dirname()` (outside the tree), `M[name]()` (not a name at all).
`opts.calls_heuristic` adds one guessed shape back — an unresolved bare name
matching exactly one function in the whole tree — marked
`confidence = "heuristic"` and drawn dashed. Off by default: a call graph that
confidently draws a wrong edge is worse than one that draws fewer.

Genuinely invisible to this is dynamic dispatch. `lib.nvim.require`'s lazy and
metatable strategies produce calls that appear nowhere in the source, and a
callback handed to `vim.schedule` or stored in a table is a call whose target
is a value, not a name. Doxygen has the same blind spot in C++ for the same
reason — which is why **no call-derived check is ever `error` severity**, and
why the Calls view's empty state says so rather than implying the function
calls nothing.

On reusing `lib.nvim.logger`'s pattern: it was considered and rejected as
direct code reuse — `logger.record` is built for runtime events (timestamps,
levels, redaction, ring-buffer flush-on-crash), while this scans static
source once. What *is* transferable is the shape of the idea: structured,
tagged records plus a dedicated inspection command (`:LibLogger show` as a
model for a possible future `:LibMap functions <module>`). Not built here —
the HTML detail pane's Functions section covers the immediate need — but
worth keeping in mind if a CLI-side query ever becomes worth adding.

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

### The five views

Toggled from the Hierarchy toolbar. Three of them are undirected structure, two
are directed graphs with a direction control of their own:

| View | Boxes are | Edges are | Doxygen equivalent |
|---|---|---|---|
| **Modules** | IR nodes | `children`, plus type edges dashed on top | Directory / class hierarchy |
| **Types** | `@class`/`@alias` definitions | `kind="type"` | Collaboration diagram |
| **Inheritance** | `@class` definitions that have a parent or a subclass | `kind="extends"` | Class hierarchy / inheritance diagram |
| **Deps** | IR nodes | `kind="require"` | Include dependency graph |
| **Calls** | individual **functions** | `kind="call"` | Caller / callee graph |

**Inheritance** is the one view that does *not* layer by distance from the
centered object, and cannot: a module normally declares a base class and its
subclasses side by side, so all of them seed the walk at once and a
distance-from-seed layout collapses the whole hierarchy onto one row (observed
on `Lib.Cache.Opts` sitting beside its own `LoadOpts`/`SaveOpts`). Depth comes
from the relation instead — longest path from a class with no parent, so a
class always renders strictly below *every* parent, including in a diamond
where one path is shorter than the other. Both directions are always shown;
unlike Deps and Calls there is no reason to want one side alone, so it costs no
state axis. Classes with no inheritance at all are left out rather than drawn as
isolated boxes in a view that exists to show relationships.

Direction (`← In` / `⇄ Both` / `Out →`) is an axis of the state, not two more
views: "callers of X" and "callees of X" are the same diagram walked the other
way, and splitting them would have doubled the view list with buttons saying
nearly the same thing. `Both` runs the two walks *independently* from the same
seeds — once a walk has gone up into callers, continuing downwards through
those callers' other callees would fill the diagram with functions unrelated
to the center. Doxygen makes the same choice.

Depth defaults to 2. A require graph's neighbourhood grows far faster than a
tree's, and `MAX_HNODES` alone would fill every diagram to the cap.

**`+ external`** (Deps only) also draws the requires that resolve to nothing in
the scanned tree — other plugins, or anything outside `source`. They live in
the IR as plain module strings on `node.requires_external`, never as invented
nodes: the map only claims to describe what it scanned, and a box with no
source, no summary and no functions behind it would break that. One box per
module however many nodes reach for it, since "these four all pull in plenary"
is the thing worth seeing. The boxes are inert — no navigation, no context
menu, because there is nothing to navigate to.

A prerequisite fell out of building it: `require("lib.lua." .. key)`, which is
how this tree's aggregators dispatch, puts a string literal exactly where the
extraction pattern looks and yields the dangling prefix `lib.lua.`. That
resolved to nothing and so cost nothing while unresolved requires were
discarded — and would have become four confident boxes for modules that do not
exist the moment they became visible. A module path has no empty segment, which
is what a leading, trailing or doubled dot means, so those are now rejected at
extraction. Verified: the resolved edge set is unchanged by the fix.

**Backedges.** The tree views never had them; a require or call graph is
cyclic, so a target keeps its first-seen BFS depth and later edges into it
point sideways or up. Drawn with the ordinary S-curve those run straight
through every box in between, so an edge whose target is not strictly below
its source is routed out of the box's side and back in — and every directed
view gets arrowheads, without which a same-layer edge says nothing about which
way it points.

### Functions are addressable

A function's id is `"<node id>#<declared name>"` — derived from data already in
the IR, so nothing extra is generated or serialized, and stable across
regenerations as long as the name is. That id is what the URL can point at,
what the Calls view centers on, and what the context menu acts on. Before it, a
function existed only as a block of text inside one node's detail pane.

They also appear in the Tree tab, behind a per-node collapsed `ƒ N functions`
group rather than mixed into `children`: `children` is IR structure and
functions are not part of it, and this tree renders eagerly — folding ~1500
function rows into the always-expanded default would bury the module structure
the tree exists to show.

### Right-click

Every clickable object — a tree row, a function row, a graph box, a type or
function entry in the detail pane — resolves through one `describeTarget()`
into `{kind, nodeId, fnKey, className, label}`, and the menu is built from
that. One resolver instead of four menus is what keeps "right-click anything,
get the same verbs" true as views are added.

Entries that lead nowhere are **disabled with their count shown**, not hidden:
an enabled item that opens an empty diagram teaches people to distrust the
menu. `preventDefault` fires only when the target actually resolves, so
selecting a paragraph of prose and reaching for the browser's own Copy still
works.

### Movement

Boxes are held in a keyed map and **reused across redraws**, so a box present
before and after a re-center is the same element at a new `left`/`top` and the
CSS transition animates it there. The previous `hgraph.innerHTML = ""` threw
that identity away every time, which is why every navigation was a hard cut
even when the two layouts shared most of their boxes.

Positions are still computed analytically from the IR, never measured off the
DOM — that is what lets the diagram be correct while the pane is `display:none`
— and animating did not change it: the movement is interpolation *between* two
deterministic layouts, not a simulation. No force-directed layout, no physics.

Edges are the exception: `d` is not an animatable CSS property, and a per-frame
path interpolator for up to 90 edges buys very little over simply not drawing
lines that would point at boxes still in motion. They are hidden while the
boxes move and faded in once they arrive.

Hovering a box dims everything that is not a direct neighbour — pure class
toggling, no relayout, and on a dense require graph the difference between a
readable diagram and a spider's web. Every transition is disabled under
`prefers-reduced-motion: reduce`.

### Zoom

Two mechanisms that are kept apart in the code, because conflating them makes
both half-work:

- **Geometric** — the same diagram, larger. A CSS transform on `#hstage`. No
  relayout, no redraw, and deliberately **not** in the URL: it is comfort, not
  state.
- **Semantic** — past a threshold, a *different excerpt*: one level down into
  the module under the cursor, or one level up. That is the
  `navigate({center})` a double-click already does.

The geometric zoom is the feel between two levels; the semantic one is the
jump. Only the jump touches history — the same rule the search preview had to
learn, for the same reason.

Positions stay analytic. The transform sits on a layer *above* the computed
pixel coordinates, so `positions`, `reconcile()` and the SVG paths never learn
that a zoom exists. `#hgraph` is sized to the *scaled* extent, because a
transform leaves layout size alone and the scroll area would otherwise not
grow on zoom-in, putting half the diagram out of reach.

| Gesture | Effect |
|---|---|
| wheel | scale, anchored on the cursor |
| shift+wheel | pan horizontally |
| `+` / `-` / `0` | zoom in / out / reset |

**Thresholds fire on *crossing*, not on being past.** That distinction is the
whole design, and getting it wrong was a real bug: a zoom that came to rest
above `DRILL_IN` drilled *in* on the next notch even when that notch was a
zoom-*out*. Crossing semantics also mean a refused jump can leave the zoom
above the line without re-firing on every further notch — which is what makes
"zoom further in to read a leaf box" work.

Asymmetric thresholds plus a cooldown, or it flaps: committing at 1.80 and
resetting to exactly 1.80 would re-trigger on the smallest wobble, so a
successful jump lands at 0.90 (in) or 1.15 (out), well inside the band, and a
jump blocked by the cooldown pulls the zoom back just inside the threshold so
the next notch can cross again rather than having to be wound all the way
back.

A jump that cannot happen — a leaf with no children, the root on the way out,
an external box, or the box that is *already* the center — pulses the box
instead of silently doing nothing, which reads as a bug.

In **Deps and Calls** the threshold binds to `depth ± 1` instead. "One level
deeper" is not defined in a require graph, which is not a containment
hierarchy; depth is the axis that means "show more" there, and it already
exists as state and as a control.

Below ~0.65 scale the secondary line in each box is unreadable grey noise, so
`#hstage.lod-min` hides it — pure CSS, no redraw, and the second sense in
which this zoom is semantic.

### SVG export

`↓ SVG` writes the current diagram as a standalone file. The boxes are redrawn
as plain `<rect>`/`<text>` rather than wrapped in `<foreignObject>`, which
Inkscape and most converters do not render, and colours are read back off the
live DOM so the export matches the theme it was taken from.

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

The state serialized into the hash is `{tab, id, center, view, dir, depth, fn}`
— every axis goes through `navigate()`, including the direction and depth
controls; a control that set one behind its back would produce a diagram the
Back button cannot return from. Only the axes the current view actually uses
are serialized, so a Tree-tab link is not three pieces of noise long. See
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

## Notes tab

Doxygen's Deprecated / Todo / Bug / Test lists, as a third tab. Four
aggregates over data the scan already has: `@deprecated` (a single string, the
migration hint) plus the three repeatable note tags `@todo`/`@bug`/`@test`
(one list entry per occurrence — see
[`docs/ANNOTATIONS.md`](docs/ANNOTATIONS.md)). Entries sort by module, then by
line, and clicking one jumps to that module in the Tree tab.

One tab rather than Doxygen's four pages: in a given tree three of these tags
are usually unused, and four tabs that are empty most of the time are four
tabs of noise. Empty sections say so explicitly instead of disappearing, so
"nothing here is deprecated" stays distinguishable from "this build did not
collect it" — the same reason the class-based Hierarchy views explain
themselves rather than rendering blank.

Deliberately **not** modelled as `check` findings. None of these is drift or
an error, and routing them through findings would fold an author's own to-do
list into the exit code CI fails on.

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
| `dead-see-target` | warn | A function's `@see` target resolves to no known module or function. |
| `undocumented-param` | info | A function has more parameters than `@param` lines (text-based heuristic, can be wrong on complex signatures — never fails `--check`). |
| `require-cycle` | warn | A cycle among **load-time** requires. |
| `layer-violation` | warn | Opt-in via `opts.layers`: a module reaching into a layer it must not. |
| `dead-function` | info | No `kind="call"` edge points at this function. Always checked for a top-level `local function` (unreachable outside its own file by construction) and anything tagged `@internal`; an ordinary exported function is only checked when `opts.dead_code = true` — a library's exported surface is *meant* to have no internal caller, so on by default it would flag half the public API. Never anything stronger than `info`: dynamic dispatch (`M[name]()`, callbacks in a table, the lazy/metatable strategies in `lib.nvim.require`) is invisible to the call graph. |

`require-cycle` excludes deferred requires — `require(...)` inside a function
body, the standard way this tree breaks initialisation order on purpose. Run
without that exclusion against lib.nvim, every cycle it reported was a
deliberate lazy load; a check that only ever fires on intentional code is one
people learn to skim past, so it would have cost the real ones too. The
distinction is made from the parse (any function body, not just top-level
declarations — a lazy require hides inside an anonymous
`__index = function(_, k)` just as often as inside a named function), and both
kinds remain real edges in the Deps view, drawn dotted when lazy.

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
