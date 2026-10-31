# `lib.lua.patterns.unit_of_work`

> Pattern: Unit of Work · Group: modern · Stage: `idea`
> Status: idea pool — may bring no benefit in Lua, kept as a reference.

Queue changes to a store and apply them together; if one fails, restore what was already applied.

## The pattern in one paragraph

`add`, `change` and `remove` only queue. `commit()` applies the queue in order against a store with `get/put/delete` (see `lib.lua.patterns.repository`). A failing step reverts the applied steps in reverse using the values read just before each step, and returns `false, err, failed_step`. `rollback()` drops the queue. The revert covers only what this unit itself wrote; it is not a database transaction.

## Usage

```lua
local repository = require("lib.lua.patterns.repository")
local unit_of_work = require("lib.lua.patterns.unit_of_work")

local uow = unit_of_work.new(repository.memory())
uow:add("a", 1):change("b", 2):remove("c")
local ok, err, step = uow:commit()
```

## API

| Function | Does |
| --- | --- |
| `new(store)` | store needs `get`, `put`, `delete` |
| `u:add(id, v)` / `u:change(id, v)` / `u:remove(id)` | queue (chainable) |
| `u:pending()` / `u:rollback()` / `u:commit()` | inspect / drop / apply |

## When it helps / when it does not (Lua view)

- **Helps when:** a user action changes several entries (rename plus index update) and a half-applied result would be a bug.
- **Does not help when:** writes are independent or the store has its own transaction; use that. Not safe against concurrent writers.
- **Cheaper alternative in Lua:** apply the steps in a function and undo by hand on error, or `lib.lua.context_manager`.

## Related

- `lib.lua.patterns.repository`, `lib.lua.patterns.saga` (compensation across systems), `lib.nvim.checkpoint` (file snapshots).

## Tests

`TESTS/patterns_unit_of_work_spec.lua`: queue then apply, rollback, failure revert (new/changed/removed), queue cleared.
