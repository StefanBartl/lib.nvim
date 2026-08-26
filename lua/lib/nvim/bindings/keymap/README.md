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
`opts.buffer = true` is normalised to buffer `0` (the current one). Wrong
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

`preset = false` (or `enable = false`) binds nothing, but the actions are still
**recorded** — the health check and the generated docs want to know what
exists, not only what is currently bound.

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

## which-key

**which-key needs no registration to show these mappings.** It reads
`nvim_get_keymap` itself and labels each mapping with its own `desc`
(`which-key/buf.lua`), and `register` always sets a `desc`. A `which_key = true`
switch would therefore do nothing at all; there isn't one.

Three things *are* outside what which-key can infer:

| | how |
| --- | --- |
| **Group label** for a prefix | `which_key = { group = "Spotlight" }` next to `prefix` |
| **Icon** | `which_key = { icon = "" }`, per action or on the prefix |
| **Hiding** one mapping | `which_key = false` on the action |

A table implies "yes" — there is no separate `true` to remember. Hiding works
even without which-key installed: it sets which-key's own `which_key_ignore`
description on the mapping rather than calling into the plugin.

`desc` is deliberately **not** sent to which-key: it already has it from the
mapping, and a second copy is how the two get to disagree. (Four plugins here
used to register descriptions that their mappings already carried.)

which-key is a soft dependency throughout — nothing loads it eagerly, and the
call is `pcall`ed, because a wrong label is never worth taking a plugin's
`setup()` down with it.

## Reading the registry back

```lua
keymap.registered()            -- every plugin's actions
keymap.registered("spotlight") -- one plugin's
keymap.conflicts()             -- lhs values claimed by more than one plugin
```

This is what makes it a registry rather than a binder. The same list is what a
`:checkhealth` section, a generated bindings page, and a "is every action also
reachable as a user command?" audit each need — and each of them re-deriving it
from source is how those drift apart.

`conflicts()` is deliberately *not* checked during registration: a plugin
cannot know what a later one will bind, so the answer is only meaningful once
everything has loaded.
