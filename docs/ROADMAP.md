# `lib.nvim` - ROADMAP

## Table of content

  - [General](#general)
  - [Checklist audits & implementation plan](#checklist-audits-implementation-plan)
  - [Finish](#finish)

---

## General

1. Implement [vim-parity](../doc/vim-parity.md)
2. Bessere Aufteilung in /docs, ausmisten

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
3. ~~Recursive directory collector~~ Done — `lib.nvim.fs.collect_recursive`
   (flat walk) and `lib.nvim.fs.scan_cached` (TTL-cached wrapper) both ship.
4. ~~Automated test suite~~ Done (at least the CI-wiring half) —
   `docs/TESTS/**` now covers most modules (logger, ui.kit, lua helpers, nvim
   helpers, window, buffer/window context, cache, store.project, composer)
   and runs headless in CI (item 5's workflow). Growing coverage for
   not-yet-tested modules remains open-ended, ordinary work — no longer a
   structural gap.
5. ~~Lint/CI pipeline~~ Done — `.luacheckrc` (LuaJIT std, `vim` global,
   `lib.nvim` conventions codified as ignore rules) plus
   `.github/workflows/ci.yml` (stylua --check, luacheck, headless test run)
   on push/PR.
6. ~~Project-scoped persistent store~~ Done — `lib.nvim.store.project`
   ships, combining `lib.nvim.cache.disk` + `lib.nvim.fs.project_key`. See
   [project-store.md](ROADMAP/project-store.md) (updated with its
   implementation status) and `doc/lib.nvim-store.txt`.
7. ~~Subcommand user-command composer~~ Done — `lib.nvim.usercmd.composer`
   (`:Verb sub sub ARG` + derived `<Tab>` completion + Markdown docgen)
   ships all 8 planned phases (typed args, flags, bare `key=value`,
   buffer-local commands, count prefix). Dogfooded as lib.nvim's own `:Lib`
   verb, generated reference at `docs/BINDINGS/Usercmds.md`. See
   [usrcmd_builder.md](ROADMAP/usrcmd_builder.md) and `doc/lib.nvim-composer.txt`.
8. ~~Structured logging / diagnostics / crash dumps~~ Done — shipped as
   `lib.nvim.logger` (not `lib.nvim.debug`; the naming question in the concept
   doc was resolved in favour of `logger`). All four phases of
   [DEBUG-MODULE-CONCEPT.md](ROADMAP/DEBUG-MODULE-CONCEPT.md) are in, plus a
   global kill switch and tag filtering that the concept did not anticipate.
   **That concept doc is a historical record — implementing it again would
   duplicate `lib.nvim.logger`;** it now carries a banner saying so.

---

## Finish

1. Expand modules
2. Optimizations
3. Create a ROADMAP of features that might be worthwhile

---
