# Zentrale Prinzipien — applied to lib.nvim

Audit of lib.nvim against
[`Zentrale-Prinzipien.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md).
Status: ✅ good · 🟡 partial / improvable · ❌ gap · ➖ N/A.

## lib.nvim usage (the "WICHTIG" preamble) — ➖

Self-referential: the preamble tells every *other* repo to depend on
`StefanBartl/lib.nvim`. lib.nvim is that library, so it cannot depend on
itself. The relevant question instead is whether lib.nvim's own modules
embody the equivalent principles internally — covered principle-by-principle
below.

## The 10 principles

**1. Events bündeln, Logik entkoppeln** — ➖
lib.nvim registers **no** autocmds of its own anywhere in the tree (it only
provides `lib.nvim.autocmd`/`lib.nvim.autocmd.augroup` as helpers *for
consumers* to do this correctly — see `lua/lib/nvim/autocmd/init.lua`,
`augroup.lua`). Nothing to bundle/decouple at the library level. N/A.

**2. Eigene Logik lazy laden** — ✅
This principle is lib.nvim's core architectural choice, not just followed:
`require("lib")`'s default `"metatable"` strategy
(`lua/lib/strategies/metatable.lua`) is a per-key proxy that loads a
submodule only on first access; `lib.lua.lazy` (`lua/lib/lua/lazy/init.lua`)
gives consumers the same primitive (`lazy.module(...)`, `lazy.fn(...)`) for
their own use. Direct `require("lib.nvim.notify")`-style paths remain
available and are the recommended tree-shake-friendly option per
`README.md`.

**3. Kontext statt Mehrfach-API-Zugriffe** — ✅
`lib.nvim.neotree.node.collect_nodes`/`extract_paths` resolve a node/path
once and pass it onward rather than re-querying `state.tree` repeatedly per
caller; `lib.config.get()` returns the resolved options table once instead of
re-reading fields ad hoc.

**4. Autocommand-Gruppen sauber nutzen** — ✅
`lib.nvim.autocmd.augroup.create.clear(name)` centralizes namespaced,
dedup'd augroup creation (`nvim_create_augroup(name, { clear = true })`) —
exactly the pattern this principle asks for, offered as reusable
infrastructure rather than hand-rolled per consumer.

**5. Event oder Command?** — ➖
No automatic (event-driven) behavior exists in lib.nvim itself — it is a pure
helper library invoked synchronously by callers. N/A at the library level;
this is a question for *consumers* of `lib.nvim.usercmd`/`autocmd`, not for
lib.nvim.

**6. Treesitter notwendig oder nicht?** — ➖
lib.nvim uses no Treesitter anywhere. N/A.

**7. Cache vorhanden und explizit?** — ✅
`lib.lua.memo` (`M.fn`/`M.memo.memoize`, backed by `lib.lua.memo.lru`) is an
explicit, capacity-bounded, invalidatable-by-construction cache (LRU eviction,
not silent weak-table decay) — regenerable and explicit, matching the
principle directly. It is opt-in (consumers call `memo.fn(...)`), not a
hidden cache inside library internals.

**8. Allokationen im Hot-Path vermeiden** — ✅
No loop-local table/closure allocation patterns found in the modules read
(`neotree.node`, `normalize.validators`, `strings.core`); array building uses
pre-indexed `t[#t+1] = v`, not accumulating closures. lib.nvim has no
`CursorMoved`/`TextChanged`-class hot paths of its own to audit (see
principle 10).

**9. Debugbarkeit eingeplant?** — ✅
`:checkhealth lib` (`lua/lib/health.lua`) reports Neovim version, configured
aggregator strategy, per-module load success/failure, and `lib.vim` parity
status — a clear, isolated way to see what's active and what's broken.
`lib.nvim.notify` centralizes user-facing diagnostics instead of scattered
`print`/`vim.notify` calls.

**10. Laufzeit wichtiger als Startup?** — ✅
lib.nvim registers no per-keystroke or per-event handlers at all (see
principles 1/5) — there is no runtime hot path to optimize away from at the
library level; the only "startup cost" is the aggregator resolution, and the
default strategy defers even that to first access.

## Summary

Most of these 10 principles are really aimed at *feature modules* that react
to editor events — lib.nvim is a passive helper library with no autocmds,
no Treesitter, and no hot-path event handlers of its own, so several
principles are structurally N/A rather than gaps. Where they do apply
(lazy-loading, context reuse, augroup hygiene, explicit caching,
debuggability) lib.nvim not only follows them but **is the infrastructure**
other repos are told to adopt for the same principles (see
[Checklist.md](Checklist.md) and [Arch&Coding.md](Arch&Coding.md)).
