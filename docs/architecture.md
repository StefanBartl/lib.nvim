# Design

The library is split by responsibility into two namespaces:

| Namespace    | Purpose                                                      | `vim` API |
| ------------ | ----------------------------------------------------------- | --------- |
| `lib.lua.*`  | General, **editor-independent** Lua helpers                 | no        |
| `lib.nvim.*` | **Neovim-specific** helpers (adapters onto the `vim` API)   | yes       |

**Guiding rule:** anything that does not need the `vim` API belongs in `lib.lua.*`. `lib.nvim.*` is merely an adapter onto Neovim. (A third namespace, `lib.vim.*`, once targeted classic-Vim-compatible stubs — rejected and removed 2026-08-14: the real scope was ~174 modules against a Neovim-only consumer base.)

This keeps the generic parts independently testable and reusable, and they can later move into a dedicated `lib.lua` repository.

See also: [Namespaces & modules](modules.md) for the full module reference, and [Conventions](conventions.md) for the per-module documentation rules that keep this structure consistent.
