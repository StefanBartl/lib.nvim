# `lib.nvim.cross.fs.expand_path`

Expands `~`, `$VAR`/`${VAR}` (POSIX-style) and `%VAR%` (Windows-style)
references in a raw path string. Pure string expansion — it does **not**
normalize separators or resolve `.`/`..` (see `lib.nvim.cross.fs.separators`
for that). The one exception is a **leading named root** (below): that part
comes back in the registry's canonical spelling.

Behavior:

- `path` that is not a non-empty string is returned unchanged.
- A leading `~` is replaced with `vim.uv.os_homedir()` (falling back to
  `vim.loop.os_homedir()`); if the home directory can't be determined, the
  `~` is left as-is.
- `%VAR%` references are substituted from `vim.env`; an unset variable is
  left untouched (`%VAR%` stays literal).
- `$VAR` and `${VAR}` references are substituted from `vim.env`; an unset
  variable is likewise left untouched.
- A **leading** `$NAME` / `${NAME}` / `%NAME%` that names a root of
  [`lib.nvim.fs.roots`](../../../fs/roots/README.md) is resolved by the registry
  first. That is what makes `$NVIM_CONFIG_DIR` (which is `stdpath("config")`,
  not necessarily an environment variable) and user-defined `extra` roots work
  here, and what lets a test inject its own values. The root comes back in the
  registry's spelling — absolute, forward slashes, no trailing slash (the
  rest keeps its own separators: on Windows `$REPOS_DIR\proj\x` becomes
  `D:/repos\proj\x`, while `roots.expand` would unify them) — and
  the rest of the string goes through the expansions below. Names the
  registry does not know behave exactly as before.
- All three expansions run unconditionally and in that order (`~`, then
  `%VAR%`, then `$VAR`/`${VAR}`) — a path can mix styles, e.g. `~/foo/$HOME`.

## Usage

```lua
local expand_path = require("lib.nvim.cross.fs.expand_path")

expand_path("~/projects")        --> "/home/me/projects"
expand_path("$HOME/projects")    --> "/home/me/projects"
expand_path("${HOME}/projects")  --> "/home/me/projects"
expand_path("%USERPROFILE%\\x")  --> "C:\\Users\\me\\x"
expand_path("$UNSET_VAR/x")      --> "$UNSET_VAR/x"  -- left untouched
```
