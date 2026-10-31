# `lib.lua.patterns.bridge`

> Pattern: Bridge · Group: structural · Stage: `idea`
> Status: idea pool — may bring no benefit in Lua, kept as a reference.

Bind an abstraction (functions taking an implementor first) to an implementor and check the required primitives up front.

## The pattern in one paragraph

Two things vary independently: *what* is done (report kinds) and *where/how* (output targets). Instead of one class per combination, the abstraction is written against a small set of primitives and any implementor providing them can be plugged in.

## Usage

```lua
local bridge = require("lib.lua.patterns.bridge")

local report = {
  title = function(out, text)
    out.line(text)
    out.line(("="):rep(#text))
  end,
}
local r = bridge.new(report, to_buffer, { "line" })
r.title("Hello")
```

## API

| Function | Does |
| --- | --- |
| `new(abstraction, impl, required)` | table of bound functions; raises if `impl` lacks a required primitive |

## When it helps / when it does not (Lua view)

- **Helps when:** two axes of variation are real (several report kinds times several outputs) and combinations would otherwise multiply.
- **Does not help when:** there is one axis; Lua's first-class functions make a strategy table simpler. This module may bring no benefit.
- **Cheaper alternative in Lua:** pass the output table as a parameter, `report.title(out, text)`.

## Related

- Strategy, Adapter, `lib.nvim.output` (channel-agnostic output facade, close to a bridge in practice).

## Tests

`TESTS/patterns_bridge_spec.lua`: same abstraction on two implementors, return values, missing primitive.
