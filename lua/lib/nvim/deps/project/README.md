# `lib.nvim.deps.project`

The **project view** of what is missing: not "this buffer needs a parser"
(that is [`treesitter.parser_policy`](../../treesitter/parser_policy/README.md),
per filetype, at the moment it is needed) but "this root holds files of kinds
X, Y and Z, and for them the parsers A, B and the tools C, D are not here".

It is one scan plus one mapping plus one report:

```
files under root ──count──> "*.rs": 340, "Makefile": 1, …            (scan, cached per root)
"*.rs" ──vim.filetype.match──> rust ──get_lang──> rust ──status──> "available"   (parsers)
rust ──caller's table──> { rust-analyzer (Mason), cargo (bin) } ──detect──> missing (tools)
```

Requiring the module registers nothing and touches nothing. **Nothing here
installs silently** — see [Installing](#installing).

## Using it

```vim
:Lib deps project            " scan the current directory, show what is missing
:Lib deps project refresh    " walk again instead of using the cached scan
:Lib deps project install    " scan, then ask ONCE and install what the report lists
```

In the report popup `I` is the same as `install`.

```lua
local project = require("lib.nvim.deps.project")

-- 1. Say which tools a filetype wants (once, from the plugin that knows).
project.register_tools("lsp.nvim", {
  lua  = { { mason = "lua-language-server" }, { mason = "stylua" } },
  rust = { { mason = "rust-analyzer" } },
  markdown = {
    { bin = "pandoc", why = "Export to docx/pdf", pkg = { winget = "JohnMacFarlane.Pandoc", brew = "pandoc" } },
  },
})

-- 2. Scan (async, cached), build the report, show or install.
project.scan(vim.fn.getcwd(), nil, function(scan)
  local report = project.report(scan)
  print(table.concat(project.lines(report), "\n"))
end)

-- 3. Optional: notify when a root has something missing. Off by default.
project.setup({ auto = true })
```

## The tools table

What a filetype *wants* is the caller's knowledge — `lib.nvim` cannot guess
that Lua wants stylua. It is a table `{ [filetype] = entry[] }` handed over
with `register_tools(owner, table_or_function)` or per call as
`report(scan, { tools = … })`. An entry is either

| Entry | Meaning | Installed through |
|---|---|---|
| `{ bin = "pandoc", why = "…", pkg = { brew = "pandoc" } }` | a `Lib.Deps.Tool`, exactly what a plugin's `docs/install.json` already says (`bin_alternatives`, `paths` work too) | `deps.install` — a terminal with the command typed, not submitted |
| `{ mason = "stylua", why? }` | a Mason package | the Mason registry API, headless |

A plugin that ships `docs/install.json` registers its tools keyed by the
filetypes that need them; lsp.nvim registers the Mason packages of its
`ensure_install` lists. A table may be a function (called at report time), for
lists only known after the owner's own `setup()`. Unusable entries are named in
`report.problems`, not dropped silently.

## Scanning

`scan(root, opts, on_done)` walks `root` asynchronously
(`lib.nvim.fs.collect_recursive`, one directory at a time, the main loop is
never blocked) and keeps **only counts**: files per extension (`*.rs`) or per
bare file name (`Makefile`, `.gitignore`), plus one sample path of each kind.
The path list is thrown away.

- Pruned by default: the basenames of `lib.nvim.fs.ignore.list`
  (`.git`, `node_modules`, `target`, caches, …); `opts.ignore` replaces that.
- **Cached per root** (`ttl_seconds`, default 600): a `:cd` back to a known root
  costs nothing; `refresh = true` walks again. Two callers asking for one root
  while a walk runs share it.
- A walk that could not read a directory is delivered (`scan.errors`) but not
  cached — a momentarily unreadable root would otherwise answer "nothing here"
  for the whole TTL.
- `on_done` always runs on the main loop, also for a cache hit; the returned
  function cancels the wait.

## The mapping

1. **kind → filetype**: `vim.filetype.match({ filename = sample })` on one real
   path of that kind. Two files of one extension can in principle resolve
   differently (a pattern keyed on a directory); the sample decides. Files
   with no filetype are counted as `unmapped`.
2. **filetype → language**: `vim.treesitter.language.get_lang`.
3. **language → parser state**: `parser_policy.status(lang)` — `installed`
   (a `parser/<lang>.*` library is on `runtimepath`, which covers the bundled
   parsers and everything nvim-treesitter installed, or nvim-treesitter lists
   it), `available` (installable), `unavailable`, `unknown`. A language the user
   answered "Never" to is reported as `declined`.

Only `available` and `declined` count as **missing parsers**. `unavailable`
(no parser exists) and `unknown` (nvim-treesitter is not loadable) are not
"missing" — nothing could be installed. `treesitter.guard` (which filetypes may
*activate* treesitter) is deliberately not consulted: this answers "is the
parser there", not "will it be switched on".

## Installing

`install(report, opts)` asks **one** question that lists everything it is about
to do, and only then starts it:

| What | How | Note |
|---|---|---|
| parsers | `parser_policy.install(lang)` (nvim-treesitter, background) | "Never" languages are left out and named; the policy mode is irrelevant here, the question *is* the confirmation |
| `bin` tools | `deps.install.run(plan, { confirm = false })` | a terminal with the command **typed, not submitted** — a `sudo` prompt is answered by you |
| Mason packages | the registry API (below) | headless, results arrive as notifications |

`opts.confirm = false` skips the question (callers that asked in their own UI,
tests); the terminal command is still only typed. `install_plan(report)` returns
the same plan and question text without doing anything.

## `setup({ auto = true })` — the optional trigger

Off by default (`setup()` without `auto` does nothing). With `auto = true` the
current directory is scanned now and on every `DirChanged`; one
`lib.nvim.notify` line per root says what is missing, and again only when
*what is missing* changes. It never installs. `reset_announced()` forgets the
announcements; `setup({})` turns the trigger off.

## Feasibility: driving Mason from Lua without UI (answered)

The open question from the idea note was whether Mason installs can be driven
from Lua without disturbing the UI. **Yes**, checked against the mason.nvim
source (the checkout in use, `2a6940a`, 2026-06-11):

- `require("mason-registry")` is the API the `:Mason` window itself sits on.
  `get_package(name)` returns a `Package`; `pkg:is_installed()` and
  `pkg:is_installing()` are plain reads.
- `pkg:install(opts, callback)` queues the job on Mason's own installer (a
  coroutine runner behind a shared semaphore, so Mason decides how many run at
  once) and returns an `InstallHandle`. It opens no window and steals no focus;
  the result is `callback(success, error)`. The handle carries `stdout`/`stderr`
  events if a caller ever wants progress.
- Two traps, both handled in `deps.project.mason`: `get_package` **raises** for
  a name the registry does not know *and for every name while the registry has
  never been fetched* (a fresh machine) — so it is always `pcall`ed and
  `registry.refresh(cb)` runs once before the first install; and `install`
  **asserts** the package is not already installing, so that is checked first.
- Mason is a soft dependency: without it every Mason entry reports `unknown`
  (not `missing`) and is never offered.

Whether a modern installer of our own should replace Mason is not part of this.

## API

| Function | Meaning |
|---|---|
| `scan(root, opts?, on_done)` | async, cached per root; returns a cancel function |
| `forget(root?)` | drop the cached scan of a root (or all) |
| `count(root, paths, errors?)` / `key_of(path)` | the pure counting `scan` is built on |
| `register_tools(owner, table_or_fn)` / `registered()` | the caller's filetype → tools table; returns an unregister function |
| `report(scan, opts?)` | languages, missing parsers, tools, missing tools, unmapped, problems |
| `lines(report, opts?)` / `summary(report)` | the report as text / one notification line (nil when nothing is missing) |
| `install_plan(report, opts?)` / `install(report, opts?)` | the plan and its question / ask once, then start |
| `run(root?, action?, opts?)` | what `:Lib deps project [refresh\|install]` calls |
| `setup(opts?)` / `reset_announced()` | the optional `DirChanged` trigger |

Types: `Lib.Deps.Project*` in [`@types/init.lua`](@types/init.lua).
