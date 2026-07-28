Converts an absolute file path into the Lua require-style module path
`lua-language-server` (and `require`) expect, by locating the `/lua/` segment
in the path and transforming everything after it: backslashes are normalized
to `/` first, the `.lua` extension is stripped, a trailing `/init` segment is
stripped, and the remaining `/`-separated path is joined with `.`.

Returns `nil` when the path contains no `/lua/` segment at all (nothing to
anchor the module path on). Only the **first** `/lua/` occurrence is used, so
a path with more than one `lua` directory in it (e.g. a vendored dependency
nested under another plugin's `lua/`) resolves relative to the outermost one.

Example: `…/plugin/lua/lib/nvim/fs/is_dir/init.lua` → `lib.nvim.fs.is_dir`.
