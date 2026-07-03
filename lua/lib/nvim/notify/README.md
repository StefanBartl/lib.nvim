# `lib.nvim.notify`

## Table of content

- [`lib.nvim.notify`](#libnotify)
  - [Example: usage in a module](#example-usage-in-a-module)
  - [Example: another module, another prefix](#example-another-module-another-prefix)
  - [`lib.nvim.notify.safe`](#libnotifysafe)
    - [When is `lib.nvim.notify.safe` needed](#when-is-libnotifysafe-needed)
    - [`safe.schedule`](#safeschedule)
    - [`safe.defer`](#safedefer)
    - [`safe.wrap`](#safewrap)
    - [`safe.notify`](#safenotify)
    - [`safe.create_safe(prefix)`](#safecreate_safeprefix)
    - [Recommended usage](#recommended-usage)
  - [Design properties](#design-properties)

---

## Example: usage in a module

```lua
---@module 'neotree_fs_refactor.core'

local notify = require("lib.nvim.notify").create("[neotree-fs-refactor]")

notify.info("Refactor started")
notify.warn("Some paths could not be updated")
notify.error("LSP rename failed")
```

---

## Example: another module, another prefix

```lua
---@module 'config.lsp.setup'

local notify = require("lib.nvim.notify").create("[lsp]")

notify.debug("Attaching server")
```

---

## `lib.nvim.notify.safe`

`lib.nvim.notify.safe` provides safe wrappers around `vim.notify`, specifically designed for so-called *fast event contexts*. These include, among others, callbacks from `autocmd`s such as `TextChanged`, `CursorMoved`, `BufWritePost` or other high-frequency events, in which a direct call to `vim.notify` can lead to errors, delays or undefined behavior.

The module encapsulates all common protection mechanisms (`vim.schedule`, `vim.defer_fn`, `vim.schedule_wrap`) behind a consistent, well-typed API.

---

### When is `lib.nvim.notify.safe` needed

You should use the safe variants when:

* notifications originate from autocommands
* notifications are triggered from LSP, tree or UI callbacks
* code is potentially executed multiple times per second
* it is not guaranteed that you are in the main event loop

For normal, direct user actions (commands, keymaps), `lib.nvim.notify.create` is still sufficient.

---

### `safe.schedule`

Schedules the notification with `vim.schedule` directly in the next main-loop tick.
This is the recommended default solution for almost all safe cases.

```lua
local safe = require("lib.nvim.notify").safe

safe.schedule("Scheduled notification", vim.log.levels.INFO)
```

Properties:

* immediate, but safe execution
* minimal overhead
* preferred default strategy

---

### `safe.defer`

Delays the notification by a defined time span using `vim.defer_fn`.

```lua
safe.defer("Delayed warning", vim.log.levels.WARN, {}, 150)
```

Properties:

* controlled delay
* useful for UI transitions or debouncing
* optional delay in milliseconds

---

### `safe.wrap`

Creates a reusable, already-scheduled notify function.
Ideal for repeated calls in hot paths.

```lua
local wrapped = safe.wrap()

wrapped("Repeated debug message", vim.log.levels.DEBUG)
```

Properties:

* efficient for many calls
* avoids repeatedly creating closures
* optimal for loops or event handlers

---

### `safe.notify`

A convenience wrapper that automatically chooses the appropriate strategy depending on the mode.

```lua
safe.notify("Auto scheduled", vim.log.levels.INFO)
safe.notify("Deferred", vim.log.levels.WARN, {}, "defer", 100)
```

Supported modes:

* `"schedule"` (default)
* `"defer"`
* `"wrap"`

---

### `safe.create_safe(prefix)`

Creates a safe notifier with a fixed prefix, analogous to `lib.nvim.notify.create`, but fully fast-event-safe.

```lua
local safe_notify = require("lib.nvim.notify").safe.create_safe("[plugin]")

safe_notify.info("Safe info message")
safe_notify.error("Safe error message")
```

Properties:

* the prefix is normalized once
* identical API to normal notifiers (`info`, `warn`, `error`, `debug`)
* internally always `vim.schedule`
* no duplicate prefixes possible

---

### Recommended usage

* `lib.nvim.notify.create`
  for commands, keymaps, user actions

* `lib.nvim.notify.safe.*`
  for autocommands, callbacks, LSP events, UI hooks

Both variants are fully compatible and can be used in parallel within the same project.

```vim
 Standard usage (as before)
local notify = require("lib.nvim.notify").create("[plugin]")
notify.info("Standard notification")

-- Safe variants for fast event contexts
local safe = require("lib.nvim.notify").safe

-- Variant 1: schedule (default)
safe.schedule("Message from fast event", vim.log.levels.INFO)

-- Variant 2: defer with delay
safe.defer("Delayed message", vim.log.levels.WARN, {}, 100)

-- Variant 3: wrapped notifier for repeated calls
local wrapped_notify = safe.wrap()
wrapped_notify("Efficient repeated call", vim.log.levels.DEBUG)

-- Variant 4: convenience wrapper
safe.notify("Auto-scheduled", vim.log.levels.INFO, {}, "schedule")

-- Variant 5: safe notifier with prefix
local safe_notify = safe.create_safe("[plugin]")
safe_notify.info("Safe + prefixed")
safe_notify.error("Error from fast context")
```

---

## Design properties

* one central, generic notify module
* the prefix is set **once per file**
* no double prefixing possible
* API identical to `vim.notify`
* easily reusable for any plugin or config component

---
