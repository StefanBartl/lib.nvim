# Conventions

- One module per directory with `init.lua`; module path == directory path.
- `---@module 'lib.<namespace>.<path>'` as the first line of every file.
- LuaLS type definitions (`@class`, `@alias`, standalone `@type`) live in `@types/` files, never inline in the source module.
- Internal (non-public) modules are prefixed with `_` or live under `internal/`; everything else is part of the public API.

## Documenting a new module

Two-tier docs, three steps — keep it mechanical so it stays easy to extend:

1. Add a per-module `README.md` next to the source (the detailed function reference).
2. For `:help`-worthy modules, add `doc/lib.nvim-<module>.txt` tagged `*lib.nvim-<module>*` (and `*lib.nvim-<module>-<fn>*` per function).
3. Wire it into the indexes: one row in the [namespace tables](modules.md#namespaces--modules) + a bullet under [Per-module documentation](modules.md#per-module-documentation), and — for help files — one `|lib.nvim-<module>|` line in the `doc/lib.nvim.txt` hub (`*lib.nvim-modules*` section).

## Cache-only vs. live-fallback resolvers: `resolve_*` naming

A recurring shape across resolver-like modules (path-to-context lookups,
project detection, anything that can answer either from a cheap cache or a
more expensive live check): three tiers, named consistently so a caller can
tell what they're getting without reading the implementation.

- `resolve_cached(...)` — cache-only, synchronous, never touches disk/IO
  beyond an in-memory (or already-loaded) cache; returns `nil`/low
  confidence on a miss rather than blocking to fill it.
- `resolve_sync(...)` — synchronous, may block on IO if the cache misses
  (fill-on-miss).
- `resolve_async(...)` — same as `resolve_sync`, but callback/`lib.nvim.async`-based
  so a cache miss never blocks the main loop.

Where the result's reliability varies by tier (a cached value can be stale
in a way a live check isn't), return a `confidence` alongside the value —
e.g. `{ value = ..., confidence = "cached"|"live" }` — rather than making
the caller infer it from which function they called.

Not every resolver needs all three tiers; add the ones a module actually
has callers for (rule of three still applies to the *tiers*, not just to
extracting the module in the first place). The point of this convention is
naming, not mandating a specific set of functions.

## Returned error strings carry no source position

A message that reaches a caller as a **value** — the `err` half of a
`(value, err)` pair, or an error re-raised on someone else's behalf — must
not carry Lua's `file:line:` stamp.

`error(msg)` defaults to level 1, which prefixes `msg` with the raising
file's path and line. That is right for a *crash* (a programmer error, where
the position is the point) and wrong for a message a consumer will forward
into a user-facing notification, where it reads like a plugin crash, names a
file the user cannot act on, and leaks the developer's filesystem layout:

```
[data] JSON decode failed: E:\repos\lib.nvim/lua/lib/nvim/json/init.lua:43: max nesting depth (64) exceeded
```

So:

- **Raising a message meant to be returned** — `error(msg, 0)`. Level 0
  suppresses the position entirely. This is the fix, because it stops the
  prefix being created at all. See `lib.nvim.json`'s depth guard, and
  `lib.lua.functions.meta.raise`.
- **Re-raising someone else's error** — `error(err, 0)` too. `err` already
  carries whatever position it was raised with; level 1 would stamp a second
  one in front and blame the forwarding helper. See
  `lib.nvim.neotree.watch.with_release`.
- **A genuine crash** (invalid argument, unknown key, a broken invariant) —
  keep the position. Use level 2 to blame the caller rather than the
  validator; `lib.lua.time.diff` and `lib.lua.memo` do this throughout.

Do **not** strip the prefix afterwards with a pattern on the consuming side.
Such a pattern has to guess which `:` starts a position stamp, and a Windows
path (`E:\repos\...`) contains one of its own; anchoring on `:%d+:` narrows
but does not close the gap, because a legitimate message may quote a path or
position from user data. Errors that come from outside Lua (`vim.json.decode`
fails in C) have no prefix to begin with, so there is nothing for a stripper
to do but undo damage lib.nvim inflicted on itself.

**The one exception** is a failure to *start a process*: `vim.system` raises
(with level 1, from Neovim's own `vim/_core/system.lua`) when `cmd[1]` cannot be
spawned, so the reason arrives as `vim/_core/system.lua:324: ENOENT: …` — a stamp
this library did not create and cannot ask to be suppressed. `lib.nvim.git`
removes exactly that one leading stamp, once, and only where the failure is a
spawn failure (exit code `-1`), and only if it points into Neovim's runtime
(`vim/….lua:N: `, or `vim/…:N: ` on a build that embeds the runtime): a message
that merely quotes some other `file.lua:12:` from the command, or a path such as
`E:/work/vim/foo:12: x`, is left alone. That is why the guard is anchored at the very
front of the message on `vim/` rather than on `:%d+:` alone.

Pin the behaviour in the spec: assert the actionable text is present *and*
that `%.lua:%d+:` is absent (or, for a re-raise, occurs exactly once).

## `status()`: statusline component vs. state snapshot

`status` is a name two kinds of function use across the plugins, and they must not be confused (checked
against the tree on 2026-10-16):

| kind | where | returns | examples |
| ---- | ----- | ------- | -------- |
| **Statusline component** | `require("<plugin>.statusline").status(buf?)` | a short **string** | `casedesk`, `github_stats`, `gitsuite`, `recommender`, `runtime-analysis`, `sandbox` (all in a `statusline` module); `diff.nvim` is the one that exposes it as `require("diff").status(opts)` |
| **State snapshot** | `require("<plugin>").status()` | a **table** (or lines) for `:checkhealth`, `:<Cmd> status` and bug reports | `lsp.nvim`, `hover.nvim`, `terminal.nvim`, `lib.nvim.messages.status()` |

So `plugin.status()` is **not** one plugin-wide statusline convention: a top-level `status()` is a snapshot
unless the plugin documents otherwise. A new statusline component goes in a `statusline` module and follows
the component contract:

- returns a `string`, `""` when there is nothing worth showing (inactive, no file, any failure) -- a badge with
  nothing to act on is clutter, and a statusline cannot tell the two empty cases apart anyway;
- takes an optional buffer (`buf`, default the current one) so a window-local statusline can ask for its own;
- never raises and never blocks: it runs on every redraw. Cache per buffer (`changedtick`) or with a TTL, and
  swallow errors into `""`;
- is cheap to call unconditionally (`%{v:lua.require'<plugin>.statusline'.status()}`).

A plugin that needs both keeps them apart: `statusline.status()` for the string, `status()` for the snapshot.
