# `lib.nvim.docmap.browse`

`:LibBrowse` — the module map inside the editor.

```vim
:LibBrowse                  " read docs/map/module_map.json (~10ms)
:LibBrowse live             " install a watching handle instead (~0.65s once)
:LibBrowse lib.nvim.fs      " open centered on a module
:LibBrowse live lib.nvim.fs
```

```lua
require("lib.nvim.docmap.browse").open({ root = "/path/to/repo" })
```

## What this is not

**Not the HTML diagram in a terminal.** Boxes with connecting curves need
pixels — free positions, curves, continuous zoom. A terminal is a fixed cell
grid, and what comes out of that is a worse version of
[the page that already exists](../render/html.lua). Nobody would prefer it.

So this is a **navigator over the same edges**, not a drawing of them: the
hierarchy is a drill-down list, and Deps/Calls are lists too.

## Why it exists anyway

Three things the editor can do that the generated page cannot:

1. **Jump to the source at the line** (`gd`). The page can at best link to
   GitHub.
2. **Fill the quickfix list** (`gq`). "Every caller of `M.read`, in the
   quickfix list" is what an editor UI is for — and the point where call
   edges stop being decorative and start saving work.
3. **Be live** (`:LibBrowse live`). The page is an artifact showing the state
   of the last `:LibMap`; a watching handle re-scans on write.

If only one of those survived, it would be (2).

## Data source

Artifact-first, and that is measured rather than assumed:

| Path | Cost |
| --- | --- |
| `scan()` over lib.nvim | **0.65 s** (283 nodes) |
| read + decode `module_map.json` | **0.01 s** (810 KB) |

Two thirds of a second of blocking editor time between keypress and window is
the difference between "opens" and "hangs", so the default reads the artifact
and the live scan is opt-in. The cost of that choice is staleness, so the
status line says so when the artifact is older than the newest source file
rather than showing wrong data silently.

`live` reuses an already-installed handle rather than installing a second one,
because `install()` treats a collision as replace — which tears down a watch
another caller may rely on *and* drops every `on_change` subscriber with it.
Reusing alone was not enough, though: `docmap.command.setup()` installs with
the plain config, which sets no `watch`, so a `:LibMap` earlier in the session
left exactly the handle this finds, and "live" meant a view that never
re-scanned on write — the mode's whole promise, broken by nothing more than
which command ran first. `registry.ensure_watch()` upgrades such a handle in
place, keeping its subscribers.

> The artifact and the in-memory IR are not the same document: `module_map.json`
> writes `nodes` as an **array** in walk order (that is what makes the file
> byte-deterministic — a JSON object's key order would not be) and carries no
> `order` key. `source.rehydrate` bridges the two so everything downstream
> reads one shape. Absent optional fields are written as `null`, so decoding
> uses `luanil` — otherwise `node.module` comes back as `vim.NIL`, which is
> *truthy*, and `types_detail == nil` (the "LuaLS never ran" signal) is never
> true.

## Modes and keys

| Key | Effect |
| --- | --- |
| `1` … `4` | Structure / Deps / Calls / Types |
| `j` `k` | Move; the detail pane follows |
| `<CR>` | Descend a level (Structure) or follow the edge (Deps/Calls) |
| `-` / `<BS>` | Up a level |
| `<C-o>` / `<C-i>` | Back / forward through the visit history |
| `h` / `l` | Direction: incoming / outgoing (Deps, Calls) |
| `+` / `_` | Depth ±1 (Deps) |
| `gd` | Open the source at the line, closing the browser |
| `gq` | Current list into the quickfix list |
| `gI` | Blast radius of the selected node into the quickfix list |
| `gO` | Open the generated page at this exact position |
| `/` | Fuzzy jump across every module and function |
| `q` `<Esc>` | Close |

The history stack is the counterpart to the browser's Back/Forward, and it
matters *more* here: without an address bar there is no other answer to "where
am I".

`history` holds the whole trail **including the current position**, with
`hindex` pointing at it — the model the HTML renderer and every browser use.
Worth stating because the alternative is tempting and does not work: recording
only *past* positions leaves `hindex` addressing the entry before the current
one, so the first `<C-o>` falls off the front of the list and the second lands
one stop too far back. Both directions are a plain bounds check now, and the
cursor row of the position being left is synced into its entry before moving,
so coming back restores the row the user was on rather than the row they
arrived at.

A key that cannot change anything does not become a stop either — `+`/`_`
outside Deps (depth is the only axis `walk_requires` reads), `h`/`l` when the
direction is already what was asked for. Otherwise the trail fills with
positions identical to their neighbours, and a `<C-o>` that visibly does
nothing reads as the history being broken rather than as the key having been a
no-op.

`gI` is the counterpart to `gq`: `gq` sends what is *on screen*, `gI` sends
what would **break**. It reports the transitive closure of `required_by`, and
it acts on whatever the detail pane is describing rather than on the centered
node — those differ the moment the cursor moves, and a figure that disagreed
with the one two panes over would be worse than no figure. On a *function*
entry the answer is its module's radius, which is the only honest one: the
require graph has no finer grain than a module.

`gO` hands the current position to the generated page. The navigator knows
mode, center, direction, depth and function; the page's whole state lives in
its URL fragment. So it is a `format()` and the existing opener, and it
answers "actually, I want to see that as a picture" without having to find the
place again.

## Layout

Three [`ui.kit.layout`](../../ui/kit/README.md) slots:

```
┌─ list ───────────────┬─ detail ─────────────────┐
│ ▸ lib.nvim.fs        │ lib.nvim.fs.read         │
│   lib.nvim.git       │                          │
│ ▸ lib.nvim.store     │ Reads a file…            │
│   …                  │ @param path string       │
│                      │ 3 callers · 1 callee     │
├──────────────────────┴──────────────────────────┤
│ lib.nvim ▸ fs ▸ read     [calls ←in]            │
└─────────────────────────────────────────────────┘
```

Each slot gets a filetype (`lib-docmap-browse-list` / `-detail` / `-status`)
so a user's own config can highlight them.

## Structure

| File | Holds |
| --- | --- |
| `source.lua` | Where the IR comes from: artifact vs. live handle, rehydration, the staleness check |
| `view.lua` | Pure: state → list entries, detail lines, status line. No window touched, so the mode logic is testable headlessly |
| `init.lua` | Layout, state, navigation, keymaps, actions |

`view.lua` being pure is what lets
[`docs/TESTS/docmap_browse_spec.lua`](../../../../../docs/TESTS/docmap_browse_spec.lua)
check every mode against a synthetic IR without mounting anything.

## Notes

- The entry under the cursor is read from the **window**, not from a cached
  index. The cache is kept in step by a `CursorMoved` autocmd, which is fine
  for redrawing but must not be what an action trusts: any path that moves the
  cursor without firing that autocmd would make `<CR>` act on a row the user
  is not looking at. (It did, before this was fixed.)
- `gd` on a Calls entry lands on the callee's **declaration**, not on the call
  site. An edge's `line` is where the call is written, which is in the file
  already on screen — jumping there would send every row in the list back to
  where it started.
- Closing on `gd` is deliberate: the floats cover the editor, so "jumping to" a
  file the user cannot see is not a jump.
