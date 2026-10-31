# Pattern README template

Copy this into `lua/lib/<lua|nvim>/patterns/<name>/README.md` and fill every section. Keep the order so the
pattern READMEs read the same. Delete nothing; write "none" where a section does not apply.

````markdown
# `lib.<lua|nvim>.patterns.<name>`

> Pattern: <Name> · Group: <creational|structural|behavioral|modern> · Stage: `<impl|idea>`
> Status: <stable | idea pool — may bring no benefit in Lua, kept as a reference>

One sentence: what the module does.

## The pattern in one paragraph

Intent, in plain words, and the classless Lua form (closure, function table, module table) it takes here.
Link: https://refactoring.guru/design-patterns/<slug> (GoF) or a short source for modern patterns.

## Usage

```lua
local <name> = require("lib.<lua|nvim>.patterns.<name>")

-- the smallest realistic example
```

## API

| Function | Does |
| --- | --- |

## When it helps / when it does not (Lua view)

- **Helps when:** concrete trigger (e.g. an if/elseif ladder on a type string with five or more branches).
- **Does not help when:** concrete counter-case (e.g. two variants, no growth expected).
- **Cheaper alternative in Lua:** the plain construct that often suffices.
- For `idea` modules: say plainly that the pattern may give no benefit here and why it is kept.

## Related

- Neighbouring patterns and lib.nvim modules (`lib.nvim.hooks`, `lib.nvim.registry`, …) and when to pick which.
- Where the author's plugins use or could use it (from the design-pattern index), as `repo/path`.

## Tests

`TESTS/patterns_<name>_spec.lua` — what is covered.
````
