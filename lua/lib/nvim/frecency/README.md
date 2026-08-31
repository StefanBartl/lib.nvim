# lib.nvim.frecency

---

## Overview

`lib.nvim.frecency` ranks strings by **how often** and **how recently** they
were chosen, and persists that across restarts. It is the signal behind "the
thing you keep picking shows up first".

It knows nothing about what a key means. File paths, alternate candidates,
command names — it ranks strings, which is what lets one implementation serve
a file picker and a path resolver at the same time.

Guiding ideas:

* **one handle per namespace** — a store *is* its file, so `store()` returns
  the same handle for the same directory/namespace pair rather than handing
  out two in-memory copies that overwrite each other on flush
* **buckets, not a decay curve** — a visit is worth 100 within the hour, 80
  within the day, 60 within the week, 40 within the month, 20 after that.
  Legible in a way an exponent is not: nobody has to reason about a half-life
  to predict what a list will do
* **log-dampened frequency** — one path opened three hundred times does not
  permanently own the top of every list
* **lazy** — a store that is opened but never used reads nothing from disk

---

## Module structure

```
lib.nvim.frecency/
├── init.lua      -- store(): the handle, scoring, persistence, autoflush
└── @types/       -- LuaLS types (Lib.Frecency.*)
```

---

## Usage

```lua
local frecency = require("lib.nvim.frecency")

local visits = frecency.store({ namespace = "gopath-alternates" })

-- The user picked this candidate out of a list:
visits:record("/home/me/project/lua/config.lua")

-- Rank a fresh set of candidates. Keys that were never recorded are absent
-- from the result, not present with a zero.
local bonus = visits:lookup({ "/a/config.lua", "/a/confog.lua" })
for path, score in pairs(bonus) do
  -- fold `score` into whatever primary score you already have
end
```

Visits live in memory until they are written. `flush()` does that, and by
default a `VimLeavePre` autocmd calls it for you.

---

## Options

| Field       | Type      | Default                                    | Meaning |
| ----------- | --------- | ------------------------------------------ | ------- |
| `namespace` | `string`  | **required**                               | Names the store and its file. One flat, filesystem-safe identifier — used in the path unsanitised, the same contract `lib.nvim.cache.disk` states for its namespaces. |
| `dir`       | `string`  | `stdpath("data")/lib.nvim/frecency`        | Parent directory. |
| `weight`    | `number`  | `1.0`                                      | Multiplier applied by `lookup`, so a consumer decides how far frecency may move a result. |
| `autoflush` | `boolean` | `true`                                     | Register a `VimLeavePre` flush. |

**Two consumers must not share a namespace.** A picker ranking file paths and
a resolver ranking alternates would otherwise train each other's rankings —
the same string means something different in each.

---

## API

| Function            | Returns                                                       |
| ------------------- | ------------------------------------------------------------- |
| `store(opts)`       | `Lib.Frecency.Store` — the handle for that namespace          |
| `store:record(key)` | –  count a visit (in memory; `flush` persists)                |
| `store:score(key)`  | `number` — `0` for a key never recorded                       |
| `store:lookup(keys)`| `table<string, number>` — weighted scores, zeroes omitted     |
| `store:flush()`     | –  write pending visits; no-op when nothing changed           |
| `store:clear()`     | –  forget everything, in memory and on disk                   |
| `store:reset()`     | –  test-only: drop the in-memory copy, leave the file alone   |

---

## Notes

- **Why `stdpath("data")` and not `stdpath("cache")`.** These counts are
  earned over months of real use and cannot be regenerated. A cache directory
  promises the opposite, and some systems clear it.
- Persistence goes through [`lib.nvim.cache.disk`](../cache/README.md), which
  already owns namespaced, `pcall`-guarded JSON with directory creation. There
  is no second copy of that logic here.
- `score()` never touches disk after the first load — it is a table lookup,
  cheap enough to call once per candidate while ranking a query.
- The on-disk form is one entry per key, `{ count, last }`, so a store written
  by an older version stays readable.

---

## Used by

- [`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim) — the `smart`
  action's file ranking. This module is that implementation, extracted.
- [`gopath.nvim`](https://github.com/StefanBartl/gopath.nvim) — alternate-file
  candidates, ordered by what you actually chose before.
