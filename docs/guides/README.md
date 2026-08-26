# Guides

Essay-style problem → solution write-ups, one per topic. Each came out of a
specific ecosystem-wide finding — a bug or a platform behaviour several
plugins hit independently, which lib.nvim then absorbed so nobody has to
re-solve it.

| Guide | The finding |
| --- | --- |
| [subprocess-env.md](subprocess-env.md) | A subprocess started from Neovim inherits *Neovim's* environment, not a login shell's: incomplete `PATH`, unreachable OS keyring. `lib.nvim.cross.run.env` builds the completed one, and `cross.run` applies it by default. |
| [async-directory-walk.md](async-directory-walk.md) | Recursive scans block the main loop on a large tree. Coroutine-driven `*_async` counterparts fix that without a callback pyramid or a general async framework. |

These sit here rather than in [`../FEATURES/`](../FEATURES/README.md) because
they are not theme files: the parser behind the Features tab reads every `##`
as a feature, and an essay's own `The problem` / `The solution` / `Adoption`
structure was being counted as eleven features that do not exist. Both topics
*are* in the catalogue, as one entry each —
[FILESYSTEM.md](../FEATURES/FILESYSTEM.md#recursive-directory-walking--sync-and-async)
and
[CROSS_PLATFORM.md](../FEATURES/CROSS_PLATFORM.md#completed-subprocess-environment)
— and each links back here for the long version.
