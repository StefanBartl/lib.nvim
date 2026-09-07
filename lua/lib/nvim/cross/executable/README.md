# `lib.nvim.cross.executable`

PATH resolution and Mason-managed binary lookup, consolidating a pattern
independently re-implemented across several plugins (open.nvim's
`util.find_exec`, dap.nvim's `utils.executable`).

## Usage

```lua
local executable = require("lib.nvim.cross.executable")

executable.exists("rg")              --> true/false, vim.fn.executable(name) == 1
executable.path("rg")                --> absolute path, or nil if not on PATH
executable.find("rg")                --> "rg", or nil
executable.find({ "rg", "grep" })    --> first candidate found on PATH, or nil
executable.mason_bin("stylua")       --> stdpath("data")/mason/bin/stylua[.cmd], or nil if not installed
executable.clear()                   --> drop every memoized lookup
executable.clear("rg")               --> drop the memoized lookup for "rg" only
```

`mason_bin` appends a `.cmd` suffix on native Windows (matching how Mason
installs its shims there) and confirms the resolved path actually exists via
`uv.fs_stat` before returning it; on any other platform, or when the file is
missing, it returns the unsuffixed path only if that path exists, else `nil`.

`exists`/`path` are memoized per name — a tool installed or removed *during*
a session isn't noticed until the cache is dropped. Call `clear()` after
installing something, or `clear(name)` for a single entry; anything checking
for a tool it just installed itself should clear that name first.
`mason_bin` is deliberately not memoized (a direct, single-path `fs_stat`,
and Mason installs binaries mid-session).
