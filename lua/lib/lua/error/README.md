# `lib.lua.error`

A small structured-error and safe-call-with-traceback convention, pure Lua.
`M.new`/`M.is` give a shared shape for error values passed around as data
(instead of raw strings); `M.safe_call` is an `xpcall` wrapper that captures
a full `debug.traceback` on failure and forwards multiple return values on
success.

## Usage

```lua
local err = require("lib.lua.error")

local e = err.new("not_found", "config file missing", { path = "/etc/x.conf" })
-- e = { kind = "not_found", message = "config file missing", data = { path = "/etc/x.conf" }, __lib_error = true }

err.is(e)        -- true
err.is({ oops = 1 }) -- false

local function risky(a, b)
  if a == nil then
    error("a is required")
  end
  return a + b, "extra"
end

local ok, sum, extra = err.safe_call(risky, 1, 2)
-- ok = true, sum = 3, extra = "extra"

local ok2, failure = err.safe_call(risky, nil, 2)
-- ok2 = false
-- failure.kind = "runtime_error"
-- failure.message = "<file>:<line>: a is required\nstack traceback:\n  ..."
```

## Returns

| Function          | Returns                                                                 |
| ------------------ | ------------------------------------------------------------------------ |
| `new(k, m, d)`      | `LibErrorValue` table                                                    |
| `is(v)`             | `boolean`                                                                 |
| `safe_call(fn,...)` | `true, <fn's return values...>` on success; `false, LibErrorValue` on failure |
