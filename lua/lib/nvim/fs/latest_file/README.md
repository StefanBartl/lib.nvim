# `lib.nvim.fs.latest_file`

The newest file of some folders, by default only images, optionally only a
recent one.

```lua
local found, err, too_old = require("lib.nvim.fs.latest_file").find(
  { "~/Pictures/Screenshots" },
  { max_age_s = 300 }
)
-- found = { path, age_s, mtime }; without one, err says why and `too_old`
-- holds the newest file when it merely is older than max_age_s (so the caller can ask).
```

`opts.exts` selects other extensions, `opts.now` fixes the clock for specs.
