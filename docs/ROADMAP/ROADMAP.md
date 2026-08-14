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
   `telemetry-browser-report.md`, `telemetry-documentation-bridge.md` (both
   sides shipped, and the module it covered — `lib.nvim.telemetry` — has
   since moved out of this repo entirely, to `runtime-analysis.nvim`; current
   docs live there and in documentation.nvim's `docs/ECOSYSTEM.md`),
   `autocmd-dispatcher.md` (shipped as `lib.nvim.autocmd.dispatcher`; current
   docs live at `lua/lib/nvim/autocmd/dispatcher/README.md` and
   `docs/FEATURES/COMMANDS.md`) all went this way.
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

- [kit-dashboard.md](ROADMAP/kit-dashboard.md) — a persistent, activatable
  `ui.kit` list (unlike every existing kit component, one that outlives a
  single activation) plus a generic file/url/func/dir jump-target union.
  Analysis only, extracted out of `UI-KIT-CONCEPT.md` §15 — three open
  design questions listed there before this is ready to build.

---

