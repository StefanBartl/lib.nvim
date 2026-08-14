# Examples

Runnable scenarios for lib.nvim's larger modules — the ones with enough
surface area that a README's inline snippets don't fully show how the
pieces fit together in a real call site. Each file is one self-contained
scenario, not an API index (that's what the per-module `README.md` and
`:h lib.nvim-*` are for).

These are illustrative, not executable scripts: paste the relevant body
into a user command, keymap callback, or plugin setup function inside a
running Neovim instance rather than `dofile`-ing them directly (several
open real floats, prompt for input, or register user commands — none of
that is meant to run headless at require-time).

## `lib.nvim.harvest`

- [harvest-scan-and-export.lua](harvest-scan-and-export.lua) — scan every
  Markdown file under `cwd` for `TODO` markers, render a Markdown table,
  emit it to a scratch buffer (or clipboard/file).
- [harvest-collect-links.lua](harvest-collect-links.lua) — extract Markdown
  links from the current buffer and jump to one via a picker.

## `lib.nvim.autocmd.dispatcher`

- [autocmd-dispatcher-filetype.lua](autocmd-dispatcher-filetype.lua) — collapse
  N hand-rolled `FileType` autocmds into one registry: lazy-loaded handlers,
  deterministic `priority` ordering, glob keys, per-buffer `once`.

## `lib.nvim.usercmd.composer`

- [composer-basic-verb.lua](composer-basic-verb.lua) — the core model:
  routes, typed/enum args, a bare-verb default handler, derived completion.
- [composer-flags-and-kv.lua](composer-flags-and-kv.lua) — `--flag[=value]`
  / `-x` short aliases, and bare `key=value` grammar, on a root route.
- [composer-buffer-local-and-count.lua](composer-buffer-local-and-count.lua)
  — buffer-scoped commands (`spec.buffer`) and a `:N Verb` count prefix.

## `lib.nvim.ui.kit`

- [kit-note.lua](kit-note.lua) — centered title + message float, optional
  auto-dismiss timeout.
- [kit-viewer.lua](kit-viewer.lua) — read-only info panel, auto-sized,
  dismisses on q/`<Esc>` or the moment focus leaves it.
- [kit-toast.lua](kit-toast.lua) — ephemeral, stacking, non-focus-stealing
  corner notifications.
- [kit-input.lua](kit-input.lua) — themed single-line prompt, a `vim.ui.input`
  replacement.
- [kit-select.lua](kit-select.lua) — themed list chooser, single and
  multi-select.
- [kit-prompt.lua](kit-prompt.lua) — ask a yes/no-or-custom-choice or
  free-text question, one answer back.
- [kit-confirm.lua](kit-confirm.lua) — the same question, answered with
  horizontal buttons instead of a list.
- [kit-menu.lua](kit-menu.lua) — cursor-anchored action list, each item
  runs its own callback.
- [kit-picker.lua](kit-picker.lua) — Telescope-style interactive picker
  (prompt drives a results list) without a fuzzy-finder dependency.
- [kit-layout.lua](kit-layout.lua) — hand-build a coordinated multi-float
  layout with `compute`/`mount`, for UI shapes no ready-made template fits.
