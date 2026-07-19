# `lib.nvim.usercmd.composer`

Compose a declarative route spec into **one** Neovim user command with
subcommands, `<Tab>` completion, and Markdown docs — all read from the same
tree, so behavior and docs can never drift.

Turns the `:VerbFeatureA` / `:VerbFeatureB` anti-pattern into
`:Verb feature-a` / `:Verb feature-b`, where `{Verb}` is the central action
(`:Replace`, `:File`, `:Markdown`). Full design:
[docs/ROADMAP/usrcmd_builder.md](../../../../../docs/ROADMAP/usrcmd_builder.md).

Built on [`lib.nvim.usercmd.create`](../init.lua) (defensive registration),
[`lib.nvim.normalize.validators`](../../normalize/validators.lua) (arg
coercion), and [`lib.nvim.fs`](../../fs) (`PATH`/`DIR`/`FILE` args + docgen
writing).

## Usage

```lua
local composer = require("lib.nvim.usercmd.composer")

composer.verb("Replace", {
  desc    = "Text replacement operations",
  default = function(ctx) require("replacer").replace_prompt() end,   -- bare :Replace
  routes  = {
    { path = { "buffer" }, desc = "Replace within the current buffer",
      run = function(ctx) require("replacer").buffer() end },

    { path = { "cwd" }, args = { { name = "root", type = "DIR", optional = true } },
      desc = "Replace across the working tree (optionally under root)",
      run  = function(ctx) require("replacer").cwd(ctx.args.root) end },

    { path = { "surround" },
      args = {
        { name = "kind",   type = "STRING", enum = { "quote", "paren", "brace" } },
        { name = "target", type = "STRING" },
      },
      desc = "Wrap TARGET with KIND surroundings",
      run  = function(ctx) require("replacer").surround(ctx.args.kind, ctx.args.target) end },
  },
})
```

`composer.verb` registers the command immediately and returns a handle. Now
`:Replace <Tab>` completes `buffer | cwd | surround`, `:Replace surround <Tab>`
completes `quote | paren | brace`, `:Replace cwd <Tab>` completes directories,
and bad input is reported with the route's usage instead of a raw command error.

### Fluent form

Same spec, chained; `:build()` registers.

```lua
composer.verb("Replace")
  :desc("Text replacement operations")
  :default(function(ctx) end)
  :route("buffer", { desc = "…", run = function(ctx) end })
  :route("surround", {
      args = { { name = "kind", type = "STRING", enum = { "quote", "paren", "brace" } },
               { name = "target", type = "STRING" } },
      run  = function(ctx) end })
  :build()
```

### Buffer-local commands

`spec.buffer = true` (current buffer) or an explicit bufnr registers via
`nvim_buf_create_user_command` instead of the global
`nvim_create_user_command` — for per-buffer commands like a markdown
preview's `:TableView`, typically called from a `FileType` autocmd:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    composer.verb("TableView", { buffer = true, routes = { ... } })
  end,
})
```

Re-registering (e.g. the autocmd firing again for the same buffer) is safe —
`nvim_buf_create_user_command` overwrites like the global form does. The
fluent builder has the matching `:buffer(v)` method.

## The handler context (`ctx`)

| Field       | What                                                        |
| ----------- | ---------------------------------------------------------- |
| `ctx.args`  | coerced positional args, keyed by `ArgSpec.name`           |
| `ctx.pos`   | coerced positional args, in order                          |
| `ctx.flags` | coerced `--flag`/`-x` values, keyed by `FlagSpec.name`      |
| `ctx.kv`    | coerced bare `key=value` pairs, keyed by `KvSpec.key`       |
| `ctx.rest`  | leftover tokens beyond the declared schema                 |
| `ctx.path`  | the literal path that matched (e.g. `{ "surround" }`)      |
| `ctx.bang`  | `true` when invoked as `:Verb!`                            |
| `ctx.range` | `{ line1, line2, count, range }` (for range/count commands)|
| `ctx.raw`   | the untouched nvim callback args                           |

## Argument types

Each type carries both validation and completion:

| Type     | Validates                     | Completes                    |
| -------- | ----------------------------- | ---------------------------- |
| `STRING` | any token (default)           | `spec.values` hints, if any  |
| `INT`    | `validators.to_int`           | —                            |
| `FLOAT`  | `validators.to_float`         | —                            |
| `BOOL`   | `validators.to_bool`          | true/false/on/off/yes/no     |
| `enum`   | membership in `spec.enum`     | the enum members             |
| `PATH`   | soft (accepts any)            | file completion              |
| `DIR`    | `fs.is_dir`                   | directory completion         |
| `FILE`   | `filereadable`                | file completion              |
| `BUFFER` | valid bufnr or name match     | listed buffer basenames      |

Register a custom type once:

```lua
composer.register_type("HIGHLIGHT_GROUP", {
  validate = function(raw) return true, raw, nil end,
  complete = function(lead) return vim.fn.getcompletion(lead, "highlight") end,
})
```

`run` may also be a **module path string** instead of a function — required
lazily on first dispatch, so feature modules stay unloaded until their
subcommand fires. The module must return a callable, or a table with a `run`
field.

## Flags (`--flag` / `--flag=value`)

A route may declare `flags`, parsed out of its token tail before positional
binding — modeled on `replacer.nvim`'s `BOOL_FLAGS`/`VALUE_FLAGS` split.
**Strictly opt-in**: a route with no `flags` behaves exactly as before, so a
leading `--` in a positional value is never treated specially unless the
route asks for flag parsing.

```lua
composer.verb("Replace", {
  routes = {
    -- `path = {}` is the verb's root route: it matches even with NO literal
    -- subcommand, so this reproduces replacer.nvim's actual flat grammar —
    -- :Replace {old} {new} [scope] [--flags] — verbatim.
    { path = {},
      args  = { { name = "old", type = "STRING" }, { name = "new", type = "STRING" },
                { name = "scope", type = "STRING", optional = true } },
      flags = {
        { name = "dry",    bool = true },                                   -- --dry
        { name = "type",   type = "STRING", repeatable = true },            -- --type=lua --type=go
        { name = "engine", type = "STRING", enum = { "fzf", "telescope" } },-- --engine=fzf
      },
      run = function(ctx)
        -- ctx.flags.dry == true | nil, ctx.flags.type == {"lua","go"} | nil,
        -- ctx.flags.engine == "fzf" | "telescope" | nil
        require("replacer").run(ctx.args.old, ctx.args.new, ctx.args.scope, ctx.flags)
      end },
  },
})
```

Flags may appear **anywhere** in the tail — before, after, or between
positionals (`:Replace --dry foo bar` and `:Replace foo bar --dry` are
equivalent) — and a literal `--` stops flag parsing, so everything after it is
positional even if it looks flag-shaped (matches replacer.nvim's
`flags_done` sentinel). A value flag accepts either `--name=value` or
`--name value`. An undeclared `--name` is a hard error (same fail-loud stance
as a bad positional arg), not silently swallowed as a positional.

`<Tab>` completes flag names (`--<Tab>` → every declared flag) and, after
`--name=`, the flag's own value completer (enum members, file paths, …) —
derived from the same `FlagSpec`, so nothing is completion-only or
dispatch-only.

**Known limitation**: completion is ambiguous for a verb that mixes a
`path = {}` root route *with* sibling subcommand routes on the same verb —
an unusual combination (a flat-grammar verb normally has no subcommand
children at all). Dispatch is unaffected; only the `<Tab>` suggestion in that
mixed case can be unhelpful.

### Short-flag aliases (`-x`)

A flag may declare a single-char `short` alias:

```lua
flags = {
  { name = "replace", short = "r", bool = true },   -- --replace or -r
  { name = "output",  short = "o", type = "STRING" },-- --output=<v> or -o <v> (next-token only, no -o=v)
}
```

`-x` and `--name` are interchangeable and may be mixed in the same call
(`:Recommend query -r --output=out.txt`). Short flags only take their value
from the **next token** (`-o file.txt`), never `-o=file.txt` — that's the
long form's job. An unrecognized `-x` (no `short` matches) is left as an
ordinary positional rather than an error — unlike `--name`, a bare `-` prefix
collides too easily with legitimate values (a negative number, a passthrough
CLI arg). `<Tab>` after a bare `-` completes every declared short flag.

## Bare `key=value` (no dashes)

A route may separately declare `kv`, for grammars like
`:Diff target=file.lua view=vsplit` (no `--`/`-` prefix at all):

```lua
composer.verb("Diff", {
  routes = {
    { path = {},
      kv = {
        { key = "target", type = "STRING" },
        { key = "view", type = "STRING", enum = { "vsplit", "split" }, default = "vsplit" },
      },
      run = function(ctx)
        -- ctx.kv.target, ctx.kv.view (defaults applied when omitted)
      end },
  },
})
```

Unlike `flags`, an **undeclared** `key=value`-shaped token is left as an
ordinary positional rather than an error — `=` shows up in too many
legitimate positional values (URLs, passthrough env assignments, …) to treat
every match as an intentional kv pair; only a token whose key matches a
*declared* `KvSpec.key` is ever consumed. `<Tab>` offers `key=` for every
declared key, and value completion after `key=` — kv tokens have no marker
prefix, so these candidates are merged alongside whatever else is valid at
that slot (a subcommand name, a positional arg's own completions, …), not
used exclusively. `flags` and `kv` compose freely on the same route
(`ctx.flags` and `ctx.kv` are both populated; parsing runs flags first, then
kv, then whatever's left binds to `args`).

## Documentation generation

The route tree drives docs too:

```lua
handle:document()                 -- one verb → docs/BINDINGS/Usercmds.md
handle:document("docs/CMDS.md")   -- explicit path
composer.document()               -- every registered verb → default path
```

`composer.setup({ docs = { path = "docs/BINDINGS/Usercmds.md", mode = "replace" } })`
sets the default path and mode. `mode = "section"` updates a delimited
`<!-- lib.nvim:composer --> … <!-- /lib.nvim:composer -->` block inside a larger
file so hand-written prose survives regeneration; `"replace"` (default)
overwrites the whole file.

## Access

```lua
require("lib.nvim.usercmd.composer")   -- direct (most efficient)
require("lib").composer                -- via aggregator
require("lib").usercmd.composer        -- via the usercmd namespace
```
