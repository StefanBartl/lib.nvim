# Health

```vim
:checkhealth lib
```

Reports the Neovim version, the configured strategy, and whether a representative set of modules resolves.

## `ℹ️ INFO` highlighting for consumers

`after/syntax/checkhealth.vim` highlights the hand-written `ℹ️ INFO` prefix
some dependent plugins (filetree.nvim, pickers.nvim, ...) add to status-list
lines — `DiagnosticInfo`, the same standard group Neovim's own checkhealth
syntax already uses for `OK`/`WARNING`/`ERROR`. It lives here rather than in
each of those plugins or in a personal config: since they all depend on
lib.nvim already, shipping it once here means it just works for every
consumer, no extra config needed.
