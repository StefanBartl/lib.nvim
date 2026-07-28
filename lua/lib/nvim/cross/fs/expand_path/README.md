# `lib.nvim.cross.fs.expand_path`

Expands `~`, `$VAR`/`${VAR}` (POSIX-style) and `%VAR%` (Windows-style)
references in a raw path string. Pure string expansion — it does **not**
normalize separators or resolve `.`/`..` (see `lib.nvim.cross.fs.separators`
for that).

Behavior:

- `path` that is not a non-empty string is returned unchanged.
- A leading `~` is replaced with `vim.uv.os_homedir()` (falling back to
  `vim.loop.os_homedir()`); if the home directory can't be determined, the
  `~` is left as-is.
- `%VAR%` references are substituted from `vim.env`; an unset variable is
  left untouched (`%VAR%` stays literal).
- `$VAR` and `${VAR}` references are substituted from `vim.env`; an unset
  variable is likewise left untouched.
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
