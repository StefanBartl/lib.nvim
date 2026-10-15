# `lib.nvim.fs.portable`

Make a text artifact portable between machines: host-specific root paths become **placeholders** when it
is written, and the placeholders are **resolved** again when it is read -- through a temporary copy, so the
stored file is never touched and stays valid for every machine that shares it.

Generalised from `sessions.nvim`'s `portable.lua`; useful for any plugin that syncs notes, bookmarks or
project configs across machines (a `:mksession` file, a bookmark list, a project config with absolute paths).

## Usage

```lua
local portable = require("lib.nvim.fs.portable")
local roots = { { path = vim.fn.getcwd(), placeholder = "{{PROJECT_ROOT}}" } }

-- after saving: paths -> placeholders, in place
portable.make_file(session_file, roots)

-- before loading: placeholders -> this machine's paths, through a temp copy
local src, is_temp, err = portable.resolve_file(session_file, roots)
vim.cmd.source(src)
if is_temp then
  vim.fn.delete(src)
end
```

The pure halves work on strings: `portable.make(content, roots)` and `portable.resolve(content, roots, opts)`.

## API

| Call | Meaning |
|---|---|
| `make(content, roots)` | Replace each root by its placeholder. Spellings: forward-slashed, backslashed, and the `:~` form. The longest root wins where roots are nested, whatever the list order. |
| `resolve(content, roots, opts?)` | Replace the placeholders by the roots' paths (forward-slashed). Placeholders that are not in `roots` stay. `opts.remap = { [old_prefix] = new_prefix }` translates another machine's prefixes. |
| `make_file(path, roots)` | Rewrite `path` in place, byte-exact and atomic (a symlink target is kept). Returns `ok, err`. A file that has nothing to replace is not rewritten. |
| `resolve_file(path, roots, opts?)` | Returns `source, is_temp, err`. `source` is a temporary copy (`opts.suffix`, default `.tmp`) when anything was resolved, otherwise `path`. The caller deletes a temp copy. On a read or write failure `path` comes back unresolved with `err` -- never a path that does not exist. |

A root is `{ path, placeholder }`; both must be non-empty strings (an error otherwise).

## Boundary rule

A path ends where the next byte cannot continue a file name (`[%w_%-.~]`). `E:/repos/ui.nvim` is a
prefix of `E:/repos/ui.nvim-backup`; replacing it blindly would turn the latter into
`{{ROOT}}-backup/...`, which is wrong the moment the placeholder is re-anchored to a directory the sibling
was never under. The same rule applies to `remap`. Placeholders themselves are matched as plain text.
