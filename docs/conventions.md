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
