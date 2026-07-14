# `lib.nvim.treesitter.guard`

Filetype allowlist gate for treesitter-dependent features (highlighting,
foldexpr, indentexpr).

This is **not** a parser-availability probe (it does not check whether a
parser is actually installed for a filetype) — it's a curated allowlist of
filetypes considered safe/desired for treesitter activation, kept centrally
so multiple activation hooks (highlight, fold, indent, …) share one list.

## Usage

```lua
local guard = require("lib.nvim.treesitter.guard")

vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    if guard.is_enabled(args.buf) then
      vim.treesitter.start(args.buf)
    end
  end,
})

-- Override the allowlist for a one-off check:
guard.is_enabled(bufnr, { lua = true, python = true })
```

## API

| Function                              | Meaning                                                        |
|----------------------------------------|------------------------------------------------------------------|
| `is_enabled(bufnr, whitelist?)`        | `true` when `bufnr`'s filetype is in `whitelist` (default `DEFAULT_WHITELIST`). |
| `DEFAULT_WHITELIST`                    | `table<string, boolean>` of filetypes enabled by default.       |
