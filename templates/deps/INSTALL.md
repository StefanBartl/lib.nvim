# Optional external tools

<!--
Copy this file to <your-plugin>/docs/INSTALL.md and fill it in — one
```install-tool fenced block per tool your plugin can use but doesn't
require to load. Parsed by lib.nvim.deps.spec.parse_markdown /
lib.nvim.deps.spec.load; see lua/lib/nvim/deps/README.md in lib.nvim for
the full field reference, and docs/ROADMAP/dependency-installer.md for the
design this template implements.

Prefer install.json instead (see ../deps/install.json in this same
templates/ directory) if you want multi-line `why` text, extra metadata
fields, or the fastest possible parse — the Markdown variant here trades
that for being readable as plain prose on GitHub. If your plugin ships
both, lib.nvim.deps.spec.find prefers the JSON one.

Every block needs: bin, a non-empty why, and at least one pkg entry.
`required` defaults to false if omitted; `see` is optional (an anchor into
this file's own prose, e.g. "#ocr-backend").
-->

`<plugin-name>` works without any of these — each one only unlocks a
specific feature or backend. Run `:LibDeps show <plugin-name>` to see
what's missing on this machine.

```install-tool
bin: <executable-name>
required: false
why: "<one sentence: what this unlocks, said plainly>"
pkg:
  apt: <debian/ubuntu package name>
  dnf: <fedora package name>
  pacman: <arch package name>
  zypper: <opensuse package name>
  apk: <alpine package name>
  brew: <macos/homebrew package name>
  winget: <windows/winget package id>
  scoop: <windows/scoop package name>
  choco: <windows/chocolatey package name>
```

<!-- Repeat the block above per tool. Omit any pkg row your tool has no
     package for on that manager rather than guessing a name. -->
