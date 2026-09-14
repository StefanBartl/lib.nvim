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
