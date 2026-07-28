Returns the current working directory via libuv: `(vim.uv or vim.loop).cwd()`,
falling back to `vim.fn.getcwd()` if neither `vim.uv` nor `vim.loop` is
available. Exists purely for version compatibility across Neovim releases
that expose the loop under different names.

Aggregated as `require("lib.nvim.cross").fs.cwd`.

Note: `lib.nvim.cross.uv.fs` is a separate module with an identical body —
the two were not deduplicated.
