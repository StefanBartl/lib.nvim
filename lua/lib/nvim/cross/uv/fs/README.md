Returns the current working directory via libuv: `(vim.uv or vim.loop).cwd()`,
falling back to `vim.fn.getcwd()` if neither is available. Exists purely for
version compatibility across Neovim releases that expose the loop under
different names.

Note: this module's body is identical to `lib.nvim.cross.fs._cwd` — the two
were not deduplicated. Unlike `fs._cwd`, this one is not currently
re-exported through `require("lib.nvim.cross")`'s aggregate table.
