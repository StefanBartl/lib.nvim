# Polymorphic Root Resolver for Neovim LSPs

## Table of content

  - [Overview](#overview)
  - [Features](#features)
  - [Usage](#usage)
  - [Configuration](#configuration)
  - [Flow Diagram](#flow-diagram)
  - [Summary](#summary)

---

## Overview

This module provides a **polymorphic root-directory resolver** for Neovim LSP configurations.
Its main purpose is to determine the "root directory" of a project based on a file path or buffer number. This is crucial for LSP servers because many language servers need to know the project root to:

- Locate configuration files (e.g., `.luarc.json`, `tsconfig.json`, `pyproject.toml`).
- Determine the scope of diagnostics and linting.
- Load workspace libraries efficiently.
- Resolve relative imports and file references correctly.

Without a proper root resolver, LSPs may treat every file individually, leading to:

- Missing completions across the project.
- Unnecessary diagnostics outside the project.
- Incorrect path resolutions.

---

## Features

- **Polymorphic:** accepts either a filename (`string`) or buffer number (`integer`) and resolves the root accordingly.
- **Callback support:** optionally provide a callback to integrate with asynchronous LSP pipelines.
- **Configurable markers:** use VCS directories (`.git`, `.hg`, `.svn`) or custom files/folders to detect project roots.
- **Fallbacks:** if no markers are found, falls back to the containing directory or Neovim's `stdpath("config")`.
- **Reusable:** independent of any specific LSP, can be used for LuaLS, Marksman, or other LSP servers.

---

## Usage

```lua
local make_root_dir_resolver = require("lib.nvim.fs.polymorphic_rootresolver")

-- Create a resolver with default configuration
local resolve_root = make_root_dir_resolver()

-- Resolve root from a filename
local root = resolve_root("/home/user/project/src/main.lua")
print("Project root:", root)

-- Resolve root from a buffer number (e.g., buffer 1)
local root_buf = resolve_root(1, function(res)
  print("Resolved root via callback:", res)
end)
```

---

## Configuration

You can customize the resolver when creating it:

```lua
local resolve_root = make_root_dir_resolver({
  markers = { ".git", ".luarc.json", "pyproject.toml" },
  include_stdpath_config = false,
})
```

- `markers`: list of files/folders that indicate a project root.
- `include_stdpath_config`: if `true`, will fallback to Neovim's `stdpath("config")` if the start directory is under it.
- `resolve`: `nil|fun(dir: string, cfg): string|nil` — replaces the default marker
  search entirely. Called with the normalized start directory and the resolved
  config; its return value (or the start directory, if it returns `nil`) becomes
  the root. Use this when a server's notion of "root" is more than "nearest
  marker" (e.g. a workspace file, a language-specific config precedence) while
  still reusing this module's buffer/filename normalization and callback
  plumbing:

  ```lua
  local resolve_root = make_root_dir_resolver({
    resolve = function(dir, cfg)
      return require("lib.nvim.fs.find_root")({ markers = { "pyproject.toml" } }).find(dir)
    end,
  })
  ```

---

## Flow Diagram

```sh
+-----------------------------+
| Input: fname (string)       |
|        or bufnr (integer)   |
+-----------------------------+
            |
            v
+-----------------------------+
| If bufnr, get buffer name   |
+-----------------------------+
            |
            v
+-----------------------------+
| Determine start directory   |
|  - dirname(fname)           |
|  - fallback to CWD          |
+-----------------------------+
            |
            v
+-----------------------------+
| cfg.resolve set?            |
|  yes -> cfg.resolve(dir,cfg)|
|  no  -> vim.fs.root(dir,    |
|         cfg.markers)        |
|         (single call, one   |
|         combined list --    |
|         VCS + custom markers|
|         are not two stages) |
+-----------------------------+
            |
            v
+-----------------------------+
| No root found? -> use dir   |
+-----------------------------+
            |
            v
+-----------------------------+
| Check if dir is under       |
|  stdpath("config")          |
+-----------------------------+
            |
            v
+-----------------------------+
| Return resolved root        |
+-----------------------------+
            |
            v
+-----------------------------+
| If callback provided, call  |
| cb(root)                    |
+-----------------------------+
```

---

## Summary

A **root resolver** determines the project root directory for a given file or buffer. This is essential for proper LSP functionality, workspace management, and project-scoped diagnostics. The polymorphic design ensures compatibility with both legacy `lspconfig` and the new Neovim native LSP pipelines.

---
