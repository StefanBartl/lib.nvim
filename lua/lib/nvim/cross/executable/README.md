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
executable.clear()                   --> drop every memoized lookup (and the $PATH index)
executable.clear("rg")               --> drop the memoized lookup for "rg" only
executable.warm()                    --> build the $PATH index in the background now (Windows)
```

`mason_bin` appends a `.cmd` suffix on native Windows (matching how Mason
installs its shims there) and confirms the resolved path actually exists via
`uv.fs_stat` before returning it; on any other platform, or when the file is
missing, it returns the unsuffixed path only if that path exists, else `nil`.

`exists`/`path` are memoized per name — a tool installed or removed *during*
a session isn't noticed until the cache is dropped. Call `clear()` after
installing something, or `clear(name)` for a single entry; anything checking
for a tool it just installed itself should clear that name first.
## The $PATH index (native Windows)

Memoizing does not help the first lookup of each name, and a name that is not
installed is the expensive one: `vim.fn.exepath` stats every $PATH entry times
every $PATHEXT extension (72 x 11 on the author's machine, ~40 ms per miss). The
third native lookup therefore starts a background index of $PATH
(`lib.nvim.cross.executable.index`, ~30–65 ms for ~7800 names, one directory per
event-loop tick); from then on names not seen before are answered from a table
in microseconds.

The index reproduces Vim's own lookup, quirks included (checked against
`vim.fn.exepath`/`executable` on a real $PATH: 379 of 380 names identical): $PATH
order first, then inside a directory an exact file name before a $PATHEXT
expansion, any existing file counts whatever its extension, case-insensitive. The
one difference is in its favour: Windows-Store app aliases (`pwsh` from the Store),
which `vim.fn` cannot stat, are found.

It is an answer with an expiry, not a source of truth. It answers "unknown" -- and
the lookup falls back to `vim.fn` -- when $PATH or $PATHEXT changed since it was
built (mason prepends its bin dir mid-session), when it is older than 60 s, or
for anything containing a path separator. `clear(name)` makes that one name skip
the index (a tool installed a moment ago is not in an index built before it).
Other systems never use it: their $PATH is short and has no $PATHEXT multiplier.

`mason_bin` is deliberately not memoized (a direct, single-path `fs_stat`,
and Mason installs binaries mid-session).
