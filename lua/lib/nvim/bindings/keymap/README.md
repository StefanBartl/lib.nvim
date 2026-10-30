# `lib.nvim.bindings.keymap`

Two levels. Most plugins want both.

## 1. One-off mappings

The validated `vim.keymap.set` wrapper this module has always been — the
module stays callable, so existing call sites are unchanged.

```lua
local keymap = require("lib.nvim.bindings.keymap")

keymap("n", "q", close, { buffer = true }, "close")
keymap.set("n", "q", close, { buffer = true }, "close")   -- the same thing
```

Defaults applied when unset: `noremap = true`, `silent = true`, `desc = ""`.
`opts.buffer = true` is normalised to buffer `0` (the current one); the record
kept for `registered()`/`cheatsheet()` holds the real buffer number. Wrong
argument types are reported through `lib.nvim.notify` **with the caller's
file and line**, instead of a stack trace from inside `vim.keymap.set`.

Use it for keys that are not part of a plugin's public surface: a `q` inside a
report window, a floating-window binding — anything a user has no reason to
rebind.

## 2. Named actions (`register`)

For everything that *is* public surface. A plugin declares actions by **name**;
the `lhs` is only their current default, and the user's spec can move or drop
any of them individually.

```lua
keymap.register("spotlight", {
  prefix = "<leader>s",
  which_key = { group = "Spotlight" },
  order = { "toggle_here", "toggle", "next", "prev" },
  actions = {
    toggle_here = {
      default = "<leader>sk",
      mode = { "n", "x" },
      rhs = api.toggle_here,
      desc = "toggle this occurrence only",
    },
    next = { default = "]k", rhs = api.next, desc = "next spotlight" },
  },
}, cfg.keymaps)
```

The user, in that plugin's setup spec:

```lua
keymaps = {
  toggle_here = "<leader>x",   -- remap
  next        = false,         -- drop just this one
  preset      = false,         -- or: bind nothing at all
}
```

`preset = false`, `enable = false`, or the whole table set to `false` all bind
nothing — several plugins here spell it the short way, and accepting all three
means migrating one never silently changes what its users' config means. The
actions are still **recorded** — the health check and the generated docs want to know what
exists, not only what is currently bound.

### Several keys for one action

`default` and the user's override both accept a list. One action on more than
one key is a real case — gopath binds `open_here` to `gF` *and* to a
double-click — and it stays one action, so moving or dropping it is still said
once:

```lua
open_here = { default = { "gF", "<2-LeftMouse>" }, rhs = ..., desc = "open here" },
```

```lua
mappings = { open_here = { "gF", "<C-CR>" } }   -- replaces both defaults
mappings = { open_here = false }                -- drops both
```

A list override replaces the defaults outright rather than adding to them:
"also bind this" and "bind exactly these" are different requests, and only the
second one lets a user *remove* a default they dislike.

### One key, two modes, different functions

The same key routinely means the same *intent* in two modes while calling
different functions — normal mode acting on the token under the cursor, visual
mode on the selection. To a user that is **one** action: one name, one key, one
override. So it stays one action here, with the per-mode differences in
`binds`:

```lua
toggle_here = {
  default = "<leader>sk",
  desc = "toggle this occurrence only",   -- fallback for binds without one
  binds = {
    { mode = "n", rhs = api.toggle_here },
    { mode = "x", rhs = api.toggle_here_selection, desc = "toggle this selection only" },
  },
},
```

Splitting that into `toggle_here` and `toggle_here_selection` would force a
user who moves the key to say so twice, and to keep the two in step by hand.
Each bind yields its own entry in `registered()`, sharing the action's name and
`lhs`, so the docs can group them and `conflicts()` still sees one row per mode.

### Overrides that carry options

Some plugins let a mapping carry more than its key — insights' symbol mappings
also decide the scope and symbol type they open with. Such an override is a
table **with** an `lhs` field:

```lua
keymaps = {
  symbols_telescope = { lhs = "<leader>ps", scope = "buffer", type = "tables" },
}
```

A plain list of keys is a table **without** one, so the two can never be
confused: an array has no `lhs`, a spec table has no positional entries. The
registry takes the key and leaves the rest to the plugin.

### Why names, not `lhs` keys

Keying the override table by the current default — `{ ["]k"] = "<leader>n" }` —
reads more directly and is the obvious first idea. It fails in three ways a
name does not:

1. **It cannot say "disable".** The key already *is* the value's counterpart,
   so `false` has nowhere to attach that does not also read as "map to
   nothing".
2. **It breaks silently when a default changes.** The user's `["]k"]` then
   matches no action: no error, no mapping, and nothing saying why.
3. **It cannot say which plugin is meant.** Two plugins defaulting to the same
   `lhs` are indistinguishable.

A wrong *name*, by contrast, is detectable — and is reported:

```
[lib.nvim.bindings.keymap] spotlight: no such keymap action: nexr (did you mean next?)
```

That one line is the main practical reason for the whole module. A typo in a
keymap override is otherwise completely silent.

### No `<Plug>` layer

`<Plug>` exists so a user can remap an action without the plugin offering a
config key — which is exactly what this module offers instead. Mappings bind
straight onto the action's `rhs`.

### Buffer-local presets

Some presets belong to a filetype rather than to the session — images.nvim
binds its whole set per buffer from a `FileType` autocmd. Pass the buffer:

```lua
keymap.register("images", spec, cfg.keymaps, { buffer = ev.buf })
```

Declare once at setup and bind per buffer:

```lua
keymap.register("images", spec, cfg.keymaps, { bind = false })      -- at setup
keymap.register("images", spec, cfg.keymaps, { buffer = ev.buf })   -- per buffer
```

`bind = false` declares the actions and puts the which-key group up without
binding anything — the label is global and belongs there as soon as the preset
exists, not on whichever buffer happens to match first, and `:checkhealth`
should see the actions in a session that never opens a matching file.

Re-registering per buffer is the normal case, not an error. The action set is
the same everywhere; only the target differs, so the registry keeps **one**
record per plugin rather than one per buffer — which is what `registered()`
and the health check want to read.

An unknown name is reported **once** per plugin, not once per registration.
Without that, one typo in a buffer-local preset would warn once per file
opened.

## which-key

**which-key needs no registration to show these mappings.** It reads
`nvim_get_keymap` itself and labels each mapping with its own `desc`
(`which-key/buf.lua`), and `register` always sets a `desc`. A `which_key = true`
switch would therefore do nothing at all; there isn't one.

Three things *are* outside what which-key can infer:

| | how |
| --- | --- |
| **Group label** for a prefix | `which_key = { group = "Spotlight" }` next to `prefix` |
| **Icon** | `which_key = { icon = "" }`, per action or on the prefix — see below |
| **Hiding** one mapping | `which_key = false` on the action |

A table implies "yes" — there is no separate `true` to remember.

One plugin may own several prefixes. fileops labels `<leader>n` and
`<leader>p` separately — "next file" and "prev file" are two groups, and
labelling them together would say neither — so a **list** is accepted next to
the single-group form:

```lua
which_key = {
  { prefix = "<leader>n", group = "fileops: next file" },
  { prefix = "<leader>p", group = "fileops: prev file" },
},
```

An array has a `[1]`; a single group spec does not, so the two cannot be
confused.
 Hiding works
even without which-key installed: it sets which-key's own `which_key_ignore`
description on the mapping rather than calling into the plugin.

### Icons need a declared Nerd Font

Icons are only sent when `vim.g.have_nerd_font` is `true`. Default: **off**.

That is a declaration, not a check, because **Neovim cannot see the terminal's
font**. Measured rather than assumed: `strdisplaywidth()` returns 1 for every
codepoint, including `U+10FFFD` — a noncharacter no font contains. It consults
Unicode width tables and never the font, so any "detection" here would be a
guess dressed up as a check.

Off by default is the asymmetry that matters: guessing wrong fills the popup
with replacement boxes, while a missing icon costs nothing — the mapping still
shows with its description. One line in a config turns them on everywhere:

```lua
vim.g.have_nerd_font = true
```

A plugin can therefore declare icons unconditionally; they stay inert until
that line exists.

`desc` is deliberately **not** sent to which-key: it already has it from the
mapping, and a second copy is how the two get to disagree. (Four plugins here
used to register descriptions that their mappings already carried.)

which-key is a soft dependency throughout — nothing loads it eagerly, and the
call is `pcall`ed, because a wrong label is never worth taking a plugin's
`setup()` down with it.

## Reading the registry back

```lua
keymap.registered()            -- every plugin's actions AND its plain set() maps
keymap.registered("spotlight") -- one plugin's
keymap.conflicts()             -- lhs values claimed more than once
keymap.forget("spotlight")     -- drop a plugin's direct records before a re-setup
```

### A `g?` cheatsheet from it

```lua
local sheet = keymap.cheatsheet("testing", {
  groups = { { title = "Run", actions = { "run_file", "run_nearest" } }, { title = "Move", actions = { "next_fail" } } },
  footer = "q close",      -- hint line(s) under the list
  width = 60,              -- cut longer text with an ellipsis; the key column takes at most half
  -- buffer = bufnr, modes = true, indent = 2, other_title = "Other",
  -- hl = { heading = "Title", key = "Special", desc = "Normal", footer = "Comment" },
})
vim.api.nvim_buf_set_lines(buf, 0, -1, false, sheet.lines)
for _, h in ipairs(sheet.highlights) do -- { line (0-based), col_start, col_end (exclusive), group }
  vim.api.nvim_buf_add_highlight(buf, ns, h.group, h.line, h.col_start, h.col_end)
end
```

Only what is **bound** is listed (a disabled action, `preset = false`, or an action without a key is
not), one action on several keys is one row (`<a> / <b>`), the registry's `plugin: ` prefix is stripped
from the description, aligned on one key column. `groups` orders the sections; actions not named in
one go under `other_title`. Without `buffer` only global entries show; with it, global ones plus that
buffer's. `sheet.rows` holds what is shown (`name`, `keys`, `modes`, `desc`), `sheet.width` the widest
line. A `plugin/surface` registry key is addressed as given.

This is what makes it a registry rather than a binder. The same list is what a
`:checkhealth` section, a generated bindings page, and a "is every action also
reachable as a user command?" audit each need — and each of them re-deriving it
from source is how those drift apart.

### Plain `set()` calls count too

A plain `keymap.set(...)` used to record **nothing**, and that is the call
almost everybody actually makes. The gap was not small: in the author's config,
59 registered actions against 305 real keymaps. A page generated from this
registry was over eighty percent blind, and `conflicts()` could not see a
collision between two `set()` keymaps *even in principle* — which is most of
them.

So `set()` records as well. Such an entry is marked `direct = true`, carries the
`file:line` it was called from, and lands in a bucket derived from that path (the
directory holding the `lua/` it sits under), so a plugin's direct calls group
under the plugin without anyone passing a name. Pass `record = false` to opt out
— `register()` does, because it writes its own richer entry.

Direct records are kept in `keymap.records`, not in the same table, because
`register()` replaces a plugin's array wholesale and would otherwise wipe them;
`registered()` merges the two and returns a fresh list. So does `register()`
itself. Sorting or trimming either result is safe; the entries inside are the
registry's live records, shared with `:checkhealth`, `conflicts()` and the
docs generator — read them, do not mutate them. A `setup()` that rebinds the
same keys should call `forget(plugin)` first, or the list grows on every call.

UI buffers that are recreated on every open (a picker, a float) bind their keys again from the same call
site under a new buffer number. Direct records of a buffer that is wiped or unloaded (`:bdelete`, `bufhidden=delete`:
Neovim discards its buffer-local maps) are dropped whenever a new one is added or the list is read, so those buffers do not pile up; no tag or scope argument is needed.

### `conflicts()`

Deliberately *not* checked during registration: a plugin cannot know what a
later one will bind, so the answer is only meaningful once everything has
loaded.

Buffer scope is part of the identity. A buffer-local binding and a global one on
the same key are not a conflict — the local one shadows the global one inside
its buffer, and that is the point of it. Bucketing them together would report
every buffer-local preset, and a report that cries wolf is one nobody reads.

## The two scopes of `conflicts()`

`conflicts()` answers for what lib.nvim bound, because that is all it can
know. A raw `vim.keymap.set`, an `nvim_set_keymap`, a lazy.nvim `keys` entry
never passed through `register`/`set`, and `nvim_get_keymap()` cannot fill the
gap: it reports the **winner** of a key, so a mapping that was overwritten is
simply gone. Two bindings on `<M-h>` in the same mode look like one.

So there are two scopes:

| scope | sees | needs |
| --- | --- | --- |
| `"registered"` (default) | only bindings made with `keymap.set` / `register` | nothing |
| `"full"` | those, plus raw and lazy.nvim bindings, **including overwritten ones**; and a live image of the effective mappings (Neovim's own defaults included) | the **tap**, installed early |

```lua
keymap.conflicts()                      -- registered, as ever
keymap.conflicts({ scope = "full" })    -- + whatever the tap recorded
```

The second result describes how the answer was reached:

```lua
local conflicts, info = keymap.conflicts({ scope = "full" })
-- info.scope, info.tap_installed, info.notes (caveats), info.benign_hidden
```

`full` without an installed tap still answers, from the registry and the live
state, but says so in `info.notes` — a clean result then means "nothing I could
see", and overwritten mappings are invisible.

Commands (put `keymap.create_usercmd()` in **your own config**):

| command | |
| --- | --- |
| `:LibKeymapConflicts` | scope `registered` |
| `:LibKeymapConflicts!` | scope `full` |
| `:LibKeymapRuntime [defaults]` | Neovim's default mappings that were overridden or removed in this session |
| `:LibKeymapRuntime duplicates` | one action on several keys (by description or target) — candidates only |

### The tap: `keymap.tap`

`require("lib.nvim.bindings.keymap.tap")` wraps the four `vim.api` keymap
functions and records every call that succeeded: mode, key, buffer, `desc`, and
the `file:line` it came from (`via = "lib" | "lazy" | "raw"`). It is **opt-in**:
requiring lib.nvim never installs it.

```lua
local tap = require("lib.nvim.bindings.keymap.tap")
tap.install()        -- idempotent; true when this call installed it
tap.collisions()     -- Lib.Keymap.Conflict[]  (claimants carry source/via, `benign` is set when it is a placeholder)
tap.log()            -- the raw events;  tap.clear()  forgets them
tap.uninstall()      -- restores the originals
```

**It has to be installed before the plugins bind their keys.** Calls made
earlier are not in the recording, and a plugin that cached
`vim.api.nvim_set_keymap` in a local before `install()` is not seen at all.
From the command line, before any config runs:

```sh
nvim --cmd "lua require('lib.nvim.bindings.keymap.tap').install()"
```

(with lib.nvim already on the `runtimepath`, e.g. through a `--cmd "set rtp+=…"` first),
or as the first lines of `init.lua`.

Only the `vim.api` level is wrapped. `vim.keymap.set` ends in exactly these
calls, so wrapping both would count every binding twice, and wrapping the lower
level also catches a `vim.keymap.set` that was cached in a local earlier.
Errors of the original (an invalid mode, a missing mapping) come out unchanged,
and nothing is recorded for a call that failed.

What is a collision: the same key (compared through Neovim's own canonical
spelling, so `<M-h>` = `<A-h>` and `<C-K>` = `<C-k>`) bound twice in the same
mode and buffer scope with no deletion in between. What is not:

- a `del` between the two bindings — that is a re-bind;
- the same call site binding the same thing again (a `FileType` autocmd firing
  twice, a `:source`) — a re-bind;
- a buffer-local and a global mapping, or two buffers — different scopes;
- lazy.nvim's own mapping for a `keys` entry followed by the plugin's mapping
  with the same description (a `plugin: ` prefix is ignored). lazy binds a
  placeholder, **deletes** it before loading the plugin, binds the real mapping,
  and the plugin then binds its own, so only a run that *starts right after a
  deletion* qualifies: reported with `benign = "lazy-stub"`, and left out of
  `conflicts({ scope = "full" })` unless `opts.benign` is set (counted in
  `info.benign_hidden`). A placeholder that is overwritten without lazy having
  deleted it is **not** benign, however alike the descriptions are: it is dead,
  and the plugin it stands for is never lazy-loaded through that key.

The source of a binding is the first frame after lib.nvim's own keymap frames
(for a plain `vim.keymap.set`, the first outside Neovim's). Instrumentation that
wraps a function and calls it on -- a telemetry hook around `register` -- would
be named as the caller of everything; list its file in `tap.skip` (Lua patterns
on the forward-slash path, empty by default) and the tap looks past it:

```lua
tap.skip = { "/runtime%-analysis%.nvim/lua/runtime%-analysis/telemetry/" }
```

The recording stops at `tap.max_events` (default 50000, about 25 MB; a long
session binds buffer-local maps on every attach). `tap.truncated()` says so, and
`conflicts({ scope = "full" })` adds a note: a clean answer after that proves
nothing. `tap.clear()` lets it grow again.

### The live image: `keymap.runtime`

`require("lib.nvim.bindings.keymap.runtime")`:

| function | |
| --- | --- |
| `snapshot(opts)` | every effective mapping of n, x, s, o, i, c, t, l: mode, key, `rhs` / callback, `desc`, `sid`/`lnum`, `source` (file of the script that set it), `origin` (`builtin` = Neovim's defaults — by script id, or by content against the cached pristine list on a build that does not stamp them; `lib` = lib.nvim's registry; `other`); `opts.buffers = true` adds loaded buffers. With the tap installed, `source`/`lnum` are the recorded call site (`source_from = "tap"`, plus `via`) — only when the tap's last event for the key matches the live mapping (`desc`, string or function), so a mapping bound while the tap was not recording keeps its script stamp |
| `pristine_defaults(opts)` | the defaults of a clean `nvim --clean` child, cached per Neovim version under `stdpath("cache")`; `nil, err` when the child cannot run (never raises, never notifies) |
| `diff_defaults(pristine, live)` | `{ overridden, removed, unchanged }`: a default bound to something else now, or not bound at all (deleted, or set to `false` in a plugin's spec) |
| `action_duplicates(live)` | candidates for one action on several keys: same normalized description (`[plugin] ` and `plugin: ` prefixes dropped) or same string target in one mode; `<Nop>` and Neovim's own defaults are skipped |

### What none of this covers

- Neovim's **built-in Normal-mode commands** (`dd`, `<C-w>`, `gg`, …) are not
  mappings. They are neither listed nor compared: `nvim_get_keymap()` does not
  know them, and neither does this.
- A mapping overwritten **before the tap was installed**.
- Mappings made with **Ex commands** (`:nnoremap`, `:nunmap`, `:nmapclear`,
  `mapset()`): a Vimscript plugin is invisible to the tap, and an `:nunmap`
  between two lua bindings is not seen as the re-bind it is.
- Keys that Neovim 0.12 keeps in **separate slots** although a terminal sends the
  same byte (`<Tab>`/`<C-i>`, `<CR>`/`<C-m>`, `<Esc>`/`<C-[>`, `<C-@>`/`<Nul>`):
  they are compared as one key, so the tap may call "overwritten" what Neovim
  holds as two live mappings.
- Two bindings from **the same call site** with the same description whose
  functions are closures over different values (`bind(make(1)); bind(make(2))`
  on one key) count as a re-bind: a function is identified by where it is
  defined, because that is what a `FileType` autocmd firing again produces too,
  and the two cannot be told apart without comparing upvalues.
- A call site that is a helper of your own config (`local function map(...)`)
  is named as the source of everything bound through it; add its file to
  `tap.skip`.
- The error position of a failed call carries one more `file:line` than without
  the tap when the function underneath is itself a Lua function that raises
  with a position (cosmetic; the message and the type stay the same).
- Buffer-local mappings of buffers that are **not loaded**.
- `action_duplicates` is a list of candidates; two keys for one action is often
  intended.
