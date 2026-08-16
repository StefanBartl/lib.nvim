# `lib.lua.context_manager`

Lua's missing try/finally as one small composable primitive, pure Lua — no
`vim` API. Built on [`lib.lua.error.safe_call`](../error/README.md) for the
actual pcall + multi-return-safe forwarding; this module only adds the
"guarantee `release` runs" contract on top.

No existing module in this codebase has a generic "acquire a scarce
resource, guarantee its release" primitive —
[`lib.nvim.fs.dir_guard`](../../nvim/fs/dir_guard/README.md)'s
`handle.bypass(fn)` is the closest prior art (pcall-wraps a body,
unconditionally restores state after), but it's scoped to that one module.
Not retrofitted onto `dir_guard`/`cache`/`lock` here — they keep their
current shape; this is a new primitive for future callers.

## Usage

```lua
local with = require("lib.lua.context_manager").with

local ok, result_or_err = with(function()
  return io.open("/tmp/x.txt", "w") -- acquire: resource, err
end, function(f)
  f:close() -- release: always runs, even if body errors
end, function(f) -- body
  f:write("hello\n")
  return "done"
end)
```

## Semantics

- `acquire()` returns `resource, err`. If `resource` is `nil`, `with`
  short-circuits: `release` is **never called** (there is nothing to
  release), and `with` returns `false, err`.
- `body(resource)` runs under `pcall` (via `lib.lua.error.safe_call`).
- `release(resource)` **always** runs afterward if `acquire` succeeded,
  whether `body` returned normally or errored.
- On success: `true, body`'s return value(s) (multiple values forwarded
  correctly, including embedded `nil`s — the same LuaJIT-safe
  `table.pack`/`unpack` machinery `lib.lua.error.safe_call` uses).
- On a `body` error: `false, err` — a structured `LibErrorValue`
  (`kind = "runtime_error"`), same as `lib.lua.error.safe_call`'s own
  failure shape — returned **after** `release` has already run.

## Returns

| Function                       | Returns        | Meaning                                                          |
|-----------------------------------|-----------------|----------------------------------------------------------------------|
| `M.with(acquire, release, body)`   | `boolean, ...`  | `true` + `body`'s results on success; `false` + error on `acquire`/`body` failure |
