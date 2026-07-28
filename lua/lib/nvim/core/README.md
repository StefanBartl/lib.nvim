# `lib.nvim.core`

Small grab-bag of core editor helpers that didn't warrant their own
namespace: memoized executable lookup, and a preallocated `nvim_echo`
wrapper (exposed as `core.simple_echo`, lazily required).

## Usage

```lua
local core = require("lib.nvim.core")

core.has_exec("rg")                       --> true/false, memoized per binary name
core.first_available({ "rg", "grep" })    --> "rg" (first found on PATH), or nil if none
```

`has_exec` caches `vim.fn.executable(bin) == 1` per binary name in a
module-local table — subsequent calls for the same name skip the
`executable()` shell-out. `first_available` walks its candidate list in order
and returns the first hit (also benefiting from that cache), or `nil` if none
of them are on `PATH`.

```lua
core.simple_echo("All done.")
core.simple_echo("File not found.", "WarningMsg", true)   -- highlighted + err flag
```

`simple_echo(msg, hl, is_error)` wraps `vim.api.nvim_echo`, always adding the
message to `:messages` history. It reuses a single preallocated one-element
chunks array across calls to avoid repeated table allocation on hot paths.
`is_error` truthy sets `{ err = true }` in the native opts; falsy leaves the
key out entirely rather than passing `err = false`. Returns whatever
`nvim_echo` returns.
