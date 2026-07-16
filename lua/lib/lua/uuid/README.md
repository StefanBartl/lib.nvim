# `lib.lua.uuid`

UUIDv4 generation and formatting, pure Lua. Seeded once at module load via
`math.randomseed`. This is **not cryptographically secure** — it provides
just enough entropy for typical UI/temp-id use (list keys, scratch buffer
names, log request ids, …), not for anything security-sensitive.

## Usage

```lua
local uuid = require("lib.lua.uuid")

local id = uuid.generate()
-- id = "3f9a2b10-7c4e-4d21-9a3f-6b5e0c8d1a44" (random each call)

uuid.format(id, "compact")
-- "3f9a2b107c4e4d219a3f6b5e0c8d1a44"

uuid.format(id, "upper")
-- "3F9A2B10-7C4E-4D21-9A3F-6B5E0C8D1A44"

uuid.format(id, "braced")
-- "{3f9a2b10-7c4e-4d21-9a3f-6b5e0c8d1a44}"

local braced_id = uuid.get("braced")
-- one-shot: generate + format
```

## Returns

| Function      | Returns                                             |
| ------------- | ---------------------------------------------------- |
| `generate()`  | `string` — lowercase, hyphenated UUIDv4               |
| `format(u,s)` | `string` — transformed presentation of `u`            |
| `get(s)`      | `string` — `format(generate(), s)`                    |
