# lib.lua.memo

---

## Overview

The `lib.lua.memo` module provides a small, self-contained caching infrastructure for Neovim Lua code.
The focus is on:

* predictable memory usage
* constant runtimes
* clear, explicit semantics
* easy integration into existing `lib.*` helper modules

The module is deliberately implemented independently of Neovim-specific APIs and can therefore also be used in a pure Lua context, but it is particularly suited for:

* wrappers around expensive Neovim APIs
* memoization of pure helper functions
* caching of computed configurations
* reducing overhead on repeated `require`-like accesses

---

## Module structure

```
lib.lua.memo/
├── init.lua        -- aggregated export
├── lru.lua         -- LRU cache implementation
└── memo.lua        -- memoization based on the LRU cache
```

The entry point is always `require("lib.lua.memo")`.

---

## lib.lua.memo (aggregator)

The top-level module bundles the individual cache strategies under a common namespace.

Available submodules:

| Field | Description                          |
| ----- | ------------------------------------ |
| lru   | LRU cache with O(1) access           |
| memo  | memoization helper based on LRU      |

Example:

```lua
local cache = require("lib.lua.memo")

local lru = cache.lru.new(64)
local memoize = cache.memo.memoize
```

---

## lib.lua.memo.lru

### Purpose

`lib.lua.memo.lru` implements a classic least-recently-used cache with:

* O(1) access (`get`)
* O(1) insertion (`put`)
* a deterministic memory limit
* a hashmap + doubly linked list

This makes the cache particularly suited for:

* function results
* expensive computations
* normalization steps
* small, frequently used data sets

---

### Data model

Internally the cache consists of:

* a map `key -> node`
* a doubly linked list for order management
* `head`: the most recently used element
* `tail`: the element not used for the longest time

---

### API

#### new(capacity)

Creates a new LRU cache.

* `capacity` must be ≥ 1
* when exceeded, the oldest element is automatically removed

```lua
local LRU = require("lib.lua.memo.lru")

local cache = LRU.new(128)
```

---

#### get(key)

Reads a value from the cache.

* moves the entry to the head (most-recent)
* returns `nil` if the key does not exist

```lua
local value = cache:get("foo")
```

---

#### put(key, value)

Stores a value in the cache.

* overwrites existing entries
* moves the entry to the head
* automatically removes the LRU element on overflow

```lua
cache:put("foo", 42)
```

---

## lib.lua.memo.memo

### Purpose

`lib.lua.memo.memo` provides a memoization wrapper based on the LRU cache.

It is suited for:

* pure functions
* deterministic helper functions
* wrappers around expensive computations
* functions with small, primitive arguments

---

### memoize(fn, cap, keyer)

Creates a memoized variant of a function.

Parameters:

| Parameter | Meaning                                     |
| --------- | ------------------------------------------- |
| fn        | function to memoize                         |
| cap       | maximum cache size (default: 128)           |
| keyer     | optional function for key generation        |

By default, the cache key is generated from the function arguments.

---

#### Example without keyer

```lua
local memo = require("lib.lua.memo.memo")

local slow_fn = memo.memoize(function(a, b)
  return a * b
end, 64)
```

---

#### Example with keyer

Recommended for:

* tables
* complex arguments
* values that are not uniquely stringifiable

```lua
local memo = require("lib.lua.memo.memo")

local fn = memo.memoize(
  function(tbl)
    return tbl.x + tbl.y
  end,
  128,
  function(tbl)
    return tbl.x .. ":" .. tbl.y
  end
)
```

---

### Limitations

* default keying uses `table.concat({ ... })`
* a `nil` return value is not cached
* not suitable for side effects
* arguments should be deterministic

---

## Typical use cases in Neovim

* caching `vim.fn.expand`, `vim.fn.resolve`
* memoization of path normalizations
* reuse of computed highlight definitions
* optimization of LSP or Tree-sitter helper functions
* wrappers around expensive Lua pattern matches

---

## Design decisions

* an explicit capacity limit instead of an unbounded cache
* no weak tables, for maximum predictability
* no automatic expiring (TTL)
* a simple, readable implementation instead of micro-optimization
* full LuaLS compatibility

---

## Feature roadmap (proposals)

### Short-term

* `peek(key)`
  read without updating the LRU order

* `clear()`
  fully empty the cache

* `len()`
  current number of stored entries

---

### Mid-term

* optional TTL support
  time-based invalidation in addition to the LRU strategy

* `invalidate(predicate)`
  selective removal of keys

* statistics API
  hits, misses, evictions

---

### Long-term

* weak-key / weak-value variants
  for GC-friendly special cases

* shared cache registry
  multiple memoizers share the same LRU

* async/deferred integration
  combination with `vim.schedule` or `vim.uv`

---

## Scope

`lib.lua.memo` is deliberately not a generic data-structure framework.
It provides targeted, pragmatic tools for real Neovim configurations and complements other `lib.*` modules such as:

* `lib.nvim.fs`
* `lib.schedule`
* `lib.nvim.require`
* `lib.nvim.notify`

---
