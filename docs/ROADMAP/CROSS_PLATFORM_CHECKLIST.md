# Cross-Platform Feature Checklist

`lib.nvim` claims Windows/WSL/macOS/Linux support for its `lib.nvim.cross.*`
modules, but a *claim* in the code is not the same as a *run* on that
platform. This file tracks, per module with real per-OS branches, what has
actually been executed on that OS versus what is only reasoned about from the
code and the target program's documented CLI behavior.

Legend: ✅ run on a real instance of that OS · 🟡 not run, but the code was
checked against that platform's documented CLI behavior (flags, man pages) —
confidence noted · ⬜ not yet looked at.

## `cross.reveal_in_fm`

Reveals a path in the system file manager. See
[`lua/lib/nvim/cross/reveal_in_fm/README.md`](../../lua/lib/nvim/cross/reveal_in_fm/README.md)
for the module itself; this entry only tracks verification status.

| OS | Status | Notes |
| --- | --- | --- |
| Windows (native) | ✅ | Verified on a real host 2026-08-07 (commit `ee2858b`): file reveal, directory target, paths with spaces and `&`, and `reuse` — window came to front every time, ~16ms round trip. |
| WSL | 🟡 | Same `win_reveal.ps1` code path as native Windows, reached through `wslpath -w` conversion. Not run for real; the path-conversion step itself is untested against a live WSL distro. |
| Linux (native) | 🟡 | Not run on a real host. Code-reviewed against each manager's documented CLI behavior: |
| | | — `dolphin --select <file>` — high confidence, an explicitly documented KDE flag. |
| | | — `pcmanfm` excluded from file-select (`select = false`) — high confidence, PCManFM has no select flag; giving it a file path would not do the right thing. |
| | | — `xdg-open` restricted to directories/no-select — high confidence, documented: `xdg-open <file>` launches the file's default application, not a manager; `xdg-open <dir>` resolves through the `inode/directory` MIME association to the user's actual default manager. |
| | | — `nautilus <file>` / `nemo <file>` / `caja <file>` / `thunar <file>` selecting the file with no explicit flag — medium-high confidence, matches the long-documented default ("bare file path → parent folder opens, file selected"), but this is *implicit* behavior, not a flag, and Nautilus specifically has touched it across GTK3→GTK4 releases (an explicit `--select` flag now exists there too but is unused in this code). A version where the bare-path select was dropped would silently degrade to "opens the folder, selects nothing" — not a crash, just a quiet miss. This is the one gap real execution would close that review can't. |
| macOS | 🟡 | Not run. `open -R <file>` is high confidence — an officially documented Apple `open(1)` flag ("Reveals the file(s) in the Finder instead of opening them"). `open <dir>` is standard, undisputed behavior. |

**To close Linux/macOS out fully**: run the module (or just the underlying
CLI commands) on a real Linux desktop with at least Nautilus and Dolphin
installed, and on a real macOS host. WSL only exercises the Windows code path
and does not substitute for either.

---

Other `lib.nvim.cross.*` modules with per-OS branches (`open_default`, `run`,
`fs.wslpath`, …) are not yet tracked here — add a section per module as it
gets this kind of audit, rather than filling in placeholders for modules that
haven't actually been reviewed.
