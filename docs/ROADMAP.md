# `lib.nvim` - ROADMAP

## Table of content

  - [General](#general)
  - [Checklist audits & implementation plan](#checklist-audits--implementation-plan)
  - [Finish](#finish)

---

## General

1. Implement [vim-parity](../doc/vim-parity.md)

---

## Checklist audits & implementation plan

lib.nvim was audited against the project checklists. Full per-rule status:
- [Arch&Coding.md](ROADMAP/Arch%26Coding.md)
- [Checklist.md](ROADMAP/Checklist.md)
- [Zentral-Prinzipien.md](ROADMAP/Zentral-Prinzipien.md)
- Feature relevance map: [NEOTREE_FEATURES.md](ROADMAP/NEOTREE_FEATURES.md)

**Prioritized action items surfaced by the audits:**
1. ~~Add the missing `---@module` tag to `spawn_shell_command.lua`.~~ Done.
2. ~~Generalize `lib.nvim.window.neotree.get_neotree_window`.~~ Done — now
   `lib.nvim.window.find_by_filetype(filetype)`. See
   [NEOTREE_FEATURES.md](ROADMAP/NEOTREE_FEATURES.md).
3. **Recursive directory collector** — no `lib.nvim.fs.collect_recursive`
   equivalent exists yet; every consumer (e.g. filetree.nvim's `util.fs`)
   currently hand-rolls this. Candidate for a new `lib.nvim.fs` helper.
4. **Automated test suite** — still the biggest structural gap (no
   `docs/TESTS/**`); deliberately deferred, tracked here for later.
5. Optional: a small lint/CI pipeline (`luacheck`) alongside the existing
   `.stylua.toml` formatting config.
6. **Project-scoped persistent store** — `lib.nvim.cache.disk` +
   `lib.nvim.git.repo_root` cover the two halves but nothing combines them;
   at least 7 plugins hand-roll project-keyed JSON persistence separately.
   Proposal: [project-store.md](ROADMAP/project-store.md).

---

## Finish

1. Expand modules
2. Optimizations
3. Create a ROADMAP of features that might be worthwhile

---
