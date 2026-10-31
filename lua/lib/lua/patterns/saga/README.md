# `lib.lua.patterns.saga`

> Pattern: Saga · Group: modern · Stage: `idea`
> Status: idea pool — may bring no benefit in Lua, kept as a reference.

A multi-step process where each step has a compensating step; on failure the completed steps are compensated in reverse.

## The pattern in one paragraph

Steps share one `ctx` table. If step N fails, the compensations of steps N-1 down to 1 run (each under `pcall`; a failing compensation is reported but does not stop the others). The result carries a per-step report: `done`, `failed`, `compensated`, `compensation_failed`, `skipped`.

## Usage

```lua
local saga = require("lib.lua.patterns.saga")

local ok, err, report = saga.run({
  { name = "reserve", run = function(c) c.id = reserve() end, compensate = function(c) release(c.id) end },
  { name = "charge", run = function(c) charge(c.id) end, compensate = function(c) refund(c.id) end },
}, {})
```

## API

| Function | Does |
| --- | --- |
| `run(steps, ctx)` | `true, ctx` or `false, err, report` |

## When it helps / when it does not (Lua view)

- **Helps when:** a process spans systems that cannot share a transaction (remote calls, several files, an external tool) and a failure must leave no half-done work.
- **Does not help when:** everything happens inside one editor session; use `lib.lua.context_manager` (try/finally) or `lib.lua.patterns.unit_of_work`. This module may bring no benefit.
- **Cheaper alternative in Lua:** a list of undo closures that you run on error.

## Related

- `lib.lua.patterns.unit_of_work`, `lib.lua.patterns.command` (undo of user actions), `lib.nvim.patterns.retry_backoff`.

## Tests

`TESTS/patterns_saga_spec.lua`: success, reverse compensation, report states, failing compensation, steps without compensate.
