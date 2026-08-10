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
  environment for `vim.system`/`vim.uv.spawn`/`jobstart`.
