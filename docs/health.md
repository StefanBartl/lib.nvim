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

## `ℹ️ INFO` highlighting for consumers

`after/syntax/checkhealth.vim` highlights the hand-written `ℹ️ INFO` prefix
some dependent plugins (filetree.nvim, pickers.nvim, ...) add to status-list
lines — `DiagnosticInfo`, the same standard group Neovim's own checkhealth
syntax already uses for `OK`/`WARNING`/`ERROR`. It lives here rather than in
each of those plugins or in a personal config: since they all depend on
lib.nvim already, shipping it once here means it just works for every
consumer, no extra config needed.
