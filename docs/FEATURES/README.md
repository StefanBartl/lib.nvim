# Features

Cross-cutting capabilities lib.nvim provides, written up as *problems and
their solution* rather than as module reference. Use these when you want to
know **why** something exists and when to reach for it; use
[`docs/API/`](../API/README.md) when you want signatures, and each module's
own `README.md` for authoritative usage.

Entries here typically come out of an ecosystem-wide finding — a bug or a
platform behaviour that several plugins hit independently, which lib.nvim
then absorbs so nobody has to re-solve it.

## Files

- **[subprocess-env.md](subprocess-env.md)** — spawned subprocesses inherit
  Neovim's own environment, not a login shell's: incomplete `PATH`,
  unreachable OS keyring. `lib.nvim.cross.run.env` builds the completed
  environment for `vim.system`/`vim.uv.spawn`/`jobstart`; `cross.run`'s
  `run`/`run_blocking` apply it by default.
- **[async-directory-walk.md](async-directory-walk.md)** — recursive
  directory scans (`collect_recursive`, and `scan_cached`/`scan_roots` built
  on it) block the main loop on large trees. Coroutine-driven `*_async`
  counterparts fix that without a callback pyramid or a general async
  framework.
