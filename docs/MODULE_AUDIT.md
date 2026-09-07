# Module audit (docs / @types / aggregator wiring / feature ideas)

Working checklist for a full pass over every top-level `lib.nvim.*` module
(granularity: the namespace tables in [modules.md](modules.md)). For each
module, verify against [conventions.md](conventions.md):

- [ ] `README.md` present and matches the actual exported API (no stale
      function names/signatures, no missing exports)
- [ ] `@types/` has proper `@class`/`@alias` defs (not inline in source),
      and the types match what the code actually returns/accepts
- [ ] Wired into [modules.md](modules.md): namespace table row +
      per-module-doc bullet (if it has a README)
- [ ] `doc/lib.nvim-<module>.txt` + hub line in `doc/lib.nvim.txt` (only for
      `:help`-worthy modules — not every module needs this)
- [ ] Feature idea check: "fehlt etwas Sinnvolles?" — noted below regardless
      of whether it gets built

Status legend: ⬜ not started · 🔎 in progress · ✅ audited (fixes applied or
nothing to fix) · 💡 has open feature idea(s) not yet acted on

Source-of-truth inventory (init/README/@types presence, `lua_files` = total
`.lua` count including submodules) taken 2026-09-07:

| Module | init.lua | README | @types | notes |
|---|---|---|---|---|
| async | Y | Y | 1 | |
| bindings | Y | Y | 0 (nested have own) | huge (34 files) |
| buf_win_tab | - (leaf-only) | - | 4 (nested) | documented exception? verify |
| buffer | - (leaf-only) | - | 1 (nested) | documented exception, see modules.md:34 |
| cache | Y | Y | 1 | |
| contextmenu | Y | Y | 1 | |
| core | Y | Y | 1 | |
| count | Y | Y | 1 | |
| cross | Y | Y | 5 (nested) | huge (42 files) |
| debounce | Y | Y | 1 | |
| deps | Y | Y | 1 | |
| dev | - (leaf-only) | Y | 0 | |
| dotrepeat | Y | Y | 1 | |
| frecency | Y | Y | 1 | |
| fs | - (leaf-only) | - | 5 (nested) | huge (52 files) |
| git | Y | Y | 1 | |
| harvest | Y | Y | 1 | |
| health | Y | Y | 1 | |
| image_preview | Y | - | 0 | no README at all |
| json | Y | Y | 1 | |
| lastcmd | Y | Y | 1 | |
| logger | Y | Y | 1 | |
| lua_ls | - (leaf-only) | - | 1 (nested) | |
| markdown | - (leaf-only) | - | 0 | |
| neotree | - (leaf-only) | - | 0 | |
| net | - (leaf-only) | - | 0 | |
| normalize | Y | Y | 4 (nested) | |
| notify | Y | Y | 1 | |
| progress | Y | Y | 1 | |
| require | Y | Y | 1 | |
| safe_api | Y | Y | 1 | |
| selection | Y | Y | 1 | |
| store | Y | Y | 1 | |
| system | Y | Y | 1 | |
| terminal | Y | Y | 1 | |
| token | Y | Y | 1 | |
| treesitter | - (leaf-only) | - | 0 | |
| ui | - (leaf-only) | - | 1 (nested) | huge (29 files) |
| window | Y | Y | 1 | |

Plus `lib.lua.*` namespace (tables, strings, functions, time, json, memo,
lazy, class, context_manager) — not yet inventoried, add before closing out.

## Per-module log

(One entry per module as it's actually reviewed — status, what was checked,
fixes made, feature ideas raised. Filled in as the sweep proceeds; this
section is the actual record, the table above is just the starting map.)

### core — ✅ (partial: aggregator doc bug found & fixed)

- Found: [`lua/lib/nvim/init.lua`](../lua/lib/nvim/init.lua) docstring claimed
  `Nvim.map == require("lib.nvim.bindings.keymap")` and similar — wrong. The
  `lib.nvim` aggregator is a straight 1:1 metatable (`require("lib.nvim." ..
  key)`); the flattened short names (`map`, `usercmd`, `notify`, ...) only
  exist on the *top-level* `require("lib")` aggregator
  ([`lib/strategies/metatable.lua`](../lua/lib/strategies/metatable.lua)).
  Fixed the docstring to stop claiming a shortcut that doesn't exist and
  point at `require("lib").map` instead.
- Still to check: `lib/nvim/core` module itself (has_exec, simple_echo)
  README/@types accuracy.
