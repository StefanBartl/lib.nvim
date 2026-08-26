# lib.nvim — Binding Cheatsheet

Every user command and autocommand `lib.nvim` installs. This file is
documentation only; the source of truth is `lua/lib/nvim_usrcmds/`
(`usrcmds.lua`, `autocmds.lua`, `actions.lua`). A change there must be
reflected here.

`lib.nvim` is a library, not a feature plugin, so its binding surface is
deliberately small and every part of it is opt-in.

## Table of content

  - [Keymaps](#keymaps)
  - [User commands](#user-commands)
  - [Autocommands](#autocommands)
  - [Switching things off](#switching-things-off)

---

## Keymaps

**None.** A library that other plugins depend on has no business claiming a key
on their behalf, so `lua/lib/nvim_usrcmds/` has no `keymaps.lua` at all — the
one deliberate gap in the three-module `bindings/` split every plugin here uses.

`lib.nvim.bindings.keymap` is a wrapper *for callers* around `vim.keymap.set`; it binds
nothing itself. The only `vim.keymap.set` in the tree that fires is `q` inside
the UI-kit preview surface (`ui/kit/preview.lua`) — buffer-local to a float
this library opened, closed again with the float.

## User commands

Two surfaces over the same actions, deliberately: the flat commands predate the
verb and are kept for muscle memory; the verb is the composer-built one with
`<Tab>` completion at every level. Both dispatch into
`lib.nvim_usrcmds.actions`, so they cannot drift apart.

### Flat

| command | option | desc |
| --- | --- | --- |
| `:CwdHere` | `cwd_here` | Set the local cwd to the directory of the current buffer |
| `:PowershellProfile` | `powershell_profile` | Open the active PowerShell profile in Neovim |

`powershell_profile` defaults to `vim.fn.has("win32") == 1` — the command does
not exist on other platforms unless you ask for it.

### `:Lib`

Built with `lib.nvim.bindings.usercmd.composer`, which dogfoods the module it ships. The
route list mirrors which features are enabled, so the verb never advertises an
action the flat set would also omit.

| command | desc |
| --- | --- |
| `:Lib helptags` | Regenerate all helptags now |
| `:Lib cwd-here` | `lcd` to the current buffer's directory |
| `:Lib ps-profile` | Open the active PowerShell profile |
| `:Lib deps show [{plugin}]` | List a plugin's declared external tools, why each matters, and what is missing |
| `:Lib deps install {plugin}` | Offer to install a plugin's missing external tools (asks first) |
| `:Lib deps reset-first-run [{plugin}]` | Forget that a plugin's (or every plugin's) first-run popup was already shown |

`{plugin}` completes from the `DEPS_PLUGIN` argument type — the set of plugins
that declare a dependency spec, computed at completion time.

The `deps` routes live under `:Lib deps …` rather than a separate `:LibDeps`
command on purpose: a second top-level name for a subordinate feature is
exactly the `:VerbFeatureA`/`:VerbFeatureB` shape the composer exists to
replace.

The generated table is also kept at
[`BINDINGS/Usercmds.md`](BINDINGS/Usercmds.md).

## Autocommands

One, in the augroup `LibNvimUsrCmdsHelptags`:

| event | pattern | option | desc |
| --- | --- | --- | --- |
| `User` | `LazyInstall`, `LazyUpdate`, `LazySync` | `helptags` | Regenerate helptags after lazy.nvim installs or updates plugins |

Two things about it are the result of fixing a bug rather than a first draft,
and both are worth knowing before touching it:

- **It hangs off those three `User` patterns, not `LazyDone`.** `LazyDone`
  fires on *every* start, and `helptags ALL` walks every installed plugin's
  `doc/` directory and rewrites its tags file unconditionally — nothing about
  it is incremental, so the second run in a session costs exactly as much as
  the first. Help files only change when a plugin is installed or updated, and
  those are the events above. `:Lib helptags` covers the case where something
  changed outside lazy's knowledge.
- **The augroup is named and created with `clear = true`.** It used to have no
  group, and `setup()` is called again on every config reload: each call added
  another `User` autocmd for the same three patterns, so a `:Lazy sync` after
  two reloads ran `helptags ALL` three times. At the ~229 ms that costs with a
  hundred-plus plugins, that is visible. A named group makes re-registration
  idempotent by construction.

## Switching things off

Everything is a flag on `setup()`, and each is independent:

```lua
require("lib.nvim_usrcmds").setup({
  helptags           = true,   -- the autocommand + :Lib helptags
  cwd_here           = true,   -- :CwdHere + :Lib cwd-here
  powershell_profile = vim.fn.has("win32") == 1,
  lib_verb           = true,   -- the :Lib verb itself
  deps               = true,   -- the :Lib deps … routes
})
```

Setting `lib_verb = false` drops the verb but keeps the flat commands; setting
an individual feature to `false` drops it from both surfaces at once.
