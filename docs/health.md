# Health

```vim
:checkhealth lib
```

Reports the Neovim version, the configured strategy, and whether a representative set of modules resolves.

The **named roots** section (`lib.nvim.fs.roots`) lists every configured root (`$REPOS_DIR`, `$NVIM_CONFIG_DIR`,
`extra` and registered ones) with what became of it: a root that is not set, whose function raised, that is relative,
the filesystem root, or that points at a missing directory is a warning with the reason. It also warns when
`$NVIM_CONFIG_DIR` in the environment disagrees with `stdpath('config')` (usually inherited from a parent Neovim with
another `NVIM_APPNAME`).

The **dialogs** section (`lib.nvim.ui.dialog`) names the backend that answers every plugin's yes/no, choice and text prompt: ui.nvim's `ui.kit` (OK), the kit copy in lib.nvim (info; install ui.nvim for your own preset) or the native `vim.ui` fallback (warning).

The **deprecated API calls** section (`lib.nvim.dev.deprecations`) scans every `*.lua` under `stdpath('config')` (not in dot-directories or `---@meta` files) and
warns per deprecated Neovim call still in it (`vim.loop`, `nvim_buf_set_option`, `vim.highlight`, ...) with file, line,
column and the replacement. A line under `---@diagnostic disable-next-line: deprecated` is not reported. The same
check on save: `require("lib.nvim.dev.deprecations").watch()`, see the [module README](../lua/lib/nvim/dev/README.md).

## `ℹ️ INFO` highlighting for consumers

`after/syntax/checkhealth.vim` highlights the hand-written `ℹ️ INFO` prefix
some dependent plugins (filetree.nvim, pickers.nvim, ...) add to status-list
lines — `DiagnosticInfo`, the same standard group Neovim's own checkhealth
syntax already uses for `OK`/`WARNING`/`ERROR`. It lives here rather than in
each of those plugins or in a personal config: since they all depend on
lib.nvim already, shipping it once here means it just works for every
consumer, no extra config needed.
