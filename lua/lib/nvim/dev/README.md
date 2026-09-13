# `lib.nvim.dev`

Tooling for whoever is developing *across* the plugin ecosystem lib.nvim sits
under, not for a single plugin's own runtime. Occupants: `duplicates.lua`,
`reload.lua`.

## `reload.lua` — reload a config module on save

```lua
require("lib.nvim.dev.reload").watch()
```

One line in **your own config's** startup, not in a plugin: registers a
`BufWritePost` autocmd that reloads whatever module under
`stdpath("config")/lua` you just saved (`package.loaded[name] = nil`,
`require(name)` again) — matched lazily per save, not by pre-globbing every
`*.lua` file at startup. `M.module(name)` is the reload alone, if you already
have your own autocmd wiring.

## `duplicates.lua` — cross-repo function duplication

Identical function bodies across sibling repos — candidates for extraction
into lib.nvim itself, not a general clone-detector. Promoted from a
throwaway `python duplicate_functions.py` that walked a hardcoded path;
this is the same detection (normalize each top-level function body, group by
the normalized text, keep groups spanning two or more different repos),
parameterized by a root directory instead.

```lua
local duplicates = require("lib.nvim.dev.duplicates")

duplicates.scan("E:/repos")   -- default: cwd
duplicates.lines("E:/repos")  -- the same, as printable lines
```

**Scope: `root`'s immediate subdirectories, not `root` itself.** A hit only
means something when the *same* body shows up in *two different repos*, so
point this at a directory holding several sibling checkouts — `root`'s own
`lua/` (if it has one) is never itself scanned as a repo. Pointing it at a
single plugin's own root, with no sibling checkouts underneath, correctly
finds nothing: there is no second repo to duplicate against.

lib.nvim's own directory is always excluded from the repo set — the question
this answers is "what should move INTO lib.nvim", so lib.nvim's own code is
never itself a candidate.

`duplicates.create_usercmd()` registers `:LibDuplicateScan [path]`. Put that
one line in **your own config**, not in a plugin. `path` is optional and
defaults to cwd — run it from the directory that holds your sibling repos.

```lua
require("lib.nvim.dev.duplicates").create_usercmd()
```
