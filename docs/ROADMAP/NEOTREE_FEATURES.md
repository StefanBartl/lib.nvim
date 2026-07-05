# lib.nvim features → filetree.nvim relevance map

**Purpose.** This is the inventory called for in `FINISH.md`: a sweep of
lib.nvim's own implemented features that are useful for a filetree/file-manager
plugin (Neo-tree, NvimTree, Netrw, Oil, mini.files, …) — so future
`filetree.nvim` work knows what already exists here, ready to consume
**cross-platform** and **filetree-manager agnostic**. It is the mirror image of
[`filetree.nvim/docs/ROADMAP/NEOTREE_FEATURES.md`](E:/repos/filetree.nvim/docs/ROADMAP/NEOTREE_FEATURES.md)
(that document audits the *old Neo-tree config* against filetree.nvim; this one
audits *lib.nvim* against filetree.nvim's category layout) and complements
[`filetree.nvim/docs/ROADMAP.md`](E:/repos/filetree.nvim/docs/ROADMAP.md)'s own
"lib.nvim adoption" section.

## How to read

- **Origin** — module path in lib.nvim (`lua/lib/...`).
- **filetree.nvim category** — the `features/<category>/` bucket the helper
  fits under (see filetree.nvim's registry: nav/ui/fileops/search/paths/git/
  lsp/compare/org/infra/system).
- **Status:** ✅ already consumed by filetree.nvim · 🟡 candidate (overlaps an
  existing filetree.nvim util, not yet migrated) · ❌ gap (no lib.nvim
  counterpart yet, would need to be added first) · ℹ️ informational finding.

---

## nav / infra — tree, buffer, window plumbing

| Feature | Origin | Category | Status |
|---|---|---|---|
| Neo-tree node under cursor / marked nodes / path resolution | `lib.nvim.neotree.node` (`get_current`, `get_path`, `collect_nodes`, `extract_paths`, `get_line_number`) | nav | ✅ used by filetree.nvim's neo-tree adapter |
| Scratch/floating window builder | `lib.nvim.window.make_scratch` | ui/nav | 🟡 candidate for preview/float-based features |
| Safe window close incl. re-focus | `lib.nvim.window.nice_quit` | nav | 🟡 candidate |
| Center a floating window | `lib.nvim.window.center` | ui | 🟡 candidate |
| Close window on focus lost | `lib.nvim.window.close_on_focus_lost` | ui | 🟡 candidate |
| Set floating window title | `lib.nvim.window.set_title` | ui | 🟡 candidate |
| Generic window attach/lifecycle helper | `lib.nvim.window.attach` | nav | 🟡 candidate |
| **Neo-tree-specific window lookup** | `lib.nvim.window.neotree.get_neotree_window()` | nav | ℹ️ **finding** — hardcodes "neotree" in the name/impl; conflicts with the "manager-agnostic" goal. If ported, generalize behind an adapter-style lookup instead of a Neo-tree-only helper. |
| Buffer normalization (skip specials, find a normal win) | `lib.nvim.buf_win_tab.normal_buffer` | nav/infra | 🟡 candidate — filetree.nvim's own `ROADMAP.md` already flags `util.buffer` → this module as a migration target |
| Adjacent-buffer resolution (safe) | `lib.nvim.buf_win_tab.safe_adjacent_buffer` | fileops | 🟡 candidate — overlaps `actions/save/adjacent_buffer` lineage |
| Window/tab/buffer capture (session-like state) | `lib.nvim.buf_win_tab.capture` | infra | 🟡 candidate |
| Move buffer to another tab | `lib.nvim.buf_win_tab.move_buffer_to_tab` | nav | 🟡 candidate |
| Guarded window resize | `lib.nvim.buf_win_tab.resize_guarded` | ui | 🟡 candidate — relevant to filetree.nvim's planned "Auto-Resize" feature (see its `ROADMAP.md` → Long-term) |

## paths / fs — filesystem helpers

| Feature | Origin | Category | Status |
|---|---|---|---|
| Path join / ensure-dir | `lib.nvim.fs.path` | paths/infra | 🟡 candidate |
| Path shortening for display | `lib.nvim.fs.path_shorten` | ui | 🟡 candidate — useful for tree-node labels / statusline |
| `is_dir`, `is_readable_file`, `is_subpath`, `relpath` | `lib.nvim.fs.is_dir`, `.is_readable_file`, `.is_subpath`, `.relpath` | infra/fileops | 🟡 candidate |
| Find nearest ancestor dir containing marker files | `lib.nvim.fs.find_upward_dir` | infra | 🟡 candidate — overlaps `actions/project_root` / filetree.nvim's `infra.project_root` |
| Polymorphic root resolver (multi-strategy project root) | `lib.nvim.fs.polymorphic_rootresolver` | infra | 🟡 candidate, stronger version of the above |
| **Recursive directory collection** | *(none)* | infra | ❌ **gap** — filetree.nvim's `util.fs` hand-rolls an iterative recursive collector (used by `fs.collect_recursive`, O(n), stack-based). lib.nvim has no equivalent; a `lib.nvim.fs.collect_recursive`-style helper would be a genuine, reusable port target instead of leaving it duplicated per-plugin. |
| Path/value normalization (`normalize_path`, `path_kind`, `to_path`, `to_argv`, …) | `lib.nvim.normalize.*` | paths/infra | 🟡 candidate |

## system / infra — cross-platform

| Feature | Origin | Category | Status |
|---|---|---|---|
| OS detection (`is_windows`/`is_linux`/`is_macos`/`is_wsl`) | `lib.nvim.cross.platform.is_*` | system/infra | 🟡 candidate — filetree.nvim's own `ROADMAP.md` flags `util.platform` → this module |
| Run command / argv builder | `lib.nvim.cross.run`, `lib.nvim.cross.run_argv` | system | 🟡 candidate — relevant to "open in system app" / trash / launcher features |
| Clipboard copy | `lib.nvim.cross.copy_to_clipboard` | paths | 🟡 candidate — overlaps `paths.path_copy` |
| Path separator normalization | `lib.nvim.cross.fs.separators` | infra | 🟡 candidate |
| Host env snapshot (`is_windows`/`home`/`pathsep`/`repo_base`) | `lib.nvim.system` | infra | ℹ️ newer/broader than `cross`; worth comparing before consolidating a port |

## ui — pickers / selection

| Feature | Origin | Category | Status |
|---|---|---|---|
| Consistent hover/select picker UI (single + multi-select) | `lib.nvim.ui.hover_select` | ui/search | ✅ used by filetree.nvim (`util.select` wraps it, per its `ROADMAP.md`) |

## git

| Feature | Origin | Category | Status |
|---|---|---|---|
| Repo root / current branch / dirty / ahead-behind / upstream / head hash | `lib.nvim.git.*` | git | 🟡 candidate — overlaps `git.git_status` |
| Line-diff highlight clearing | `lib.nvim.git.clear_line_diff` | git | 🟡 candidate |

## keymap/usercmd/autocmd wrappers (cross-cutting, not tree-specific)

| Feature | Origin | Category | Status |
|---|---|---|---|
| `vim.keymap.set` wrapper with validation | `lib.nvim.map` | all | ✅ filetree.nvim's `util.map` wraps this (per its `ROADMAP.md`) |
| `nvim_create_user_command` wrapper | `lib.nvim.usercmd` | all | ✅ used via `util.usercmd` |
| Autocmd / augroup helpers | `lib.nvim.autocmd`, `lib.nvim.autocmd.augroup` | all | ✅ used via `util.autocmd` |

---

## Notes for a future filetree.nvim port pass

- Everything marked 🟡 above overlaps a `util.*` module filetree.nvim already
  maintains locally; migrating means routing through lib.nvim with a local
  fallback so filetree.nvim still runs standalone — same approach it already
  used for `map`/`usercmd`/`autocmd`/`hover_select`.
- The one concrete **gap** worth closing in lib.nvim first is the recursive
  directory collector (no `fs.collect_recursive` equivalent yet).
- The one concrete **finding** is `lib.nvim.window.neotree.get_neotree_window`:
  its name and implementation are Neo-tree-specific, which cuts against the
  "cross-platform & filetree-manager agnostic" principle this very checklist
  item calls for. If/when filetree.nvim wants this helper, it should be
  generalized (e.g. adapter-supplied window lookup) rather than ported as-is.
- Cross-reference: filetree.nvim's own `docs/ROADMAP.md` → "lib.nvim adoption
  (shared code)" section lists the same candidates from its side of the
  fence; keep the two lists in sync as migrations land.
