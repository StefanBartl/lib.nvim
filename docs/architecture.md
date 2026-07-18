# Design

The library is split by responsibility into three namespaces:

| Namespace    | Purpose                                                      | `vim` API |
| ------------ | ----------------------------------------------------------- | --------- |
| `lib.lua.*`  | General, **editor-independent** Lua helpers                 | no        |
| `lib.nvim.*` | **Neovim-specific** helpers (adapters onto the `vim` API)   | yes       |
| `lib.vim.*`  | Optional **classic-Vim** implementations, API-compatible    | `vim.fn`  |

**Guiding rule:** anything that does not need the `vim` API belongs in `lib.lua.*`. `lib.nvim.*` is merely an adapter onto Neovim. `lib.vim.*` mirrors `lib.nvim.*` with a compatible signature for classic Vim where feasible.

This keeps the generic parts independently testable and reusable, and they can later move into a dedicated `lib.lua` repository.

See also: [Namespaces & modules](modules.md) for the full module reference, and [Conventions](conventions.md) for the per-module documentation rules that keep this structure consistent.
