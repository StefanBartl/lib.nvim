# `lib.nvim.fs.roots`

Named root directories — `$REPOS_DIR`, `$NVIM_CONFIG_DIR`, your own — in one
place, and the four things plugins do with them: **expand**, **fold**,
**remap**, **list**.

```lua
local roots = require("lib.nvim.fs.roots")

roots.setup({
  vars = { "REPOS_DIR" },                 -- environment variables that are roots
  nvim_config = true,                     -- $NVIM_CONFIG_DIR = stdpath("config")
  extra = { NOTES = "~/notes", WORK = function() return vim.g.work_dir end },
})

roots.expand("${REPOS_DIR}/lib.nvim/x.lua")   --> "D:/repos/lib.nvim/x.lua"
roots.expand("$NVIM_CONFIG_DIR/lua")          --> "C:/Users/me/AppData/Local/nvim/lua"
roots.fold("d:\\repos\\lib.nvim\\x.lua")      --> "$REPOS_DIR/lib.nvim/x.lua"
roots.remap("E:/repos/casedesk.nvim/a.md")    --> { "D:/repos/casedesk.nvim/a.md" }
roots.names()                                 --> { "NOTES", "WORK", "REPOS_DIR", "NVIM_CONFIG_DIR" }
```

## Why a module and not `vim.fn.expand`

Measured on Neovim 0.12.2 / Windows — this is what the design follows from:

| call | `$VAR/x` | `${VAR}/x` |
| --- | --- | --- |
| `vim.fn.expand`, `vim.fs.normalize`, `glob`, `:edit` | expanded | **not** expanded |
| `filereadable`, `isdirectory`, `readfile`, `io.open`, `vim.uv.fs_*` | nothing is expanded | nothing is expanded |
| `fnamemodify(p, ":p")` | prepends the cwd (broken) | prepends the cwd (broken) |

`vim.fs.normalize` also expands `$X` in the **middle** of a path
(`C:/data/$X/y` turns to garbage). Patching Neovim globally is out of the
question, so the rule for callers is:

> **expand first, then normalize.** For a path that comes out of a buffer,
> `vim.fs.normalize(p, { expand_env = false })`.

## API

All pure functions over the configuration; the roots themselves are re-read on
every call, so a changed environment is seen. Call from the main loop (they use
`vim.fn` / `vim.env`).

### `setup(cfg?)`

| field | default | |
| --- | --- | --- |
| `enable` | `true` | `false` turns `fold` and `remap` off. `expand` keeps working: it only acts on text somebody wrote. |
| `vars` | `{ "REPOS_DIR" }` | Environment variable names that are roots. Replaces the default, never merges with it. |
| `nvim_config` | `true` | Register `NVIM_CONFIG_DIR` (= `stdpath("config")`). |
| `extra` | `{}` | `NAME = path \| fun(): path`. A path may start with `~`, `$VAR`, `${VAR}` or `%VAR%`. |
| `source` | — | **Tests.** `table` or `fun(name)` replacing `vim.env` **and** `stdpath("config")` as the origin of every value. |
| `windows` | platform | Force the Windows (`true`) / POSIX (`false`) spelling and comparison rules. |

`setup()` with no argument resets to the defaults. A root must be an
**absolute** path after expansion; a relative one is refused (it would move
with `:cd`, and a root that moves is no root). The filesystem root and a bare
drive (`C:/`) are refused too — they would fold every path.

### `roots()` → `{ { name, root }, ... }`

`root` is absolute, forward-slash, without a trailing slash. Order: `extra`
(alphabetical), `vars`, `NVIM_CONFIG_DIR`; **the first definition of a name
wins**, so an `extra` entry overrides an environment variable of the same name.
Names are case-insensitive on Windows (like the variables themselves).

`names()` is the same list, names only.

### `expand(s)`

`$NAME/rest`, `${NAME}/rest`, `%NAME%/rest` and `~/rest` → absolute path.
Works for a root without a real environment variable. Everything else comes
back **unchanged**:

- another variable, an unset or unknown name;
- a reference in the **middle** of the string (a root is an absolute path;
  substituting it mid-path can only produce garbage);
- a name followed by something that is not a separator (`$REPOS_DIRX`,
  `$REPOS_DIR.bak`, `${REPOS_DIR}x`).

On Windows the rest's backslashes become slashes; elsewhere the rest is kept
verbatim (a POSIX filename may contain a backslash).

`match(s)` returns `name, root, rest` for the same leading reference
(`nil` when there is none) — for callers that need the split.

### `fold(abs, opts?)` → `folded, name`

Absolute path → `$NAME/rest`. The **longest** root wins (a nested root beats
the one around it); on Windows the comparison ignores case (via
`vim.fn.tolower`, not `string.lower`, so a non-ASCII profile path works) and
backslashes and drive-letter case are accepted. A sibling that merely shares a
name prefix (`/repos2` vs `/repos`) is not inside. A relative path, or one
under no root, comes back unchanged with `name = nil`. With `enable = false`
always unchanged, unless `opts.force`.

`folder(opts?)` returns the same function with the roots resolved **once** —
for a recursive file list.

### `remap(abs)` → `{ candidate, ... }`

For an absolute path recorded on **another machine**: the root's own folder
name is the anchor. A root `D:/repos` is called `repos` on every machine, so
the part of `E:/repos/casedesk.nvim/x.md` after `repos` is looked up under
`D:/repos`. Only candidates that **exist** are returned, nearest anchor first,
each once. Empty when `enable = false`, the path is not absolute or nothing
matches.

### `status()`

Every configured name with what became of it: `{ name, kind, raw, root,
exists, problem }`, `problem` being `"unset"`, `"not_absolute"` or
`"missing_dir"`. `:checkhealth lib` reports it (a missing `$REPOS_DIR` is the
usual finding).

## Readable from outside Neovim

```sh
nvim --headless -c "lua require('lib.nvim.fs.roots').print_json()" -c "qa"
```

prints one JSON line (`json()` returns the same string):

```json
{"version":1,"windows":true,
 "roots":[{"name":"REPOS_DIR","root":"D:/repos","exists":true},
          {"name":"NVIM_CONFIG_DIR","root":"C:/Users/me/AppData/Local/nvim","exists":true}],
 "unresolved":[]}
```

`unresolved` lists configured names without a usable value
(`{ "name": "...", "problem": "unset" | "not_absolute" }`). Run it with the
user's own config — not `-u NONE` — so `setup()` and its `extra` roots have
run. The desktop hub queries it this way.

## `NVIM_CONFIG_DIR` as an environment variable

`stdpath("config")` is the source of the `NVIM_CONFIG_DIR` root — **not** the
environment variable, which can be stale (inherited from a parent Neovim with a
different `NVIM_APPNAME`). On startup (`plugin/lib_roots.lua`, and when the
module is first required) the variable is also **exported** — only if it is not
set, never overwritten — so child processes and `vim.fn.expand("$NVIM_CONFIG_DIR")`
understand it. Opt out with `vim.g.lib_nvim_roots_no_export = true`.

## Tests

`setup({ source = {...} })` makes a spec independent of the machine:

```lua
roots.setup({
  source = { REPOS_DIR = "/work/repos", NVIM_CONFIG_DIR = "/work/nvim" },
  windows = false,
})
```

With a `source` **every** value comes from it — including `NVIM_CONFIG_DIR`,
which is simply absent when the table has no entry for it. There is deliberately
no fallback to the `stdpath("config")` of whatever sandbox the test happens to
run in, and nothing is exported. Set `windows` explicitly whenever a case
depends on the spelling: the CI matrix includes Windows.

### In `testing.nvim` children

A child Neovim inherits a **filtered** environment: variables starting with
`NVIM` are never passed through, and `REPOS_DIR` is only passed when it is
listed in the child's `env_allow`. So inside a child:

- `$NVIM_CONFIG_DIR` is still right — it comes from the child's own
  `stdpath("config")`, not from the environment;
- `$REPOS_DIR` is **missing** unless you add it to `env_allow` (the
  `:checkhealth lib` finding "`$REPOS_DIR` is not set" is how this shows up).

## Relation to other modules

- [`cross.fs.expand_path`](../../cross/fs/expand_path/README.md) resolves a
  leading root reference through this registry; the composer argument types
  `PATH` / `DIR` / `FILE` go through it, and complete `$NAME/...` leads in the
  spelling the user typed.
- Not a normalizer: `normkey` / `to_absolute` / `vim.fs.normalize` still do
  that, *after* `expand`.
