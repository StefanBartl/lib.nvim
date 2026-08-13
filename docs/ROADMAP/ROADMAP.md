# `lib.nvim` - ROADMAP

## Table of content

  - [General](#general)
  - [Open concepts (not implemented)](#open-concepts-not-implemented)

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

