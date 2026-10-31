# `lib.lua.patterns.repository`

> Pattern: Repository · Group: modern · Stage: `idea`
> Status: idea pool — may bring no benefit in Lua, kept as a reference.

A collection-like API (`get`, `save`, `remove`, `find`, `filter`, `count`) over a store with four primitives; `memory()` is an in-memory store.

## The pattern in one paragraph

Code asks a repository for entries and never touches the storage. Any table with `get(id)`, `put(id, value)`, `delete(id)` and `all()` works as store (optional `count()` and `each(fn)`, where `fn(id, value)` returns true to stop, make `count`, `find` and `filter` skip the copy of the whole store; `memory()` has both), so the data can live in a table, a JSON file or `lib.nvim.store`, and tests use `memory()`.

## Usage

```lua
local repository = require("lib.lua.patterns.repository")

local users = repository.new(repository.memory())
users:save("u1", { name = "Ada" })
users:find(function(u) return u.name == "Ada" end) --> { id = "u1", value = { name = "Ada" } }
```

## API

| Function | Does |
| --- | --- |
| `memory()` | in-memory store (insertion order) |
| `new(store)` | validates the four primitives |
| `r:get(id)` / `r:save(id, v)` / `r:remove(id)` | single entries (`save` rejects `nil`) |
| `r:all()` / `r:find(pred)` / `r:filter(pred)` / `r:count()` | queries |

## When it helps / when it does not (Lua view)

- **Helps when:** the storage may change (memory, JSON, SQLite) or must be faked, and several modules query it.
- **Does not help when:** one JSON file is read and written by one module; two functions are simpler. This module may bring no benefit.
- **Cheaper alternative in Lua:** a module-local table with accessor functions; `lib.nvim.store` for project-scoped persistence.

## Related

- `lib.nvim.store`, `lib.lua.patterns.unit_of_work` (batches writes to a store), Adapter.

## Tests

`TESTS/patterns_repository_spec.lua`: CRUD, order, find/filter, predicate arguments, custom store.
