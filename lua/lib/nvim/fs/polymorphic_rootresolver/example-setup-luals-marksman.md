# Example - Setup

## Table of content

  - [Basic idea](#basic-idea)
  - [Different usage: Marksman vs LuaLS](#different-usage-marksman-vs-luals)
    - [1. Marksman (Markdown)](#1-marksman-markdown)
    - [2. LuaLS (Lua)](#2-luals-lua)
  - [Summary of the differences](#summary-of-the-differences)
    - [Best Practice](#best-practice)

---

Here is a detailed explanation of how to use your `polymorphic_root_resolver`
module effectively with **Marksman** and **LuaLS**, including the differences in
setup:

---

## Basic idea

Your module `lib.nvim.fs.polymorphic_root_resolver` provides a **functional,
polymorphic root resolution**:

```lua
local resolver_module = require("lib.nvim.fs.polymorphic_root_resolver")
local resolve_root = resolver_module.make_root_dir_resolver()
```

* `resolve_root(arg, cb?)` accepts either:

  * `arg` = **buffer number** → automatically reads the buffer's file name
  * `arg` = **file path** → uses it directly
* An optional callback `cb(root)` allows integration into **asynchronous
  pipelines**, as required by Neovim's native LSP configuration.

---

## Different usage: Marksman vs LuaLS

### 1. Marksman (Markdown)

* **Characteristic:** Markdown projects often have `.marksman.toml`, `mkdocs.yml`
  or `.git` as root indicators.
* **Setup:** The root resolver must be **polymorphic** to support both `bufnr`
  and `fname`, since Neovim's new LSP API (`vim.lsp.enable`) passes buffer
  numbers.
* **Example:**

```lua
local resolver_module = require("lib.nvim.fs.polymorphic_root_resolver")

local resolve_root = resolver_module.make_root_dir_resolver({
  markers = { ".marksman.toml", ".git", "mkdocs.yml" },
  include_stdpath_config = false,
})

vim.lsp.config("marksman", {
  cmd = { "marksman", "server" },
  filetypes = { "markdown", "markdown.mdx" },
  root_dir = resolve_root,  -- polymorphic resolver
  single_file_support = false,
})
```

* **Why it matters here:** Markdown projects often have many small documents.
  The root must be identified reliably, otherwise the LSP treats every file as
  isolated → missing link resolution and faulty workspace diagnostics.

---

### 2. LuaLS (Lua)

* **Characteristic:** Lua projects use `.luarc.json`, `.neoconf.json`,
  `selene.toml`, `stylua.toml` and VCS markers.
* **Setup:** The root resolver can be **polymorphic as well**, since LuaLS also
  accepts `bufnr` or `fname`.
* **Optional:** For LuaLS you could make the configuration a bit stricter and
  additionally set `include_stdpath_config = true`, so that scripts within the
  Neovim configuration structure are automatically recognized as root.
* **Example:**

```lua
local resolver_module = require("lib.nvim.fs.polymorphic_root_resolver")

local resolve_root = resolver_module.make_root_dir_resolver({
  markers = { ".git", ".hg", ".svn", ".luarc.json", ".neoconf.json", "selene.toml", "stylua.toml" },
  include_stdpath_config = true,
})

vim.lsp.config("lua_ls", {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_dir = resolve_root,
  single_file_support = true,
})
```

* **Why it matters here:** LuaLS uses the root dir to load workspace libraries
  (`library`) correctly and to check diagnostics only within the project.

---

## Summary of the differences

| Property            | Marksman                               | LuaLS                                       |
| ------------------- | -------------------------------------- | ------------------------------------------- |
| Typical markers     | `.marksman.toml`, `mkdocs.yml`, `.git` | `.git`, `.luarc.json`, `.neoconf.json` etc. |
| Stdpath fallback    | rarely necessary (not config)          | optionally useful (Neovim config)           |
| Single-file support | false                                  | true                                        |
| Focus               | Project-wide Markdown link resolution  | Workspace libraries & project diagnostics   |
| Root importance     | high for correct link checks           | high for workspace / diagnostics / preload  |

---

### Best Practice

1. **Polymorphic resolver for both:** cover both `bufnr` and `fname`.
2. **Marksman:** adapt markers to Markdown-specific files, turn off stdpath config.
3. **LuaLS:** extend markers to Lua project files, optionally enable stdpath config.
4. **Use the callback:** always compatible with LSP pipelines.
5. **Shared function:** the same module can be reused for both LSPs → DRY principle.

---
