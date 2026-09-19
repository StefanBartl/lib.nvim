# `lib.nvim.fs.stdpath_config_root`

```lua
local stdpath_config_root = require("lib.nvim.fs.stdpath_config_root")

stdpath_config_root("/home/me/.config/nvim/lua/plugins")  --> "/home/me/.config/nvim"
stdpath_config_root("/home/me/work/some-project/src")     --> nil
```

One question, asked by every LSP root resolver that honours the rule *"the
Neovim config directory is a root of its own"*: **is this directory inside
`stdpath("config")`, and if so, which spelling of it should the server be
given?**

Answers `nil` when `dir` is not inside it. Answers a path that is always a
**prefix of `dir`** when it is.

## The bug this replaces

Both callers used to ask it themselves, with the same two lines:

```lua
local stdconfig = vim.fn.stdpath("config")
if is_subpath(dir, stdconfig) then
  return stdconfig
end
```

That compares two spellings of one directory and loses.

`vim.fn.stdpath("config")` reports whatever Neovim was pointed at, verbatim —
typically `~/.config/nvim`, which on a very large share of real setups is a
**symlink into a dotfiles repo**. The directory on the other side comes from a
buffer name, and Unix Neovim canonicalizes a path on the way into a buffer
name. So the comparison is:

```
dir       = /home/me/dotfiles/nvim/lua/plugins     (what the buffer carries)
stdconfig = /home/me/.config/nvim                  (what stdpath reports)
```

No common prefix, a silent `false`, and the rule never fires. The caller falls
through to its VCS search and roots the language server at **the whole dotfiles
repo** — every file in it loaded into the workspace, for everyone whose Neovim
config is version-controlled, which is most people who have one.

## Which spelling comes back

The **normalized** one, on either branch — never `stdpath("config")` verbatim.

Returning the raw `~/.config/nvim` for a buffer at `~/dotfiles/nvim/...` would
satisfy *"did the rule fire"* while handing the server a root that is not a
prefix of the file it is being asked about — which is worse than the miss it
replaces. Measured against a real `lua-language-server`: it indexes the tree
through the symlink and answers `textDocument/definition` with the **other**
spelling of the file, so jumping to a definition opens a second buffer on a
file that is already open, and edits split across two views of one file.

An earlier version of this module returned `stdpath("config")` byte for byte
on a plain match, on the reasoning that "nothing that resolved correctly
before resolves differently now". That missed a case: `vim.fn.stdpath("config")`
comes back with **native separators** — measured, on every call, on Windows
(`C:\Users\...\nvim`) — while the `dir` it gets compared against is
forward-slash (both production callers build it through `vim.fs.normalize`).
The match itself is normalized, but the byte-for-byte *return value* was not,
so the "genuine prefix of `dir`" promise above was false on every Windows call
that took the plain-match branch. Unix is unaffected: `vim.fs.normalize` is a
no-op there for any path already free of `~`, `//`, and `./`, which every
`stdpath("config")` is — so this only ever changes the separators of the value
Windows gets back, never which directory is named.

## Why the `realpath` is here, once, and not at the call site

[`is_subpath`](../is_subpath/README.md) takes an `opts` argument that routes
both sides through [`normkey`](../normkey/README.md) (`uv.fs_realpath`) and
would close the gap in one character. It is deliberately not used:

- `opts` resolves **both** sides on **every** call. A root resolver runs per
  buffer, for every file in every project — two syscalls each time, on paths
  that may sit on a network share, to re-derive an answer that cannot change.
- `stdpath("config")` is fixed for the session. Its canonical spelling is
  resolved **once** and kept; the comparison itself stays the pure string
  compare it has always been.
- `polymorphic_rootresolver` caches nothing of its own, so "once per call" here
  really did mean once per call.

The cache is keyed on the raw `stdpath("config")` value rather than held
unconditionally, so a test that stubs `vim.fn.stdpath` — the only way to test
any of this — gets a fresh resolution instead of a stale one, with no
cache-invalidation call to forget.

Both known spellings are tried, which covers both platforms without resolving
`dir` at all:

| Platform | What a buffer name typically carries | Which compare typically matches |
| -------- | ------------------------------------- | -------------------------------- |
| Linux / macOS | the canonical spelling (Neovim canonicalizes buffer names) | the canonicalized compare |
| Windows | the literal spelling (measured: it does **not** canonicalize) | the normalized compare |

"Typically", not exclusively — this is about what Neovim itself does to a
buffer name on each platform, not a hard platform split. Either branch can
fire on either platform: nothing stops a Windows user from opening a file
through a config symlink's *resolved* path directly (a tool that already
resolved it, an explicit `cd`), which would take the canonicalized-compare
branch there too, same as Unix.

A `dir` in some third spelling — behind a symlink of its own — still misses,
and still costs nothing.

## Callers

- [`lib.nvim.fs.polymorphic_rootresolver`](../polymorphic_rootresolver/README.md),
  for `cfg.include_stdpath_config`
- `lsp.servers.lua_ls.rootresolver` in `lsp.nvim`, which does the check first,
  ahead of its own scope switch and marker search

## Tests

`TESTS/stdpath_config_root_spec.lua`. The symlinked cases need a **real**
directory symlink — a junction is a different object with different resolution
semantics and would not pin the same thing.

They skip when one cannot be *created*, which is not the same as skipping on
Windows. Creating a symlink there needs `SeCreateSymbolicLinkPrivilege`
(Developer Mode or elevation), so a blanket platform skip looks right and is
not: measured on this repo's own workflow, ubuntu, macos **and**
windows-latest all create it, and all three run the cases. Windows is simply
the one platform allowed to skip, because it is the one where the privilege
can genuinely be absent.

The skip is loud, and raises rather than skipping under `CI` anywhere else:
Linux and macOS are the platforms the bug actually bites on, so a silent skip
there would be a gate reporting confidence it never earned.
