# Lua/Neovim Checklist — applied to lib.nvim

Audit against
[`Checklist.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Checklist.md).
✅ good · 🟡 partial · ❌ gap · ➖ N/A for this repo.

## Schnell-Check (10 Punkte, vor jedem Merge) — mostly ✅
- Fehlerbehandlung (pcall/wrapper) — 🟡 present at the boundaries that need it
  (usercmd callbacks, health, neotree-state access), not a blanket rule (see
  [Arch&Coding.md](Arch&Coding.md) §1).
- Type Guards — ✅ (`lib.nvim.map` validates modes/lhs/rhs/buffer types before
  calling `vim.keymap.set`; `lib.nvim.normalize.validators` is entirely built
  from type-guarded coercions).
- Buffer/Window validieren — ✅ (`*_is_valid(` in 19 files).
- Keine globalen States — ✅ (no `_G.*` anywhere).
- Single Responsibility — ✅ (one concern per module dir).
- UI-Cleanup — ✅ (`window.nice_quit`, `close_on_focus_lost`).
- Performance-Hotspots — ✅ (`table.concat`-based string helpers, `t[i]`-style
  array building in `neotree.node`, no `..`-in-loop patterns found).
- Annotationen vollständig — ✅ (210/211 files have `@module`; see
  [Arch&Coding.md](Arch&Coding.md) §5).
- Testbarkeit — 🟡 (pure-by-design `lib.lua.*`, but no automated suite; see
  [Arch&Coding.md](Arch&Coding.md) §6).
- Import-Reihenfolge — ✅ (System/vim → notify → utils, consistently; modules
  don't have UI/state/controller layers to order).

### Bonuspunkt: Custom `lib`-Modul nutzen — ➖
Self-referential for lib.nvim (it *is* the module). N/A.

## PR-Review-Checkliste (Detail) — ✅ / 🟡
Sections 1–4 (Sicherheit, Modularität, Buffer/Window, UI-State) covered by
the Arch&Coding audit above. *Config* sub-item ("`/config` mit
`/config/DEFAULTS.lua`") — ✅ now satisfied (`lua/lib/config/init.lua` +
`lua/lib/config/DEFAULTS.lua`, split this session). Section 5 (Docs) — ✅.
Section 6 (Testbarkeit) — 🟡, same gap as above. Section 7 (Tooling) — ✅
`.luarc.json` present at repo root; `.stylua.toml` present; no `luacheck`/CI
lint pipeline configured — 🟡 minor gap, not blocking.

## Coding-Checkliste (beim Implementieren) — ✅
Cached `require` locals, guard clauses, consistent `M`-table module shape are
the norm throughout (see [Arch&Coding.md](Arch&Coding.md) "Annotations-/
Import-Regeln"). The "WICHTIG: use lib.nvim" preamble is ➖ self-referential.
Functional-programming / streaming-transform subsection (Dateiverarbeitung,
Netzwerk, Kompression, ETL, …) is ➖ reference material — lib.nvim is a
synchronous editor-helper library, not a data-pipeline tool.

### A. Strings und Tabellen — ✅
No string concatenation in loops found; array-building uses `t[#t+1] = v`
(fast path) over `table.insert` in the hot spots checked
(`neotree.node.collect_nodes`/`extract_paths`).

### B. Performance-Quickwins — ✅
`require` results are cached in locals at module top; `vim.fn`/`vim.api` are
not over-aliased (used directly, per the rule's own guidance that aliasing
`vim.fn` doesn't help). No blocking I/O found in hot paths; `lib.nvim.cross.uv`
wraps `vim.uv` spawn calls for async subprocess use.

### C. Neovim-API sicher verwenden — ✅
Same evidence as the Schnell-Check buffer/window row.

### D. State- und Datenmodelle — ✅
`lib.config` exposes `get()`/`setup()` (getter/setter, not direct field
access from consumers); no FIFO/ring-buffer need identified for a stateless
helper library.

### E. Garbage-Collector bewusst steuern — ➖
No large-object churn pattern in this codebase that would call for explicit
`collectgarbage()` tuning. N/A.

### F. Lazy-Loading und On-Demand-Konfiguration — ✅
This is essentially what `lib.strategies.metatable` implements natively (a
per-key proxy that loads a submodule on first access) — the checklist's
described technique is already the library's default aggregator strategy.

## Architektur-Checkliste — ✅
Clear layering (`lib.lua.*` editor-independent / `lib.nvim.*` Neovim adapters
/ `lib.vim.*` classic-Vim parity), low coupling (no cross-namespace reach-ins
observed), explicit strategy-based extensibility for the one thing that needs
it (aggregator loading). Testability is the one open item (see above).

### C/C++ nativen Quellcode — ➖
No FFI/native-array use case in this codebase. N/A.

## Anti-Pattern-Check — ✅
No global mutable state; no unguarded `vim.api` calls in the paths checked;
no string-concat-in-loop found; no closures-in-loop pattern spotted in the
modules read. Many small temporary tables are created per-call
(`normalize.validators`, `neotree.node`) but at call-frequency low enough
that pooling would be premature optimization for a library, not a hot loop.

## Import- und Dateistruktur-Check — ✅
Import ordering (System/Kern → Debug/Notify → Utils) holds; file headers
(`@module`) present almost everywhere (see gap above); `@types/`-Ordner used
project-wide (39 dirs) exactly as prescribed.

## Performance-Spickzettel (zum Abhaken bei Hotpaths) — ✅ (spot-checked)
`t[i]`-style array fill and `table.concat`-based string joins are used where
it matters; weak-caches are deliberately *not* used (see
[Arch&Coding.md](Arch&Coding.md) §8 — `memo.lru` is a bounded LRU instead, a
stronger guarantee than a weak-table cache for a library whose consumers
can't tune GC behavior). No debounced-write need identified (no persistent
state written by lib.nvim itself).

## Sortier-/Datenstruktur-/Bitoperationen-/Komplexitäts-Abschnitte — ➖
Reference material; lib.nvim is not an algorithms library and has no
custom sort/search/insert/delete hot loops or bit-trick code paths to audit
against this section.

## Concentrated action items
Same as [Arch&Coding.md](Arch&Coding.md#concentrated-action-items):
missing `@module` tag, recursive `fs` collector candidate, the Neo-tree-
coupled window helper, and the still-open automated-test gap. Additionally
from this pass: no lint/CI pipeline (`luacheck`) configured yet — minor,
`.stylua.toml` covers formatting already.
