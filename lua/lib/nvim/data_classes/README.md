# `lib.nvim.data_classes`

The data classes of the areas on this device: the `areas.json` of the desktop apps (tasks-desktop), read
**fail-closed**. A plugin asks it before anything leaves the machine (an export, a report, a prompt to a runner
elsewhere): only `public` and `internal` may go; `private` and `unclassified` never.

The file is the hub's, and this reader follows it: the same path, the same two schemas, the same refusals as
`tasks-desktop/crates/tasks-hub/src/classes.rs` (see `docs/SECURITY.md` there, "Data classes").

```lua
local data_classes = require("lib.nvim.data_classes")

-- the class of a repository, by its folder or its name
local class, problem = data_classes.class_of_repo("E:/repos/lib.nvim")
if class ~= "public" and class ~= "internal" then
  -- leave it out (and, when `problem` is set, tell the person why nothing is released)
end

-- or the whole file
local classes = data_classes.load()
classes:shown("lib.nvim")             --> "public" | "internal" | "private" | "unclassified"
classes:for_vault("work"):allows("x") --> true only for public and internal
```

## Where the file is

`<config>/areas.json`, per device, never in a vault (a vault is synced and changed by pull requests, so a release
written there could be set by a third party). `<config>` is found the way `appkit_hub::config::config_dir` finds it:

| | |
|---|---|
| `TASKS_DESKTOP_CONFIG_DIR` set (not empty) | that folder |
| Windows | `%APPDATA%/tasks-desktop` |
| macOS | `~/Library/Application Support/tasks-desktop` |
| elsewhere (WSL too) | `$XDG_CONFIG_HOME/tasks-desktop`, else `~/.config/tasks-desktop` |

Every function that reads takes `opts` to point elsewhere: `path` (the file), `dir` (a config folder), `app` and
`env_var` (another app of the family), `env` and `os` (an environment table and a system to resolve for, for specs).

## The file

```json
{ "schema": 1,
  "default": "internal",
  "areas": { "lib.nvim": { "class": "internal", "repo": "lib.nvim" },
             "secret-area": { "class": "private" } } }
```

Schema 1 is the classes of the vault `main`. Schema 2 keys an entry by `<vault>:<area>` and gives a vault its own
default; a vault the file does not name has every area unclassified (it never takes over `main`):

```json
{ "schema": 2,
  "vaults": { "work": { "default": "internal" } },
  "areas": { "main:lib.nvim": { "class": "internal" },
             "work:lib.nvim": { "class": "private" } } }
```

`default` is the owner's explicit choice for the areas the file does not name; an entry always wins over it.

## Fail-closed

- No file: nothing is classified (`missing = true`, no problem).
- A file that exists and cannot be used classifies nothing, and `problem` says why (`kind`: `unreadable`,
  `invalid`, `no_config_dir`). The hub refuses to start with such a file; a library reader does not stop its caller,
  so the caller gets the reason to show instead.
- Refused, as `classes.rs` refuses them: a schema other than `1` or `2` (or written `1.0`, `1e0`, `"1"`, `-0`, `01`),
  a field the struct does not have (`deny_unknown_fields`: `"clas"`, a top-level `"more"`, `vaults` in schema 1, a
  `default` at the top of schema 2, a field of a vault rule that is not `default`), a field written twice in one
  object, a class that is not `public`/`internal`/`private` (case counts), an area or a repo that is not one plain
  folder name (1 to 128 characters, no `/\,:*?"<>|`, no control character, not starting with a dot or ending with a
  dot or a space), a schema 2 key that is not `<vault>:<area>` or names a vault that is not `main` or 1 to 40 ASCII
  letters, digits, `.`, `-`, `_` (not starting with a dot), more than 1000 areas, a file over 256 KiB, text that is
  not UTF-8, and anything that is not strict JSON (a byte order mark, a comment, a trailing comma, a lone surrogate,
  white space other than space, tab, CR, LF, nesting 128 deep).
- What serde_json accepts is accepted too: an entry or a rule written as a list of its fields (`["private"]`,
  `["public", "repo-b"]`), `null` for an optional field, a class written as a map of its name to `null`
  (`{"public":null}`, serde's form of a unit variant; anything else in that map is refused), an area named twice (the
  last entry wins, but the first is checked as well).
- An area that is not a text (`nil`, a number: a caller that could not work out the area) is `unclassified` in every
  vault, also one with a `default`: the default covers areas the file does not name, not a failed lookup.

The text is parsed by hand, not with `vim.json.decode`: that parser keeps the last of a field written twice
(`{"class":"private","class":"public"}` would release an area the hub keeps closed), reads `1.0` as `1` and takes a
byte order mark.

## A repository

`class_of_repo(repo)` takes the folder of a repository (or its name) and compares its last part with the `repo` field
of every entry. An entry without a `repo` field whose area name is the repository's name (the hub's `areas propose`
writes `repo` as exactly that name, a hand-written file often leaves it out) can only make the class stricter: it
never releases a repository, so with no `repo` match the repository stays `unclassified`. An entry whose
`repo` names another repository does not name this one, whatever its area is called. Of the areas that name it, the
strictest class wins (`private` over `internal` over `public`), in every
vault of the file unless `opts.vault` names one. A repository no entry names is `unclassified`: the `default` of a vault
is a choice for its areas, and which area a repository belongs to only an entry says. Names are compared exactly
(`Lib.nvim` is not `lib.nvim`).

## API

| Function | Returns |
|---|---|
| `load(opts?)` | `classes, problem` — always a `classes`; `problem` is `classes.problem` |
| `parse(text)` | `classes` of a text (no file) |
| `class_of_repo(repo, opts?)` | `class, problem, matches` — `load(opts)` then `classes:class_of_repo(repo, opts.vault)`; `matches` lists `{ vault, area, class, by }` (`by`: `"repo"` or `"name"`) |
| `config_dir(opts?)` / `path(opts?)` | `string\|nil, err` — the config folder / the file `load` reads |
| `valid_area_name(name)` / `valid_vault_name(name)` | `ok, why` — the name checks of tasks-hub (a name that is not UTF-8 is refused: a Rust `&str` cannot hold it) |
| `classes:for_vault(vault?)` | the policy of a vault (default `"main"`; one the file does not name classifies nothing) |
| `classes:shown(area, vault?)` / `classes:allows(area, vault?)` | the class / whether it may leave the machine |
| `classes:class_of_repo(repo, vault?)` | `class, matches` |
| `classes:vaults()` | the vaults the file names |
| fields | `problem`, `kind`, `missing`, `path`, `schema` |
| `policy:shown(area)` / `:allows(area)` / `:entry(area)` / `:repo_of(area)` / `:default()` | as `AreaPolicy` of classes.rs |
| `policy:areas()` / `:unclassified(all)` / `:private_areas(all)` / `:len()` / `:is_empty()` | |

`problem` never holds the path of the file (it is `classes.path`), so it can be shown or logged as it is; the name of
an area in it is clipped and escaped (`lib.nvim.contract.echo`).

Constants: `SCHEMA` (1), `SCHEMA_VAULTS` (2), `MAX_AREAS` (1000), `MAX_FILE_BYTES` (256 KiB), `MAIN_VAULT`, `APP`,
`ENV_VAR`, `FILE`.

## Not here

Writing the file (`tasks-hub areas propose` writes a proposal for a person to read; nothing here writes `areas.json`),
and the uses (the hub's `Use` enum): today every use has the same rule, `allows`.

## Tests

`TESTS/data_classes_spec.lua` ports the reading tests of `classes.rs` and adds the path, the repository lookup and the
parser edges. `TESTS/data_classes_cases_spec.lua` runs the case list tasks-desktop holds its hub and its web reader to
(`ui/web/classes-cases-dump.mjs`) against this reader; it needs a tasks-desktop checkout (`TASKS_DESKTOP_DIR` or a
sibling folder) and `node`, and says `[SKIPPED]` without them.
