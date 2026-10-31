# `lib.lua.patterns.interpreter`

> Pattern: Interpreter · Group: behavioral · Stage: `idea`
> Status: idea pool — may bring no benefit in Lua, kept as a reference.

Evaluate a small grammar by walking its tree with one rule per node type.

## The pattern in one paragraph

A mini-language is represented as a tree of nodes, and each node type has an evaluation rule that recurses into its children. Parsing is not part of this module: the tree comes from wherever you build it. `new(rules)` returns `eval(node, env)`; a rule is `fn(node, eval, env)`.

## Usage

```lua
local interpreter = require("lib.lua.patterns.interpreter")

local eval = interpreter.new({
  num = function(n) return n.value end,
  add = function(n, ev, env) return ev(n.left, env) + ev(n.right, env) end,
  var = function(n, _, env) return env[n.name] end,
})
eval({ type = "add", left = { type = "num", value = 1 }, right = { type = "var", name = "x" } }, { x = 41 }) --> 42
```

## API

| Function | Does |
| --- | --- |
| `new(rules)` | returns `eval(node, env)`; unknown or missing `type` raises |

## When it helps / when it does not (Lua view)

- **Helps when:** a real mini-language with several node types exists (filter expressions, query syntax) and must be evaluated against different environments.
- **Does not help when:** a pattern match or a single `load()`ed Lua expression (with a sandboxed environment) does the job. This module may bring no benefit.
- **Cheaper alternative in Lua:** `lib.lua.range` shows the small-grammar case done with plain parsing code.

## Related

- Visitor (same dispatch by node type, but for operations over a tree), Strategy.

## Tests

`TESTS/patterns_interpreter_spec.lua`: leaf, binary and nested nodes, environment, unknown/missing types.
