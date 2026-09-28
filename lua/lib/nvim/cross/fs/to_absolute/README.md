# `lib.nvim.cross.fs.to_absolute`

Resolves any path spec — relative, `~`/env-prefixed, mixed-separator, or
made up of nothing but separator characters — to its absolute,
trailing-separator-free, forward-slash form. The one `cross.fs` helper that
actually touches the filesystem/cwd (via `vim.fn.fnamemodify(path, ":p")`);
the others (`expand_path`, `separators.*`) are pure string transforms.

The separator-only case is the one this exists to get right:
`separators.collapse_dots` runs on the input *before* `fnamemodify`, not
just on its output. A path made up entirely of separators (`"//"`,
`"\\\\"`, `"\\/\\"`, any length or mix) collapses there to a single POSIX
`"/"`, which `fnamemodify` then resolves to the current drive's root on
Windows and to the real filesystem root on POSIX — both correctly. Skipping
that pre-pass and handing such a path to `fnamemodify` as-is does not: a
naive trailing-separator strip collapses it to `""`, which resolves to the
cwd instead of the root, and on POSIX a literal `\` is just an ordinary
filename character, so an un-collapsed backslash-heavy input resolves
relative to the cwd rather than to anything the caller meant.

## Usage

```lua
local to_absolute = require("lib.nvim.cross.fs.to_absolute")

to_absolute("~/repos/x")     --> "/home/me/repos/x"
to_absolute("E:\\repos\\x")  --> "E:/repos/x"
to_absolute("/")             --> "/"          -- POSIX root
to_absolute("//")            --> "/"          -- same as a single separator
to_absolute("\\\\")          --> "/"          -- ditto, backslash spelling
to_absolute("\\/\\")         --> "/"          -- ditto, mixed spelling
```
