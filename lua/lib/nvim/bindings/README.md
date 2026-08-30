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

`audit.create_usercmd()` registers `:LibBindingsAudit [path]`,
`:LibBindingsAuditGaps [path]` and `:LibBindingsAuditKeys [path]`. Put that
one line in **your own config**, not in a plugin — the same reasoning
`usercmd/docs.lua`'s own `create_usercmd()` gives. `path` is optional;
omitted, all three commands report on the whole session.

```lua
require("lib.nvim.bindings.audit").create_usercmd()
```

<a name="portability"></a>

## `keymap/portability.lua` + `audit.key_risks` — can the terminal send it?

A key can be bound perfectly and still never fire, because the terminal never
sends it. `<C-CR>`, `<C-#>`, `<C-S-x>` need an extended encoding ("CSI u" or
modifyOtherKeys); without it, the mapping is simply dead and nothing says so.

**This is not detectable at runtime, and the module does not pretend
otherwise.** Three separate walls:

1. *Neovim cannot press its own keys.* `nvim_feedkeys()`/`nvim_input()` enter
   below the terminal's input decoder, so a self-test passes on a terminal
   that could never have sent the key. A terminal cannot send a key to itself.
2. *The one real signal is not exposed.* Nvim queries the terminal for "CSI u"
   support at startup (`:help tui-csiu`) but hands the answer to no Lua API —
   there is no `keyprotocol` option in 0.12, and `g:termfeatures` carries only
   `osc52`.
3. *It is the wrong question.* "This terminal speaks the protocol" is not
   "this key survives the trip" — tmux and ssh rewrite sequences in between,
   and the keyboard layout gets there first: on a German layout AltGr *is*
   Ctrl+Alt, so `<C-M-q>` is consumed to produce `@` and no key event exists.

So the notation is classified statically instead, which *is* decidable:

```lua
local port = require("lib.nvim.bindings.keymap.portability")

port.classify("<leader>x")   --> "portable", ""
port.classify("<A-Right>")   --> "portable", ""   (xterm sequence, no ESC prefix)
port.classify("<C-M-y>")     --> "common",   "Alt is sent as an ESC prefix ..."
port.classify("<C-CR>")      --> "fragile",  "Ctrl+CR is the same byte as CR"
```

| tier | meaning |
| --- | --- |
| `portable` | a plain byte or a terminfo/xterm sequence — arrives everywhere |
| `common` | arrives nearly everywhere, through a mechanism with a known off switch (Alt as ESC prefix, Ctrl+Space as NUL) or a known ambiguity (`<C-i>` *is* `<Tab>`'s byte). Fine as the everyday key, not as the only one |
| `fragile` | needs "CSI u"/modifyOtherKeys or a GUI — silently never arrives otherwise |

`audit.key_risks()` is the lint on top: it reports every registered action
whose keys are **all** non-portable, which is the only case that actually
costs the user something. An action bound to `<C-M-y>` *and* `<leader>cy`
never appears; one bound to `<C-M-y>` alone does.

```lua
audit.key_risks()        -- actions with no portable key, fragile ones first
audit.key_risk_lines()   -- the same, as printable lines
```

The fix is never detection — it is a portable `lhs` next to the fancy one, and
`register()` has always taken a list:

```lua
cycle_char_next = { default = { "<C-M-y>", "<leader>cy" }, rhs = api.next, desc = "..." },
```

`:LibBindingsAuditKeys [path]` is the same report interactively.
