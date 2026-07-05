# Architektur- & Codierungsrichtlinien — applied to lib.nvim

Audit against
[`Arch&Coding-Regeln.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md).
✅ good · 🟡 partial · ❌ gap · ➖ N/A for this repo.

> lib.nvim **is** the `lib.*` helper library the other checklists tell every
> other repo to depend on. Its "NVIM-Config spezifisch" section (§241) and the
> "WICHTIG: benutze `lib.nvim`" preambles are therefore self-referential here
> and marked ➖ throughout — lib.nvim cannot depend on itself.

## 1. Sicherheitsprinzipien & Fehlerbehandlung — ✅ / 🟡
`pcall` used at 32/211 files (72 call sites), concentrated where it matters:
external Neo-tree state access (`lib.nvim.neotree.node`), health checks
(`lib.health`), user-command callbacks (`lib.nvim.usercmd` wraps every
callback in `pcall` and reports via `notify.error`). No `_G.*` usage anywhere.
*Gap:* not every `vim.api.nvim_*` call site is guarded — acceptable for a
library where callers are expected to pass valid handles, but worth spot-
checking the newer modules (`system`, `buf_win_tab/capture`) as they grow.

## 2. Modularisierung & Strukturprinzipien — ✅
One responsibility per directory, `init.lua` = module entry (113 module
dirs), internal helpers stay local (e.g. `lib.nvim.map`'s `notify_caller` is
file-local). No global state. Aggregator strategies
(`lib.strategies.{metatable,lazy,eager}`) are a clean Strategy-pattern
application for the one real architectural choice (`require("lib")` loading
behavior).

## 3. Buffer- & Window-Management — ✅
`*_is_valid(` guards appear in 19 files, exactly where buffer/window handles
are produced or consumed (`window/*.lua`, `buf_win_tab/*`,
`ui/hover_select/*`, `git/init.lua`, `neotree/node`). Handles are bound to
locals first, then checked, matching the rule.

## 4. Methoden, Metatables & Datenmodelle — ✅
Metatables used deliberately, not by default: `lib.lua.memo.lru` (`Lru.__index
= Lru`) for the LRU node type, `lib.lua.lazy` for its proxy object. No
speculative metatable use elsewhere.

## 5. Dokumentation & Annotationen — ✅
211/211 Lua files carry `---@module`
(`lua/lib/nvim/cross/uv/spawn_shell_command.lua` was the one miss; fixed).
Every module directory with meaningful public surface has a matching
`@types/` subfolder (39 `@types` dirs) — types live out of the source, per
the rule. Two-tier docs (per-module `README.md` + `doc/lib.nvim-<module>.txt`
for `:help`-worthy modules) are already the repo's documented convention
(see main `README.md` → "Documenting a new module").

## 6. Testbarkeit & Lesbarkeit — 🟡
Functions are small and mostly pure where feasible (`lib.lua.*` namespace is
side-effect-free by design). *Gap:* the only test-like artifact is
`lua/lib/nvim/ui/hover_select/test_multiselect.lua` — manually-invoked
(`run_all()`), not an automated/headless suite, and not wired into CI or
`:checkhealth`. No `docs/TESTS/**` yet (tracked, intentionally deferred this
round — see `README.md` session history).

## 7. Fehlerbehandlung & Validierung (Sicherheit) — 🟡
No dedicated `safe_call(fn, args)` wrapper or structured error-type
convention (`InvalidStateError`-style tags) exists yet; error handling is
ad-hoc `pcall` + `notify.error(...)` per call site (consistent, but not a
named, reusable pattern). *Action:* if this recurs enough, a small
`lib.lua.functions.safe_call` would formalize it — not urgent, current call
sites are already consistent.

## 8. Performance & Speicher — ✅ / 🟡
`lib.lua.tables` explicitly separates array/dict/set/functional/safe/unique
concerns; `lib.lua.memo.lru` is an O(1) hashmap + doubly-linked-list LRU with
a fixed capacity — a **deliberate** choice over `__mode`-weak-table caching
(predictable eviction, no GC-timing dependency), not a gap. *Action:* no
weak-table usage exists anywhere in the repo; fine as long as every cache
stays capacity-bounded like `memo.lru` — flag it if an unbounded table-based
cache ever gets added.

## 9. Cache hitting — ➖
No query/tool cache concept applies to a helper library (this principle
targets stateful tools like live-grep). N/A.

## 10. Schwache Tabellen & Memoisierung — ✅
Covered by `lib.lua.memo` (see §8). No shared-metatable-with-memoization
pattern needed beyond what `lru.lua` / `lazy.lua` already provide.

## 11. Spezialfälle — ➖
Dual-representation / FIFO-history patterns are consumer concerns, not
something a generic helper library should impose. N/A.

## MISC — ✅
Cross-platform is a first-class concern here, not an afterthought:
`lib.nvim.cross.platform.is_{windows,linux,macos,wsl}`, `lib.nvim.cross.fs`,
`lib.nvim.cross.uv.*`, plus `lib.vim.*` as an explicit classic-Vim parity
layer (`doc/vim-parity.md`). This is the strongest section of the audit.

## NVIM-Config spezifisch — ➖
Self-referential (see note above): lib.nvim *is* this library for every
other repo, so it cannot "use lib.nvim". N/A by construction.

## Annotations- / Import-Regeln — ✅
`@types/` folders per module, consistent `---@module`/`---@param`/`---@return`
coverage, `require(...)` results cached in top-level locals
(`local notify = require("lib.nvim.notify")...`) rather than repeated
`mod.fn()` lookups in hot call sites (e.g. `lib.nvim.map`, `lib.nvim.usercmd`).

## Tables / Strings / GC / CPU — ✅ (spot-checked)
No hot-loop string concatenation found in `lib.lua.strings` (`join`/`split`
delegate to `table.concat`/`string` patterns, not `..` accumulation).
`lib.nvim.neotree.node.collect_nodes`/`extract_paths` build result tables
with `t[#t+1] = v`, not `table.insert` in a loop — matches the recommended
fast-path pattern. `table.insert` still appears 69 times repo-wide; acceptable
outside genuine hot paths (the rule is about tight loops, not all inserts).

## Concentrated action items
1. ~~Add the missing `---@module` tag to `spawn_shell_command.lua`.~~ Done.
2. Consider a `lib.nvim.fs.collect_recursive` helper (see
   [NEOTREE_FEATURES.md](NEOTREE_FEATURES.md) — currently every consumer
   hand-rolls this).
3. ~~`lib.nvim.window.neotree.get_neotree_window` bakes in a Neo-tree-specific
   name/impl.~~ Done — replaced by generic
   `lib.nvim.window.find_by_filetype(filetype)`, which takes any filetype
   string instead of hardcoding `"neo-tree"`.
4. Tests remain the biggest structural gap (§6) — no automated suite exists;
   tracked as a deliberate, later addition.
