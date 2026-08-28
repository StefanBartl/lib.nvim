# `lib.nvim.bindings`

The keymap (`keymap/`), autocmd (`autocmd/`), and user-command (`usercmd/`)
registries, plus `docs_util` (path helpers shared by the two `docs.lua`
generators) and `audit.lua`, documented here since it does not belong to
just one of the three.

## `audit.lua` — keymap actions vs. command routes

`keymap/docs` and `usercmd/docs`/`autocmd/docs` answer "what got written to
disk". `audit.lua` answers a different question: does every user-facing
keymap action have a discoverable `:command` counterpart, or vice versa —
the thing you can only see by holding both registries next to each other.

```lua
local audit = require("lib.nvim.bindings.audit")

audit.keymap_actions()      -- every registered keymap action
audit.command_routes()      -- every registered command route (composer verbs
                             -- expanded to their subcommand paths, plain
                             -- usercmd.create() calls as "(plain)")
audit.gaps()                -- keymap actions with no obvious command
                             -- counterpart -- a candidate list, not a verdict
audit.lines() / audit.gap_lines()   -- the same, as printable lines
```

Every function takes an optional `root` (a directory path) to scope the
result to one repo — `nil` means "everything registered in this session, no
filtering". Keymap scoping resolves the plugin name from `root/lua/*` (one
subdirectory = that plugin); command scoping filters `usercmd.registered()`'s
plain records by call-site path. Composer verbs are never scoped by `root` —
a verb `Handle` carries no source location to filter on, and in practice a
session holds few of them, each named after the plugin that owns it.

`audit.create_usercmd()` registers `:LibBindingsAudit [path]` and
`:LibBindingsAuditGaps [path]`. Put that one line in **your own config**, not
in a plugin — the same reasoning `usercmd/docs.lua`'s own
`create_usercmd()` gives. `path` is optional; omitted, both commands report
on the whole session.

```lua
require("lib.nvim.bindings.audit").create_usercmd()
```
