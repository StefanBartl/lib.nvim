Converts every backslash in `path` to a forward slash — a pure string
transform: no expansion, no absolute-path resolution, no collapsing of
repeated separators. Use this to keep a path in forward-slash form
regardless of the current OS (Neovim's own API and libuv both accept `/`
on Windows too) — the opposite direction from
`lib.nvim.cross.fs.separators.normalize`, which converts *to* the current
OS's native separator.

```lua
local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

unify_slashes([[a\b\c]])   --> "a/b/c"
unify_slashes("a/b/c")     --> "a/b/c"  -- already unified, unchanged
unify_slashes([[a\\b]])    --> "a//b"   -- repeated separators are not collapsed
```

Raises an assertion error if `path` is not a string.
