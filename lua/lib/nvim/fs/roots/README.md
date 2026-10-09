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

## Who calls what

- **`setup`** belongs to the **user's config** — one place, once. It
  *replaces* the configuration, so a plugin that calls it erases the user's
  roots (and another plugin's).
- **`register`** is for **plugins**: it adds a root without touching what the
  user configured, and survives a later `setup`.
- **Per-call options** (`names`, `vars`, `extra`, `nvim_config`, and `force`
  for the callers that fold or remap) tune a single `roots` / `fold` /
  `folder` / `root_of` / `remap` call — for a plugin that has its own options
  for "which env vars count as roots here" and "which roots do I bring": they
  stay the plugin's, nobody else sees them, and the user's `setup` is not
  touched.

## API

All pure functions over the configuration; the roots themselves are re-read on
every call, so a changed environment is seen. Environment variables are read
through libuv, so `expand`, `match`, `fold`, `relative` and `roots` also work in
a fast event (a `vim.uv` callback), including the case folding of a non-ASCII
Windows path. `export_env` does not (it sets a variable through Vimscript) and
does nothing there.

### `setup(cfg?)`

| field | default | |
| --- | --- | --- |
| `enable` | `true` | `false` turns `fold` and `remap` off. `expand` keeps working: it only acts on text somebody wrote. |
| `vars` | `{ "REPOS_DIR" }` | Environment variable names that are roots. Replaces the default, never merges with it. |
| `nvim_config` | `true` | Register `NVIM_CONFIG_DIR` (= `stdpath("config")`). |
| `extra` | `{}` | `NAME = path \| fun(): path`. A path may start with `~`, `$VAR`, `${VAR}` or `%VAR%` — `$VAR` first as a known root (so `NOTES = "$REPOS_DIR/notes"` works however `REPOS_DIR` is defined), else from the environment. |
| `source` | — | **Tests.** `table` or `fun(name)` replacing `vim.env` **and** `stdpath("config")` as the origin of every value. |
| `windows` | platform | Force the Windows (`true`) / POSIX (`false`) spelling and comparison rules. |

`setup()` with no argument resets to the defaults. A value of the wrong type
(`vars = "REPOS_DIR"`) or a key that does not exist (`extras = {}`) **raises**
and leaves the previous configuration in place — silently using the defaults
would hide the typo. `vars` and `extra` are copied, so changing the table
afterwards has no effect; `source` is kept as given.

A root must be an **absolute** path after expansion; a relative one is refused
(it would move with `:cd`, and a root that moves is no root). The filesystem
root and a bare drive (`C:/`) are refused too — they would fold every path.
`.` and `..` in a root value are resolved (`/a/b/../c` is `/a/c`); `..` cannot
climb above the root of the drive, the filesystem or a UNC share.

`enabled()` returns the user's `enable` — whether actions should write the
env-var form of a path at all. A plugin that has its own switch for that checks
its own and passes `force = true` to `fold` / `remap` when it is on.

### `register(name, value)` → `unregister`

Add a root from a plugin. `value` is a path (may start with `~` / `$VAR`) or a
function returning one. A registered root survives `setup()`; on a name the
user also defined in `extra`, **the user wins** (and a user function that
returns nothing falls through to the registered one). Registering a name again
replaces the earlier one — on Windows also one spelled in another case
(`Notes` / `NOTES`). The returned function removes *this* registration again
(by identity, not by value: two plugins registering the same path do not remove
each other's root) — it does nothing once a newer one replaced it. `unregister(name)`
removes whatever is registered under the name and returns whether there was
something.

### `roots(opts?)` → `{ { name, root }, ... }`

`root` is absolute, forward-slash, without a trailing slash, with an
**uppercase drive letter** (`d:\repos` comes back as `D:/repos`). Order: `extra`
(alphabetical), `opts.extra`, registered (alphabetical), `vars` (or `opts.vars`),
`opts.names`, `NVIM_CONFIG_DIR`; **the first usable definition of a name
wins**, so an `extra` entry overrides an environment variable of the same
name — while an `extra` function that returns nothing falls through to it.
Names are case-insensitive on Windows (like the variables themselves).

`opts` (an unknown key, or a value of the wrong type, raises — naming the
function you called):

| | |
| --- | --- |
| `names` | `string[]` — environment variable names that are roots **for this call**, after `vars`. |
| `vars` | `string[]` — environment variable names that are roots for this call **instead of** `setup`'s `vars` (a plugin option that replaces the default list, as `setup`'s `vars` does). |
| `extra` | `table<string, path \| fun()>` — roots this call brings along (the plugin's own config). The user's `extra` wins on a name; they win over registered roots and `vars`. |
| `nvim_config` | `boolean` — overrides `setup`'s `nvim_config` for this call. |

The roots of the user and of other plugins stay visible to such a call (that is
the point of one registry): a path under `$NOTES` of another plugin folds to
`$NOTES/…` if that root is the deepest match.

A name must be letters, digits and underscores and not start with a digit
(`MY-ROOT`, `a.b`, `1ST` are refused, reported as `invalid_name`): `fold`
writes `$NAME/…`, and a name `expand` cannot read back would make a path that
can be written but never resolved.

A root function may itself ask the registry (`expand("$REPOS_DIR/notes")`). A
definition counts as busy while it runs, so asking about **itself** (or around
a cycle) finds nothing instead of recursing.

`names()` is the same list, names only.

### `expand(s)`

`$NAME/rest`, `${NAME}/rest`, `%NAME%/rest` and `~/rest` → absolute path.
Works for a root without a real environment variable. Everything else comes
back **unchanged**:

- another variable, an unset or unknown name;
- a reference in the **middle** of the string (a root is an absolute path;
  substituting it mid-path can only produce garbage);
- a name followed by something that is not a separator (`$REPOS_DIR` + `X`,
  `$REPOS_DIR.bak`, `${REPOS_DIR}x`).

A backslash separates only where it is one: on Windows `$REPOS_DIR\x` is a
reference and the rest's backslashes become slashes; elsewhere it is a file
called `$REPOS_DIR\x`, and only `/` ends the name (`~` likewise). The home
directory is normalized (`HOME=/home/u/` does not give `/home/u//x`).

`match(s)` returns `name, root, rest` for a leading `$NAME` / `${NAME}` /
`%NAME%` reference (`nil` when there is none, and for `~`, which is no root) —
for callers that need the split. It resolves
only the name it is asked about (no other `extra` function runs), so it is
cheap to call for every `$VAR` a string contains.

`relative(p, name)` is the part of the absolute path `p` below the root
`name` (`""` for the root itself, `"/rest"` below it, a trailing separator
kept), ignoring separator, drive-letter case and — on Windows — case.
`nil` when `p` is not under that root. It puts a path that came back from the
filesystem (a completion candidate) into the spelling the user typed.

### `fold(abs, opts?)` → `folded, name`

Absolute path → `$NAME/rest`. The **deepest** root wins (a nested root beats
the one around it). On Windows the comparison ignores case (via
`vim.fn.tolower`, not `string.lower`, so a non-ASCII profile path works) and
backslashes and drive-letter case are accepted; it compares segment by
segment, because the lowercase of a letter can have another byte length
(`İ` is 2 bytes, `i` 1). A sibling that merely shares a name prefix
(`/repos2` vs `/repos`) is not inside. A relative path, or one under no root,
comes back unchanged with `name = nil`. With `enable = false` always
unchanged, unless `opts.force`. Two names for the same directory: the one
earlier in `roots()` order wins.

The comparison is **lexical**: `.` and `..` are resolved first, so
`/repos/../etc/passwd` is *not* inside `/repos`; symlinks are not resolved —
except for a root that is itself a symlink. A buffer name is canonical on Unix
(`~/.config/nvim` → `~/dotfiles/nvim` opens as the latter), so on Unix a path is
compared with each root as configured first, and only when none matches with
the roots' `uv.fs_realpath` (cached for a few seconds, so a `fold` on a path
under no root does not stat on every call; a link to a drive or the filesystem
root is ignored — it would fold every path). Windows does not canonicalise
buffer names, so it never looks.

On Windows, the verbatim and device prefixes (`\\?\C:\x`, `\\.\C:\x`,
`\\?\UNC\srv\share\x`) are read as `C:/x` and `//srv/share/x`. On POSIX a path
with a **backslash below the root** (a valid file name such as `a\..\..\x`) is
*not* folded: `$NAME/a\..\..\x` would climb out of the root on a Windows machine
that reads the text.

`opts` — those of `roots` plus `force` (fold even when `enable` is false, for
an action the user asked for by name — or a plugin whose own switch is on). An
unknown key raises.

`folder(opts?)` returns the same function with the roots resolved **once** —
for a recursive file list. `root_of(abs, opts?)` returns just the name.

### `remap(abs, opts?)` → `{ candidate, ... }`

`opts` are those of `fold` (which roots; `force` maps although `enable` is
false).


For an absolute path recorded on **another machine**: the root's own folder
name is the anchor. A root `D:/repos` is called `repos` on every machine, so
the part of `E:/repos/casedesk.nvim/x.md` after `repos` is looked up under
`D:/repos`. The anchor can also be the last segment (the recorded root itself).
Only candidates that **exist** are returned, the **outermost** anchor first
(the longest rest; for equal anchors the earlier root — across all roots), each
once. The anchor word compares case-insensitively when
this machine is Windows *or the recorded path is a Windows path* (a drive
letter or UNC). Empty when `enable = false`, the path is not absolute or
nothing matches.

The recorded path is someone else's data: `.` and `..` are resolved first, so
`E:/repos/../../etc/x` cannot climb out of the root it is re-anchored under.
A path with a NUL byte maps to nothing. The work is bounded because the path is
somebody else's data: one longer than 4096 bytes maps to nothing, and at most 64
candidates are looked up per call.

### `status()`

Every configured name with what became of it: `{ name, kind, raw, root,
exists, problem, detail }`. `kind` is `"extra"`, `"registered"`, `"var"` or
`"nvim_config"`. `problem`:

| | |
| --- | --- |
| `unset` | no value (variable not set or empty, function returned nothing) |
| `unresolved_var` | the value starts with `$VAR` / `~` that has no value — `detail` names it |
| `error` | the function raised — `detail` is the message |
| `bad_type` | neither a string nor a function — `detail` is its type |
| `not_absolute` | relative after expansion |
| `too_broad` | the filesystem root or a whole drive |
| `invalid_path` | contains a NUL byte |
| `invalid_name` | not letters, digits and underscores |
| `missing_dir` | `root` is not an existing directory |

For `NVIM_CONFIG_DIR`, `env` holds the root the environment variable of that
name would give, when it differs from `stdpath("config")`. `:checkhealth lib`
reports all of it (a missing `$REPOS_DIR` is the usual finding).

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
(`{ "name": "...", "problem": "<see status>", "detail": "..." }`, `detail`
only when there is one) — plus `"invalid_encoding"` for a root that is not
valid UTF-8, which a strict JSON reader would refuse as a whole. The key order
within an object is not part of the contract.

Run it with the user's own config — not `-u NONE` — so `setup()` and its
`extra` roots have run. A `-c` command runs **before** `VimEnter`, so a root a
plugin registers from a `VimEnter` handler (a lazy-loading manager) is missing
from that output. To see those too, print from `VimEnter` itself, after the
handlers of the config:

```sh
nvim --headless "+autocmd VimEnter * ++once lua require('lib.nvim.fs.roots').print_json()" \
                "+autocmd VimEnter * ++once qa"
```

The desktop hub is the intended reader (it asks through `nvim --headless`).

## `NVIM_CONFIG_DIR` as an environment variable

`stdpath("config")` is the source of the `NVIM_CONFIG_DIR` root — **not** the
environment variable, which can be stale (inherited from a parent Neovim with a
different `NVIM_APPNAME`). On startup (`plugin/lib_roots.lua`, and when the
module is first required) the variable is also **exported**, so child
processes and `vim.fn.expand("$NVIM_CONFIG_DIR")` understand it:

- not set → set to `stdpath("config")`;
- set by the user → **never overwritten** (the registry still uses
  `stdpath("config")`; `:checkhealth lib` warns when the two disagree);
- exported by lib.nvim in a parent Neovim (recognised by the marker variable
  `LIB_NVIM_ROOTS_EXPORTED` holding the same value) → refreshed to *this*
  instance's `stdpath("config")`.

Opt out with `vim.g.lib_nvim_roots_no_export = true` (or `1`) before it runs.

## Known limits

- Case folding on Windows is `vim.fn.tolower`, not NTFS's own table: `i` / `İ`
  and `ß` / `ẞ` are different directories on NTFS but compare equal here. Only
  the filesystem can tell; these cases are far outside real profile paths.
- Under `windows = false` a drive-letter path counts as absolute: the flag runs
  the other platform's rules on one machine, so it does not judge the host.
  Likewise `/repos` under a forced `windows = true` on a POSIX host. On a real
  Windows host it is refused as a root (`not_absolute`): it means "on the
  current drive" and moves with `:cd`.
- `expand` leaves `..` in the rest alone (`$R/../x` → `C:/repos/../x`): expand
  first, then normalize.
- `NVIM_CONFIG_DIR` listed in `vars` / `opts.names` is ignored while
  `nvim_config` is on (the root is `stdpath("config")`); with `nvim_config =
  false` the variable is used.

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
run in, and nothing is exported. (`~` still reads the real home directory.)
Set `windows` explicitly whenever a case depends on the spelling: the CI matrix
includes Windows. Roots a plugin `register`ed survive `setup()` — unregister
them in the test.

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
  `PATH` / `DIR` / `FILE` go through it, and complete `$NAME/...` leads: the
  root reference keeps the spelling the user typed (`${NAME}` or `$NAME`), the
  rest comes back the way the filesystem names it with `.` / `..` resolved (so
  `$NAME/./al` completes to `$NAME/alpha/`, and a step out of the root with
  `$NAME/..` is not completed).
- Not a normalizer: `normkey` / `to_absolute` / `vim.fs.normalize` still do
  that, *after* `expand`.
