# Filesystem Ignore Definitions

This module provides a centralized, canonical set of filesystem ignore rules
intended for developer tooling that performs recursive filesystem traversal.

The goal is to avoid duplicated, inconsistent ignore lists across different
plugins and subsystems while keeping the rules conservative and predictable.

---

## Table of content

  - [Purpose](#purpose)
  - [Design Principles](#design-principles)
  - [What This Module Is *Not*](#what-this-module-is-not)
  - [Rule Categories](#rule-categories)
    - [Basenames](#basenames)
    - [Patterns](#patterns)
  - [Public API](#public-api)
    - [`as_set() -> table<string, boolean>`](#as_set-tablestring-boolean)
    - [`as_luals_patterns() -> string[]`](#as_luals_patterns-string)
    - [`as_telescope_patterns() -> string[]`](#as_telescope_patterns-string)
    - [`as_neotree_names() -> string[]`](#as_neotree_names-string)
  - [Typical Usage Examples](#typical-usage-examples)
    - [Lua Language Server](#lua-language-server)
    - [Telescope](#telescope)
    - [Neo-tree](#neo-tree)
  - [Extending the List](#extending-the-list)
  - [Rationale](#rationale)

---

## Purpose

Many developer-facing tools scan large parts of a project directory tree:

- Language servers (workspace indexing)
- File pickers (Telescope, fzf)
- File trees (Neo-tree)
- Search / grep tools
- Caching and indexing utilities

During these scans, certain directories and files are almost always irrelevant,
generated, or excessively large (e.g. `node_modules`, build outputs, caches).

This module defines a shared ignore list for such cases.

---

## Design Principles

- **Centralized**
  A single source of truth for ignore rules used across multiple tools.

- **Heuristic and conservative**
  The rules cover common cases without attempting to replace `.gitignore`.

- **Tool-agnostic core**
  The data is defined independently of any specific plugin.

- **No filesystem IO**
  The module only performs textual matching and normalization.

- **Explicit semantics**
  Exact names and pattern-based rules are kept separate.

---

## What This Module Is *Not*

- Not a replacement for `.gitignore`
- Not project-specific
- Not user-configurable at runtime
- Not performing any file or directory scanning by itself

---

## Rule Categories

### Basenames

Basenames are exact directory or file names that should be ignored verbatim.

Examples:
- `node_modules`
- `.git`
- `dist`
- `__pycache__`

These are suitable for:
- Neo-tree `hide_by_name`
- LSP workspace directory exclusion
- Direct basename comparisons

---

### Patterns

Patterns are Lua-style patterns intended for tools that support regex-like
matching (such as Telescope).

Examples:
- `%.log`
- `pnpm%-lock.yaml`
- `%.class`

These are suitable for:
- Telescope `file_ignore_patterns`
- Grep-like tools

---

## Public API

The module exposes several helper functions to adapt the canonical data to
different consumers.

### `as_set() -> table<string, boolean>`

Returns the basename list as a normalized lookup table for fast membership tests.

Use case:
- Custom filesystem traversal
- Performance-critical filters

---

### `as_luals_patterns() -> string[]`

Converts basenames into glob patterns compatible with
`Lua.workspace.ignoreDir`.

The output includes:
- Root-level ignores (`name`)
- Recursive ignores (`**/name`)

---

### `as_telescope_patterns() -> string[]`

Returns a combined list of:
- Exact basenames
- Pattern-based ignores

Suitable for:
- `telescope.defaults.file_ignore_patterns`

---

### `as_neotree_names() -> string[]`

Returns basenames only.

Suitable for:
- `neo-tree.filesystem.filtered_items.hide_by_name`

---

## Typical Usage Examples

### Lua Language Server

```lua
local ignore = require("lib.nvim.fs.ignore")

settings = {
  Lua = {
    workspace = {
      ignoreDir = ignore.as_luals_patterns(),
    },
  },
}
````

---

### Telescope

```lua
local ignore = require("lib.nvim.fs.ignore")

require("telescope").setup({
  defaults = {
    file_ignore_patterns = ignore.as_telescope_patterns(),
  },
})
```

---

### Neo-tree

```lua
local ignore = require("lib.nvim.fs.ignore")

filesystem = {
  filtered_items = {
    hide_by_name = ignore.as_neotree_names(),
  },
}
```

---

## Extending the List

When adding new entries, follow these guidelines:

* Add **exact names** to `basenames`
* Add **regex-like rules** to `patterns`
* Prefer widely applicable rules
* Avoid project-specific or niche cases

---

## Rationale

Keeping ignore rules centralized improves:

* Consistency across tools
* Maintainability
* Readability of plugin configurations
* Debuggability of filesystem-related issues

This module intentionally favors clarity and predictability over completeness.

---

