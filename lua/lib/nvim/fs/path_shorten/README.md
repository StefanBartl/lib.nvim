# `lib.nvim.fs.path_shorten`

Shorten a path for display, in one of two independent styles selected via
`opts.style`.

## Usage

```lua
local path_shorten = require("lib.nvim.fs.path_shorten")

path_shorten("/home/user/projects/big-repo/src/deep/nested/file.lua", 30)
--> ".../nested/file.lua"   (style "fit", the default)

path_shorten("/home/user/projects/big-repo/src/deep/nested/file.lua", nil, { style = "label" })
--> "~/..../nested/file.lua"
```

## `"fit"` style (default)

Preserves the path's start (drive letter or root) and the filename at the
end, collapsing a variable-length middle section into a single ellipsis
(`"…"` by default) until the result fits within `max_len` characters. Falls
back through several strategies as the budget shrinks: full-middle collapse,
then progressively fewer trailing segments kept, then finally an ellipsis
plus as many trailing characters of the raw path as fit. If `path` already
fits `max_len`, it is returned unchanged. `max_len` must be a number `>= 1`;
otherwise `path` is returned unchanged.

## `"label"` style

Always renders `<root>/<ellipsis>/<parent>/<file>` (ellipsis defaults to
`"...."`, distinct from `"fit"`'s default), *ignoring* `max_len` entirely —
ported from Harpoon's menu-label formatter. It resolves the real path
(`vim.uv.fs_realpath`) and rewrites it relative to the home directory (`~`),
a Windows drive, a UNC share, or `/`, showing only the immediate parent
directory's name rather than the full ancestor chain. This is an independent
algorithm from `"fit"`; only the top-level dispatch and the "ellipsis marker"
concept are shared.

## Options — `opts`

| Field      | Type                 | Default            | Applies to |
|------------|----------------------|--------------------|------------|
| `style`    | `"fit"` \| `"label"` | `"fit"`            | both       |
| `ellipsis` | `string`             | `"…"` / `"...."`   | both (different default per style) |

Non-string `path` is returned unchanged (no error).
