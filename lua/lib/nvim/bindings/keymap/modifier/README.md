# `lib.nvim.bindings.keymap.modifier`

Modifier keys that run *another* mapping and capture its result.

> **Experimental, and off until you ask for it.** `\` is a key people bind, so
> the library does not take it just for being on the runtimepath.

```lua
require("lib.nvim.bindings.keymap.modifier").setup({ experimental = true })
```

| Press | Effect |
| --- | --- |
| `\[a` | run `[a`, put its result on the clipboard |
| `\\[a` | run `[a`, put its result on the clipboard **and** insert it at the cursor |

Nothing is wrapped and nothing has to cooperate. The modifier reads the keys
that follow it, resolves them against the keymap table itself, and runs what it
finds. Buffer-local mappings resolve too — which is the point, since the
interesting targets (a file tree's "yank path" family) are exactly that.

## The problem: mappings have no result

Vim discards what a Lua rhs returns. `expr` mappings are the one exception, and
there the return value is a *key sequence*, not data. Wrapping every mapping
does not fix this — the wrapped function still returns nothing.

So the result is resolved in tiers, and the useful one is the tier that needs
no cooperation at all:

| Tier | Source | Cooperation |
| --- | --- | --- |
| 1 `declared` | someone called `declare()` for this lhs | once, per action |
| 2 `returned` | the mapping's callback handed back a string | the mapping must `return` |
| 3 `observed` | a register moved while the mapping ran | **none** |
| 4 `none` | nothing produced a string — say so, don't invent one | — |

**Tier 3 is why this works on plugins you did not write.** Anything that
already copies its result to the clipboard is, by construction, readable: take
a register snapshot, run the mapping, diff. `+`, `*`, `"` and `0` are watched,
in that order.

Tier 4 is a contract, not a failure: `\` on a mapping that only edits the
buffer runs it normally and reports that there was nothing to copy.

`expr` mappings are fed as keys rather than called, so their return value is
never mistaken for a result.

## Insert into what?

The insert modifier puts the result at the cursor when the current buffer takes
text. When it does not — a file tree, a terminal, any scratch surface, which is
the *normal* case for these targets — it asks which open buffer and which line,
through `vim.ui.select` / `vim.ui.input`, so whatever picker you already have is
the one you get.

## Options

```lua
modifier.setup({
  experimental = true,   -- required opt-in; false tears it back down
  copy         = "\\",   -- default
  insert       = "\\\\", -- default
})
```

`\` is free in any config that sets its own `mapleader` — it is Vim's *default*
leader, so nothing builtin is lost. The second modifier is `\\` rather than `?`
on purpose: `?` is the backwards search, and giving up a builtin to gain a
modifier is a bad trade when one reserved prefix can hold the whole family. The
only cost is that `\\` waits `timeoutlen`; plain `\` does not.

## Declaring a result

For a target that neither returns its result nor moves a register:

```lua
modifier.declare("n", "[a", function()
  return require("filetree.nvim").node_path()
end)
```

The mapping is run first; the function is called afterwards only to read the
result out, so it must be pure.

## API

| | |
| --- | --- |
| `setup(opts?)` | Bind the modifiers. Returns whether anything is bound. |
| `teardown()` | Unbind them. |
| `keys()` | `{ copy = lhs\|nil, insert = lhs\|nil }`. |
| `declare(mode, lhs, fn)` | Tier 1 producer for one mapping. |
| `undeclare(mode, lhs)` | Drop it. |

## Known limits

- **Normal mode only.** Visual-mode targets are not resolved yet; what "the
  result of a Visual mapping" should even mean is undecided.
- **No count.** `\3[a` is not passed through to the target.
- **Tier 3 picks one register.** A mapping that moves several gets the first
  match in `+`, `*`, `"`, `0` order.
- **Ambiguity is Vim's.** `\` and `\\` share a prefix, so `\\` waits for
  `timeoutlen` like any other prefix pair.
