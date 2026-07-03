# lib.lua.lazy – Reusable lazy loading for Neovim

This module provides simple helpers to load Lua modules in a Neovim config or in
your own plugins in a controlled, lazy way.

The goal is to avoid unnecessary `require()` calls at startup and to load modules
only when they are actually needed.

---

## Table of content

- [lib.lua.lazy – Reusable lazy loading for Neovim](#liblazy-reusable-lazy-loading-for-neovim)
  - [Motivation](#motivation)
    - [Load and cache behavior](#load-and-cache-behavior)
    - [Consequences](#consequences)
  - [API](#api)
    - [lazy.module(name)](#lazymodulename)
    - [lazy.require(name)](#lazyrequirename)
    - [lazy.fn(module, function_name)](#lazyfnmodule-function_name)
  - [Performance estimate](#performance-estimate)
    - [Startup](#startup)
    - [Runtime](#runtime)
  - [Safety and correctness](#safety-and-correctness)
  - [When you should not use it](#when-you-should-not-use-it)
  - [Typical use cases](#typical-use-cases)
  - [LSP support and type annotations](#lsp-support-and-type-annotations)
  - [Conclusion](#conclusion)

---

## Motivation

In many Neovim configurations, modules are loaded directly at file scope:

```lua
local mod = require("heavy.module")
```

This means:

* the module is always executed when the file is loaded
* even if the associated function is never used
* startup time and memory usage grow with the config size

`lib.lua.lazy` lets you control this behavior explicitly.

### Load and cache behavior

In Lua:
* `require()` always loads the complete module
* the module is executed exactly once
* the return object is stored in `package.loaded[name]`
* all defined functions are created
* unused functions still remain in memory

Sequence:
1. `require("notify")` is called
2. Lua looks up the module via `package.searchers`
3. the file is read completely
4. all top-level code is executed
5. all functions are created
6. the return object is cached
7. future `require()` calls only return the reference

Important:
* Lua has no partial loading of modules
* there is no automatic tree shaking
* even if only `warn()` is used, `info()`, `debug()` etc. are created as well

---

### Consequences

* side effects in top-level code are always executed
* initialization cost falls entirely on the first `require()`
* module design should be light on initialization
* lazy loading must be implemented manually

---

## API

### lazy.module(name)

Creates a lazy wrapper for a module.

```lua
local lazy = require("lib.lua.lazy")
local mymod = lazy.module("mymodule")

mymod.get().do_work()
```

Properties:

* `require()` is executed exactly once
* the result is cached in an upvalue
* after the first access, minimal overhead (nil check)

**Note on LSP support:**

When using `lazy.module()`, you get a wrapper object of type `Lib.LazyModule`, not the actual module. This means:

* no automatic type inference for the loaded module
* no autocompletion for module functions until `.get()` is called
* you must annotate the type manually after `.get()`

```lua
local mymod_lazy = lazy.module("mymodule")

-- No LSP support here:
-- mymod_lazy is of type Lib.LazyModule

---@type MyModule.Type
local mymod = mymod_lazy.get()

-- Now you have LSP support:
mymod.do_work()
```

For better LSP support, see `lazy.require()`.

---

### lazy.require(name)

Creates a lazily loaded module with direct type-inference support.

```lua
local lazy = require("lib.lua.lazy")

---@type MyModule.Type
local mymod = lazy.require("mymodule")

-- Full LSP support from here on:
mymod.do_work()
```

Properties:

* `require()` is executed exactly once (on the first access to the module)
* the result is cached
* the return value is the module itself, not a wrapper
* full LSP support through the type annotation

**Difference from `lazy.module()`:**

* `lazy.module()` returns a wrapper object (type: `Lib.LazyModule`)
* `lazy.require()` returns the actual module (castable to any type)
* `lazy.require()` is the recommended variant for modules with a complex API

**Usage with type annotations:**

```lua
---@type WkdNvC.UI.Stl.Modules.LSP.Cfg.Module
local config_mod = lazy.require("wkdnvchad.ui.statusline.modules.lsp.config")

-- The LSP now knows all functions:
local options = config_mod.get_cfg()
config_mod.set("debounce_ms", 500)
```

**Technical background:**

`lazy.require()` internally uses `lazy.module()`, but returns the result of `.get()` directly. The `---@diagnostic disable-next-line: return-type-mismatch` annotation in the module allows the language server to assume the generic type `T` that is defined by the type annotation at the call site.

---

### lazy.fn(module, function_name)

Creates a lazily loaded function wrapper.

```lua
local lazy = require("lib.lua.lazy")
local do_work = lazy.fn("mymodule", "do_work")

do_work(42)
```

Properties:

* `require()` runs on the first call
* afterwards the function is re-bound
* no further lazy check in the hot path

This variant is more aggressive and only intended for performance-critical paths.

---

## Performance estimate

### Startup

* the module is not loaded at startup
* less Lua bytecode
* less initialization of secondary logic (autocommands, caches)

### Runtime

* `lazy.module`:
  * a simple nil check per access
  * negligible overhead for most use cases
* `lazy.require`:
  * identical to `lazy.module` (uses the same caching internally)
  * no performance difference
* `lazy.fn`:
  * no additional cost at all after the first call

Compared to eager `require()`, the overall effect in large configs is noticeably
positive, especially with many optional features.

---

## Safety and correctness

* `require()` is not bypassed, only deferred
* Lua's standard caching (`package.loaded`) is fully preserved
* errors in the module surface on the first access, not silently
* no global mutation, only local upvalues

The behavior is deterministic and reproducible.

---

## When you should not use it

* for very small utility modules
* for functions that run on every keypress
* for code that is deliberately meant to produce side effects at startup

Lazy loading is a tool, not a dogma.

---

## Typical use cases

* feature-specific logic
* event handlers
* Neo-tree / LSP / Git integrations
* your own plugins with optional components

---

## LSP support and type annotations

For optimal LSP support with autocompletion and type checking, there are several approaches:

### Variant 1: lazy.require with type annotation (recommended)

```lua
---@type MyModule.Type
local mymod = lazy.require("mymodule")
```

Advantages:
* direct LSP support
* no wrapper indirection
* simplest syntax

### Variant 2: lazy.module with a manual cast

```lua
local mymod_lazy = lazy.module("mymodule")

---@type MyModule.Type
local mymod = mymod_lazy.get()
```

Advantages:
* explicit separation of the lazy wrapper and the module
* useful when you want to pass the lazy wrapper around itself

### Variant 3: inline cast with lazy.module

```lua
---@type MyModule.Type
local mymod = lazy.module("mymodule").get()
```

Disadvantages:
* can lead to type-mismatch warnings
* may require `---@diagnostic disable-next-line`

### Creating type definitions

For your own modules, you should create type definitions in `@types` folders:

```lua
---@meta
---@module 'mymodule.@types'

---@class MyModule.Type
---@field do_work fun(n: integer): string
---@field get_config fun(): MyModule.Config

---@class MyModule.Config
---@field timeout integer
---@field retry boolean

return {}
```

These types can then be used with `lazy.require()` or `lazy.module()`.

---

## Conclusion

`lib.lua.lazy` helps make Neovim configurations:

* more structured
* more performant
* more scalable

without complex infrastructure or external dependencies.

The choice between `lazy.module()` and `lazy.require()` depends on the use case:

* **`lazy.module()`**: when you explicitly want to work with the lazy wrapper
* **`lazy.require()`**: for direct access with optimal LSP support (the default case)
* **`lazy.fn()`**: for individual functions in hot paths

---
