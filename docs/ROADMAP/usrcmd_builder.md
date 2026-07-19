# Concept: subcommand user commands — `:Verb [option] [option] …`

> Status: **concept / design proposal** (no code yet). Module name is decided:
> **`composer`** (deliberately not `verb` — it *composes* a verb's routes into
> a command; it isn't itself a verb, see [§11](#11-decisions)). Default docs
> path is decided: **`docs/BINDINGS/Usercmds.md`**. Everything here is pure
> `vim.api` / `vim.fn` (completion + `nargs="*"` parsing); no shell-outs,
> cross-platform.

## 1. Purpose

Plugins keep re-solving the same command-surface problem. The *bad* pattern is
one flat command per feature:

```
:ReplacerBuffer   :ReplacerCwd   :ReplacerSurroundQuote   :ReplacerSurroundParen …
```

The *good* pattern is one **verb** with sub-options and completion:

```
:Replace buffer …
:Replace surround quote <word>
:Replace surround paren <word>
```

Every plugin the author maintains lands somewhere on this spectrum —
`fileops.nvim` is already ideal (one `:File [options?]`), `open.nvim` has four
verbs (`:Copy` `:Insert` …), `markdown.nvim` mixes a verb (`:Markdown …`) with a
one-off (`:TableView`). The construction is **always the same**: a token tree,
a router that walks it, and a `complete` function derived from that same tree.
That repetition is exactly what a library abstraction should absorb. (A survey
of the author's other `.nvim` plugins for this exact pattern is in
[§13](#13-survey-of-existing-nvim-plugins).)

`{Verb}` is the *central action*, not the repo name: `replacer.nvim` →
`:Replace` / `:Surround`; `fileops.nvim` → `:File`; `markdown.nvim` →
`:Markdown`. The module produces those verbs from a declarative spec and gives
three things for free:

1. **Dispatch** — `:Verb a b c ARG` routes to the right handler.
2. **Completion** — `<Tab>` completes subcommands *and* typed arguments,
   derived from the spec (no hand-written `complete` function).
3. **Documentation** — extract a Markdown reference of every verb/route on
   demand (`document()`), path-configurable.

## 2. Design principles

- **Build on what exists, don't fork it.** Registration goes through
  [`lib.nvim.usercmd.create`](../../lua/lib/nvim/usercmd/init.lua) — it already
  gives the defensive `pcall` wrapper, `force = true` idempotency, and
  `[lib.nvim.usercmd]` notify. This module only adds the *tree + completion +
  parsing* layer on top; it never calls `nvim_create_user_command` directly.
- **Argument coercion reuses the normalizers.** Typed args
  (`INT`/`BOOL`/`FLOAT`/…) validate and coerce through
  [`lib.nvim.normalize.validators`](../../lua/lib/nvim/normalize/validators.lua)
  (`to_int`, `to_bool`, `to_enum`, …); `PATH`/`DIR`/`FILE` go through
  [`lib.nvim.fs`](../../lua/lib/nvim/fs) (`is_dir`, `path`). No bespoke parsing.
- **Declarative first, fluent as sugar.** The primary surface is a plain spec
  table (serializable → that is what makes docgen trivial). A thin fluent
  wrapper sits on top for people who prefer chaining. Both compile to the same
  internal spec.
- **The spec is the single source of truth.** Routing, completion, and docs
  are three *readers* of one tree. There is no second place to keep in sync —
  the docgen requirement in the sketch is only cheap *because* the tree already
  holds every route, arg type, and description.
- **Config follows the repo pattern.** A module-level registry + `setup()` for
  doc defaults, mirroring the `lib.config` shape. No hidden global command
  state beyond that registry.

## 3. Where it lives

```
lib.nvim.usercmd            ← low-level create() wrapper (unchanged)
lib.nvim.usercmd.composer   ← NEW: verb/subcommand composer + completion + docgen
lib.nvim.normalize.*        ← reused for typed-arg coercion
lib.nvim.fs.*               ← reused for PATH/DIR/FILE args + completion
```

Rationale: this is squarely a *user-command* concern, so it nests under the
existing `usercmd` namespace as a sibling to `create`. `lib.nvim_usrcmds` (the
app-level command registrations — `:CwdHere`, `:PowershellProfile`) stays a
*consumer*; it is the natural first dogfooding target (see [§9](#9-dogfooding-nvim_usrcmds)).

## 4. The spec model

A **verb** is a tree of **routes**. A route is a *path of literal tokens*
optionally ending in a *positional argument schema*, bound to a `run` handler.

```lua
---@class Lib.UserCmd.Composer.ArgSpec
---@field name  string                          # shown in usage/help
---@field type  Lib.UserCmd.Composer.ArgType    # "STRING"|"INT"|"BOOL"|"FLOAT"|"PATH"|"DIR"|"FILE"|"BUFFER"
---@field enum? string[]                        # closed set (overrides type for completion/validation)
---@field optional? boolean                     # default false
---@field default? any

---@class Lib.UserCmd.Composer.Route
---@field path  string[]                        # literal subcommand tokens, e.g. { "surround", "quote" }
---@field args? Lib.UserCmd.Composer.ArgSpec[]  # positional args after the path
---@field run   fun(ctx: Lib.UserCmd.Composer.Ctx)
---@field desc? string
---@field bang? boolean                         # this route honors :Verb! …
---@field range? boolean|integer

---@class Lib.UserCmd.Composer.Ctx
---@field args  table<string, any>              # coerced positional args, keyed by ArgSpec.name
---@field pos   any[]                           # coerced args, positional
---@field rest  string[]                        # leftover tokens beyond the schema
---@field bang  boolean
---@field range { line1: integer, line2: integer, count: integer }
---@field raw   Lib.UserCommand.Args            # the untouched nvim callback args
```

Argument **types** are the extension point that carries *both* validation and
completion:

| Type       | Validates via                       | Completes via                          |
| ---------- | ----------------------------------- | -------------------------------------- |
| `STRING`   | — (any token)                       | route-supplied `values`/none           |
| `INT`      | `validators.to_int`                 | none                                   |
| `FLOAT`    | `validators.to_float`               | none                                   |
| `BOOL`     | `validators.to_bool`                | `true/false/on/off/yes/no`             |
| `enum`     | membership check                    | the enum members                       |
| `PATH`     | `fs` existence (soft)               | `complete = "file"` semantics          |
| `DIR`      | `fs.is_dir`                         | dir-only path completion               |
| `FILE`     | readable-file check                 | file path completion                   |
| `BUFFER`   | buffer lookup                       | listed buffer names                    |

New types are a table `{ validate = fn, complete = fn }` registered once — so a
plugin can add e.g. a `HIGHLIGHT_GROUP` type without touching the core.

## 5. Author-facing API

### 5a. Declarative (primary)

```lua
local composer = require("lib.nvim.usercmd.composer")

composer.verb("Replace", {
  desc    = "Text replacement operations",
  -- bare `:Replace` with no args:
  default = function(ctx) require("replacer").replace_prompt() end,
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
}) -- registers the :Replace command immediately
```

This makes the sketch's intent — `{ "viewer", "large", "PATH" } = vw` — express
as a real, type-checkable route:

```lua
{ path = { "viewer", "large" }, args = { { name = "path", type = "PATH" } }, run = vw }
--                                       :MyFeature viewer large c:\repos
```

### 5b. Fluent (sugar over the same spec)

```lua
composer.verb("Replace")
  :desc("Text replacement operations")
  :default(function(ctx) … end)
  :route({ "buffer" }, { desc = "…", run = … })
  :route({ "surround" }, {
      args = { { name = "kind", type = "STRING", enum = { "quote", "paren", "brace" } },
               { name = "target", type = "STRING" } },
      run  = … })
  :build()   -- fluent form is lazy; :build() registers
```

Both forms return a **handle** with `:document(path?)`, `:name()`, and the
resolved spec, and both auto-register the verb into the module registry used by
docgen ([§7](#7-documentation-generation)).

## 6. The completion engine (the core value-add)

`nvim_create_user_command` hands the `complete` callback
`(arg_lead, cmd_line, cursor_pos)`. The engine:

1. tokenizes `cmd_line` (minus the command word and minus the in-progress
   `arg_lead`) → the already-committed tokens;
2. walks the spec tree consuming those tokens: each literal advances into a
   child; when the tree runs out of literal children the *next* slot is an
   **argument slot**;
3. completes the **current** slot:
   - **subcommand slot** → the child literal keys whose prefix matches
     `arg_lead` (plus, if the current node has a `run`, nothing extra — it's a
     valid stopping point);
   - **argument slot** → that `ArgSpec`'s completer (enum members, `BOOL`
     words, path/dir/file completion via Neovim's file completion, buffer
     names, or a route-supplied `values` list).

Because it is 100% derived from the tree, adding a route or an arg type
*automatically* extends completion. This is the piece that is annoying to write
by hand every time and the main reason the abstraction earns its keep.

Edge cases handled once, centrally: ambiguous prefixes, `:Verb <Tab>` at depth
0, completion *after* a fully-consumed schema (offer nothing / `rest`), and
`bang` routes.

## 7. Documentation generation

Every registered verb sits in a module registry, so docs can be emitted per-verb
or for the whole plugin at once — matching the sketch's
`builder.createDocumentation()` / `createDocumentation("NeuerPfad")`:

```lua
-- one verb:
handle:document()                                  -- default path: docs/BINDINGS/Usercmds.md
handle:document("docs/CUSTOM.md")                  -- explicit path

-- everything registered in this process (all verbs of the plugin):
composer.document()                                -- default path: docs/BINDINGS/Usercmds.md
composer.document("docs/CUSTOM.md")                -- explicit path
```

Output is a deterministic Markdown reference generated by walking each route:

```markdown
## :Replace

Text replacement operations.

| Invocation                              | Description                          |
| --------------------------------------- | ------------------------------------ |
| `:Replace`                              | (bare) open the replace prompt       |
| `:Replace buffer`                       | Replace within the current buffer    |
| `:Replace cwd [{root:DIR}]`             | Replace across the working tree …    |
| `:Replace surround {kind} {target}`     | Wrap TARGET with KIND surroundings   |

`{kind}` ∈ `quote | paren | brace`
```

**Default path: `docs/BINDINGS/Usercmds.md`** (decided — a sibling of a future
`docs/BINDINGS/Keymaps.md` if that ever exists; "Usercmds" because these are
commands, not keymaps, but they share the `BINDINGS/` directory as the general
"how do I invoke this plugin" home). Always overridable per call
(`document("path/to/file.md")`); nothing is written unless `document()` is
explicitly called — never automatic. `setup({ docs = { path = …, mode =
"replace"|"section" } })` overrides the project-wide default and whether the
writer replaces the file or updates a delimited
`<!-- lib.nvim:composer --> … <!-- /lib.nvim:composer -->` block inside a
larger doc (so hand-written prose survives regeneration).

Writing goes through [`lib.nvim.fs.write`](../../lua/lib/nvim/fs/write) +
`mkdirp`, so `docs/BINDINGS/` is created if missing.

## 8. Execution flow

On `:Verb tok1 tok2 …`:

1. registered with `nargs = "*"`, `bang`/`range` passed through, and the derived
   `complete`;
2. walk the tree with `fargs` to the **deepest matching route**; unmatched path
   → notify the error + print the verb's usage (auto-generated from the tree);
3. bind the remaining tokens to the route's `ArgSpec[]`, coercing each via its
   type; a failed/missing required arg → notify with that route's usage line and
   abort (no handler call);
4. build `ctx` and call `route.run(ctx)` inside the `usercmd.create` pcall guard
   (so a handler error surfaces as a clean notify, not a stack trace);
5. no path + no tokens → `default` handler (or usage if none).

## 9. Dogfooding: `nvim_usrcmds`

The library's own [`lib.nvim_usrcmds`](../../lua/lib/nvim_usrcmds/init.lua) is
the first natural consumer and a live example. Its independent commands can
collapse into one verb:

```lua
composer.verb("Lib", {
  routes = {
    { path = { "cwd-here" },   desc = "lcd to the current buffer's dir", run = cwd_here },
    { path = { "ps-profile" }, desc = "Open the active PowerShell profile", run = ps_profile },
    { path = { "helptags" },   desc = "Regenerate all helptags",           run = helptags },
  },
})
```

`:Lib <Tab>` then completes `cwd-here | helptags | ps-profile`. This both proves
the module and shrinks the hand-rolled `register_*` boilerplate.

> **Shipped.** [`lib.nvim_usrcmds`](../../lua/lib/nvim_usrcmds/init.lua) now
> registers the `:Lib` verb via the composer **alongside** the existing flat
> `:CwdHere` / `:PowershellProfile` (gated by a new `lib_verb` option, default
> on). The command bodies were extracted into shared local actions so both
> surfaces dispatch to identical behavior; the `ps-profile` route is included
> only when `powershell_profile` is enabled, mirroring the flat default. The
> flat commands are untouched, so no muscle-memory break.

## 10. Registration & documentation plan

Wiring the new module into the library's surfaces, per repo convention
([conventions.md](../conventions.md)):

1. **Module layout** — `lua/lib/nvim/usercmd/composer/init.lua` with an
   `@types/init.lua` (the `Route`/`ArgSpec`/`Ctx`/`ArgType` classes above),
   plus internal `completion.lua`, `parse.lua`, `docgen.lua` submodules.
2. **Aggregator** — add a key in all three strategies
   ([metatable](../../lua/lib/strategies/metatable.lua),
   [lazy](../../lua/lib/strategies/lazy.lua),
   [eager](../../lua/lib/strategies/eager.lua)):
   `composer = "lib.nvim.usercmd.composer"` — and also hang it off the existing
   `usercmd` table so both `require("lib").composer` and
   `require("lib").usercmd.composer` resolve (decided, [§11](#11-decisions)).
3. **`@types/all_functions.lua`** — add the field so `require("lib").composer`
   is fully typed.
4. **Vimdoc** — `doc/lib.nvim-usercmd-composer.txt` tagged
   `*lib.nvim-usercmd-composer*` (+ per-topic tags), and one line in the
   `doc/lib.nvim.txt` hub; per-module `README.md` next to the source.
5. **Health** — add the module to `PROBE` in
   [lib/health.lua](../../lua/lib/health.lua) so `:checkhealth lib` covers it.

## 11. Decisions

Naming and docs-path are settled; only the migration question stays open.

1. **Module name: `composer`** (settled). Rejected alternatives: `verb` (the
   module isn't itself a verb, it produces one — confusing to name the factory
   after its product), `dispatch`/`router` (accurate but generic, collides
   with the "routing" vocabulary already used for the tree-walk step
   internally), `subcommands`/`tree` (name the data model, not the module's
   job). `composer` reads as "composes routes into a verb", pairs naturally
   with `usercmd.create` (one command) sitting right beside it.
2. **Exposure: both** (settled). Registered as a top-level aggregator key
   (`require("lib").composer`) *and* reachable via
   `require("lib").usercmd.composer` — so `usercmd.create` (one command) and
   `usercmd.composer` (a verb with routes) live side by side under the same
   namespace, with a top-level shortcut for the common case.
3. **Docs default path: `docs/BINDINGS/Usercmds.md`** (settled). Always
   overridable per call or via `setup()`.
4. **`nvim_usrcmds` migration — resolved (alongside).** Shipped the `:Lib` verb
   *alongside* the existing flat `:CwdHere`/`:PowershellProfile`, gated by a
   `lib_verb` setup flag (default on); the flat commands are untouched. The old
   names are not removed — that stays a separate, future call. See §9.

## 12. Phased roadmap

> Status: **Phases 1–7 shipped.** Module lives at
> `lua/lib/nvim/usercmd/composer/` (init + argtypes + tree + parse + complete +
> docgen + registry + format + flags + kv), with `@types/`, `README.md`,
> `doc/lib.nvim-composer.txt`, a `docs/TESTS/composer_spec.lua` suite (green
> headless), aggregator keys in all three strategies, the `usercmd.composer`
> proxy, and a health PROBE entry. The `nvim_usrcmds` → `:Lib` dogfood is
> shipped ([§9](#9-dogfooding-nvim_usrcmds)), and so is the real-world
> `mdview.nvim` migration ([§13](#13-survey-of-existing-nvim-plugins)) — all 10
> of its flat `:MDViewX` commands collapsed into one `:MDView <subcommand>`
> verb, fully replacing the old names (no alongside period, by explicit
> decision for that repo). 7 of the 26 personal `.nvim` plugins are fully
> migrated as of Phase 7 (mdview.nvim, dap.nvim, cascade.nvim,
> color_my_ascii.nvim, sessions.nvim, pdfport.nvim, lib.nvim's own dogfood) —
> tracked in the nvim-config repo at `docs/ROADMAP/lib_nvim/usrcmd_composer.md`.

| Phase | Deliverable | Status |
| ----- | ----------- | ------ |
| **1** | Spec model + route walk + `usercmd.create` registration; `STRING`/`enum` args; `default` handler | ✅ shipped |
| **2** | Completion engine (subcommand + enum/BOOL slots) | ✅ shipped |
| **3** | Typed args `INT`/`FLOAT`/`BOOL`/`PATH`/`DIR`/`FILE`/`BUFFER` with coercion + path completion; custom type registration | ✅ shipped |
| **4** | Docgen (`document()` per-verb + registry-wide) + `setup()` doc defaults + section-mode writer, default path `docs/BINDINGS/Usercmds.md` | ✅ shipped |
| **5** | Fluent sugar (§5b) ✅; vimdoc/health/aggregator wiring ✅; dogfood `nvim_usrcmds` → `:Lib` ✅ (opt-in via `lib_verb`, alongside the flat commands) | ✅ shipped |
| **6** | Flag-style args (`--flag=value`/`--flag value`, repeatable, enum), modeled on `replacer.nvim`'s `BOOL_FLAGS`/`VALUE_FLAGS` tokenizer split. Strictly opt-in per route (`route.flags`) — zero behavior change for any route that doesn't declare flags. A `path = {}` root route (already legal before Phase 6) reproduces replacer.nvim's actual flat grammar `:Replace {old} {new} [scope] [--flags]` verbatim, no new route-shape concept needed. | ✅ shipped |
| **7** | Three capability gaps found while planning the remaining plugin migrations, built ahead of hitting them: (a) **buffer-local commands** — `spec.buffer = true\|bufnr` routes through `nvim_buf_create_user_command` (needed for markdown.nvim's per-buffer `:TableView`); (b) **short-flag aliases** — `FlagSpec.short` (`-r` alongside `--replace`), next-token-value only, lenient on unrecognized `-x` (needed for recommender.nvim); (c) **bare `key=value` grammar** — new `Route.kv` (`KvSpec[]`), a separate module (`kv.lua`) from `flags.lua` since the leniency stance differs (undeclared `key=value` stays positional, no error — unlike `--name`), composes freely with `flags` on the same route (needed for diff.nvim's `target=`/`view=vsplit`). All three opt-in, zero behavior change for routes that don't use them. | ✅ shipped |

## 13. Survey of existing `.nvim` plugins

Surveyed every `*.nvim` repo under `c:\repos`, all 25 named (the initial pass
missed `replacer.nvim` — it does exist, just wasn't matched by the first glob;
folded in below). Grepped each for `nvim_create_user_command`, classified the
command surface, and checked for an existing `lib.nvim` dependency.

**Headline finding: `lib.nvim.usercmd.create` is already the de-facto standard.**
Every surveyed repo except `nvim-cmdlog` already has a `require("lib...")` edge
— most via a defensive shim (`local ok, lib = pcall(require, "lib.nvim.usercmd");
has_lib = ok and lib.create ...`, else raw `nvim_create_user_command`), so it
works standalone but prefers `lib.nvim` when present. That means `composer`
isn't introducing a new dependency anywhere — it is purely additive to a
convention already adopted project-wide.

### Pattern (b) already in place — study these first

| Repo | Command(s) | What's worth stealing |
| --- | --- | --- |
| **filetree.nvim** | `:Filetree` (+`:Ft`) | **Closest existing match to `composer`'s own design.** A `TREE` table — leaf = `function(rest_args)`, interior = nested table, `[""]` key = default action for a bare prefix — is walked by *both* the dispatcher and the completion function, and a `command_paths()` walker enumerates the same tree for docs. This is proof-of-concept that the "one spec tree drives dispatch + completion + docs" idea works in production. See [`lua/filetree/commands.lua`](../../../filetree.nvim/lua/filetree/commands.lua) and [`lua/filetree/util/usercmd.lua`](../../../filetree.nvim/lua/filetree/util/usercmd.lua) (already delegates to `lib.nvim.usercmd.create`, confirming the layering in [§3](#3-where-it-lives)). |
| **debugging.nvim** | `:Debug` | `category -> { action -> fn }` table, but *lazily built* (leaf modules `require`d on first dispatch, not at setup) — worth adopting as an option (`ArgSpec`/route `run` could be a string module path, not just a function, to avoid eager `require` of every feature). Also: `parse_id` distinguishes "argument omitted" from "argument present but invalid" — exactly the distinction `composer`'s arg coercion needs for good error messages. |
| **gopath.nvim** | `:Gopath` (+8 legacy flat aliases) | 3-level dispatch with completion computed from **live cmdline token count** (which slot is the user currently typing) — same core idea as [§6](#6-the-completion-engine-the-core-value-add)'s walk-then-complete-current-slot algorithm, good second reference. Also models the **migration shape**: unified verb is canonical, old flat commands become opt-in compat aliases gated by a config flag — directly reusable for any future `nvim-containers`/`dap.nvim` migration. |
| **reposcope.nvim** | `:Reposcope` | Subcommand table carries its own `.desc` and a `print_usage()` renders `Usage: :Reposcope <sub> [args]` from it — cheap, exactly the shape `composer`'s auto-usage-on-error ([§8](#8-execution-flow) step 2) and Markdown docgen ([§7](#7-documentation-generation)) both want, from one source. |
| **fileops.nvim** | `:File` | Already the ideal single-verb case cited in [§1](#1-purpose). `SUBCMDS` list is reused for both dispatch validation and completion/usage text — same "one list, multiple readers" principle as `composer`'s spec tree, just flat instead of nested. |
| **project-insight.nvim** | `:ProjectInsight` | 12 subcommands incl. nested `cache build/info/clear` — another real 2-level tree example. |
| **language.nvim** | `:Spellcheck`, `:Translate`, `:TranslateReplace` | Token-based parsing separates control verbs from `--flag=value` pairs from positional args in one pass — `composer` doesn't currently plan `--flag=value` support ([§4](#4-the-spec-model) is positional-only); worth a Phase-3+ note if a route ever needs named flags. |
| **diff.nvim** | `:Diff` (+companions) | `key=value` grammar (`target=`, `view=vsplit`) is a different completion shape than positional args — same flag note as above. |
| **markdown.nvim** | `:Markdown` (+buffer-locals) | Registration file is pure wiring; dispatch/completion logic lives in a separate `commands` module — mirrors `composer`'s own planned `completion.lua`/`parse.lua`/`docgen.lua` split ([§10](#10-registration--documentation-plan)). |
| **emojis.nvim** | configurable single cmd | Small idiom: which arg slot is "current" derived from a trailing-space check on the cursor position — a detail `composer`'s tokenizer needs to get right too. |
| **migrate.nvim** | `:MigrateNotify` + factory-generated per-migrator commands | Dispatches on **argument shape** (empty / `%` / `cwd` / range) rather than a subcommand string — a different axis than the route tree; relevant to `composer`'s `default` handler and to `[""]`-style "no args → contextual action" leaves (filetree's `[""]` key does the same thing). |
| **buffer-ctx.nvim** | `:Insert`, `:Copy` | Good dispatch table, but command names aren't plugin-prefixed (collision risk) — a naming *anti*-pattern to avoid, reinforces `composer`'s "verb = central action, always plugin-scoped" stance ([§1](#1-purpose)). |
| **replacer.nvim** | `:Replace`/`:Replacer`, `:Surround`/`:Wrap`, `:ReplaceDebug` | **The plugin that motivated this whole concept ([§1](#1-purpose))** — worth its own paragraph, see below. |

**`replacer.nvim` in detail.** Doesn't cleanly fit pattern (a)/(b)/(c) — it's the
plugin the [§1](#1-purpose) framing was drawn from, and confirms the framing:
`:Surround`/`:Wrap` is a genuinely separate root verb (not a subcommand of
`:Replace`), exactly as the original sketch argued. What it does *not* have is
a subcommand tree at all — `:Replace {old} {new} [scope] [--flags]` is
**positional args + `--flag=value` grammar**, not `path[]` tokens. Notable,
reusable pieces:

- a quote/escape-aware shell-style tokenizer (`parse_args` in
  [`lua/replacer/command.lua`](../../../replacer.nvim/lua/replacer/command.lua)),
  handling `"quoted strings"`, `\`-escapes, and Windows path backslashes —
  more robust than naive `vim.split(args, "%s+")`;
- `BOOL_FLAGS`/`VALUE_FLAGS` as two lookup tables keyed by flag name, with a
  shared `apply_tokens()` that separates `--flag[=value]` tokens from
  positionals in one pass — this is effectively the flag-grammar `language.nvim`
  and `diff.nvim` also independently reinvented (Phase-6 candidate, see
  [Consequences](#consequences-for-the-design-above) below);
- deferred error reporting via `vim.schedule(function() notify.error(msg) end)`
  specifically so a parse error surfaces as a clean notification instead of
  Neovim's raw `E5108`-style command-error traceback — a UX detail worth
  copying into `composer`'s own arg-validation failure path ([§8](#8-execution-flow)
  step 3).
- `:ReplaceDebug` is a small flat if/elseif dispatch (`on|off|status|test|inspect|analyze <n> <pattern>`)
  — a secondary, debug-only surface; low priority to migrate.

Does **not** currently use `lib.nvim.usercmd.create` (raw `nvim_create_user_command`
throughout `command.lua`/`surround.lua`/`debug.lua`), despite already depending
on `lib.nvim` elsewhere (`lib.nvim.fs.write`, `lib.nvim.ui.kit.confirm`,
`lib.nvim.notify`) — same "adoption is wiring, not a new dependency" situation
as every other repo surveyed.

### Flat anti-pattern — future migration candidates (not in scope now)

| Repo | Flat commands | Collapses to |
| --- | --- | --- |
| **nvim-containers** | ~24 (`Container*`, `Image*`, `Wsl*`, `*Buffer` variants) | `:Container`, `:Image`, `:Wsl` — biggest win by command count |
| **github_stats.nvim** | 10, registered in *two* places (`commands.lua` **and** `bindings/usrcmds/init.lua` — likely duplicate registration, worth a separate bug-check) | `:GithubStats show\|summary\|referrers\|paths\|chart\|export\|diff\|debug\|dashboard` |
| **mdview.nvim** | 10, one file each, each already wrapped in `lib.nvim.usercmd.create` | Cheapest technical migration — registration layer is already `composer`-compatible, only the 10 files collapse into one spec |
| **dap.nvim** | 10, all zero-arg | Lowest-risk migration (no arg-shape complexity): `:Dap continue\|step-over\|step-into\|...` |
| **cascade.nvim** | 6 (`Rotate/Sort/Reverse/Strip/Indent/Dedent`) | `:Cascade rotate\|sort\|...` — but uses `range`/`bang` per-command (bang-as-direction), so `composer`'s `Ctx` **must** carry `range`/`bang`/`count`, not just parsed args (already modeled in [§4](#4-the-spec-model)'s `Ctx` — confirmed necessary, not speculative) |
| **color_my_ascii.nvim** | 7 (`ColorMyAscii*`) | `:ColorMyAscii highlight\|toggle\|stats\|inspect char\|group\|inline\|highlight` |
| **sessions.nvim** | flat (`SessionSave`, `SessionSaveTimestamp`, `SessionLoad`, …) | `:Session save [timestamp]\|load\|...`; its `lib.nvim.notify` fallback-shim pattern is worth reusing for `composer`'s own optional deps |
| **pdfport.nvim** | 6 (`PdfPort`, `PdfPortText`, `PdfPortFloat`, `PdfPortSystem`, `PdfPortTerminal`, `PdfPortHealth`) | `:PdfPort open text\|float\|system\|terminal`, `:PdfPort health` |
| **nvim-cmdlog** | 7 (`Cmdlog`, `CmdlogFull`, `CmdlogNvim`, …) | Only repo with **no** `lib.nvim` dependency at all — would need it added first; `:Cmdlog [nvim\|shell\|favorites] [full]` collapses a 2-axis flag combinatorics cleanly |

### Single command / not applicable

`recommender.nvim`, `open.nvim` — one configurable command each, no subtree
needed; nothing to migrate.

### Consequences for the design above

- **`Ctx` needs `range`/`bang`/`count` passthrough**, confirmed by real usage
  (cascade.nvim's bang-as-direction, gopath.nvim's `GopathProbe!`, fileops.nvim's
  count) — already in [§4](#4-the-spec-model)'s `Ctx`/`Route`, now validated
  rather than speculative.
- **`run` may want to accept a module path string, not just a function**
  (debugging.nvim's lazy-`require` pattern), to avoid eager-loading every
  feature module when a verb is registered at startup. Candidate addition to
  [§4](#4-the-spec-model)'s `Route.run` type for Phase 1.
- **Real dogfooding target beyond `nvim_usrcmds`**: `mdview.nvim` is the
  strongest candidate — it already registers every command through
  `lib.nvim.usercmd.create` one-by-one, so migrating it to `composer` is a
  pure win with zero new dependency risk and doubles as the first real-world
  "collapse 10 flat commands into 1 tree" validation. Recommend this as the
  Phase 5 dogfood target, ahead of or alongside `nvim_usrcmds`.
- **Flag-style args (`--flag=value`, `key=value`)** appear independently in
  **three** repos now — `language.nvim`, `diff.nvim`, and `replacer.nvim`
  (whose `BOOL_FLAGS`/`VALUE_FLAGS` split + escape-aware tokenizer is the most
  mature implementation seen) — three independent reinventions is a real
  signal, not a coincidence. Still out of scope for `composer`'s Phase 1–4
  (positional args only, per [§4](#4-the-spec-model)), but promoted from
  "possible" to a firm **Phase 6: flag-arg support**, modeled on
  `replacer.nvim`'s tokenizer/flag-table split rather than reinvented again.
