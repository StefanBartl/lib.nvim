# Help docs

All `:help` documentation lives in the runtimepath-root [`doc/`](../doc/) directory,
one file per documented module (`doc/lib.nvim-<module>.txt`), with
`doc/lib.nvim.txt` as the hub. Start at `:help lib.nvim`.

**You do not need to generate help tags yourself.** Plugin managers run
`:helptags` on a plugin's `doc/` directory automatically on install/update —
[lazy.nvim], packer and vim-plug all do this. After the next install/update the
`:help lib.nvim*` tags resolve out of the box. (The `doc/tags` index is
generated per-user and is intentionally git-ignored.)

> Help only works from the **runtimepath-root** `doc/`. A `doc/` folder nested
> inside `lua/…` is never indexed — that is why every help file lives in the
> top-level `doc/`.
