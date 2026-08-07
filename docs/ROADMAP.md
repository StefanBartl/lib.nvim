# `lib.nvim` - ROADMAP

## Table of content

  - [General](#general)
  - [Checklist audits & implementation plan](#checklist-audits-implementation-plan)
  - [Finish](#finish)

---

## General

1. Implement [vim-parity](../doc/vim-parity.md)
2. ~~Bessere Aufteilung in /docs, ausmisten~~ Partially done — fully-implemented
   concept docs with no unique content left outside their own module (no
   granular source cross-references into specific sections) get deleted once
   shipped: `DEBUG-MODULE-CONCEPT.md`, `project-store.md`,
   `usage-telemetry.md`, `UI-KIT-TASK-native-select.md`,
   `telemetry-browser-report.md` all went this way.
   `UI-KIT-CONCEPT.md` and `usrcmd_builder.md` stay — both are pointed at by
   section number from their module's own shipped source comments, so
   deleting them would leave dead links across live code. Still open: the
   remaining audit docs (`Arch&Coding.md`/`Checklist.md`/`Zentral-Prinzipien.md`)
   and `NEOTREE_FEATURES.md` are living references, not roadmap clutter, and
   are not part of this pass.

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
   `lua/lib/nvim/store/project/README.md` and `doc/lib.nvim-store.txt`.
7. ~~Subcommand user-command composer~~ Done — `lib.nvim.usercmd.composer`
   (`:Verb sub sub ARG` + derived `<Tab>` completion + Markdown docgen)
   ships all 8 planned phases (typed args, flags, bare `key=value`,
   buffer-local commands, count prefix). Dogfooded as lib.nvim's own `:Lib`
   verb, generated reference at `docs/BINDINGS/Usercmds.md`. See
   [usrcmd_builder.md](ROADMAP/usrcmd_builder.md) and `doc/lib.nvim-composer.txt`.
8. ~~Structured logging / diagnostics / crash dumps~~ Done — shipped as
   `lib.nvim.logger` (not `lib.nvim.debug`; the original concept's naming
   question was resolved in favour of `logger`), all four originally-planned
   phases plus a global kill switch and tag filtering the concept did not
   anticipate. See `lua/lib/nvim/logger/README.md` and `doc/lib.nvim-logger.txt`.
9. ~~External-tool installer~~ Done — shipped as `lib.nvim.deps`
   (`health`/`spec`/`pm`/`install`/`view`) plus `:Lib deps show|install`.
   Plugins declare optional tools in `docs/INSTALL.md` or `docs/install.json`
   with a validation-enforced `why`; installs are composed for the host's
   package manager, confirmed, and typed into a terminal the user submits.
   Two design corrections came out of building it — routes on the existing
   `:Lib` verb instead of a new `:LibDeps` command, and a lazy.nvim fallback
   after `runtimepath` proved to miss 76 of 120 plugins. The concept doc
   [dependency-installer.md](ROADMAP/dependency-installer.md) stays (contra
   General §2): its Mason comparison, the measurement, and the rejected
   alternatives are reasoning the module README deliberately doesn't carry.
   **Not yet consumed by any plugin** — `pdfport.nvim` is the intended first
   author.

---

## Open concepts (not implemented)

Design proposals that have **not** shipped. A doc leaves this list either by
being implemented (and then usually deleted — see General §2) or by being
rejected.

- [autocmd-dispatcher.md](ROADMAP/autocmd-dispatcher.md) — one autocmd, many
  handlers.
- [telemetry-documentation-bridge.md](ROADMAP/telemetry-documentation-bridge.md)
  — cross documentation.nvim's static `dead-function` check with telemetry's
  runtime counts; each method's blind spot is the other's evidence. The
  lib.nvim-side contract (`telemetry.load()`, key→module-path resolution)
  shipped; the documentation.nvim-side consumer (mode 7, the join, the
  `doccoverage` lines) is still open and lives in that repo's own roadmap.

---

## Finish

1. Expand modules
2. Optimizations
3. Create a ROADMAP of features that might be worthwhile

---
