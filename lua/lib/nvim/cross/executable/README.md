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
```

`mason_bin` appends a `.cmd` suffix on native Windows (matching how Mason
installs its shims there) and confirms the resolved path actually exists via
`uv.fs_stat` before returning it; on any other platform, or when the file is
missing, it returns the unsuffixed path only if that path exists, else `nil`.
