# `lib.nvim.fs.chdir`

Scope-aware working-directory change: global (`:cd`), tab-local (`:tcd`) or
window-local (`:lcd`), with normalization, validation, and no throwing.

## Why not `vim.fn.chdir()`

`vim.fn.chdir()`'s scope is *implicit*: it changes the global cwd, the tab's,
or the window's — depending on what the current window happens to have. The
same call therefore means different things in different windows. Code that
manages a cwd deliberately (a project lock, a per-tab workspace, a task runner
that restores the cwd afterwards) has to be able to say which scope it means.

On top of that this module handles the ceremony that otherwise gets copy-pasted
around every call site:

- `path` is made absolute and canonicalized through
  [`normkey`](../normkey/README.md) — `~` expansion, symlinks resolved, forward
  slashes, upper-cased Windows drive letter. The result compares equal to
  `vim.fn.getcwd()`, which reports libuv's physical (symlink-resolved) cwd.
- A trailing slash is dropped (except on a root like `/`, `C:/`,
  `//host/share`), because `getcwd()` never returns one — without this, a
  caller holding or watching a directory would compare unequal to its own cwd.
- A missing path, or one that is not a directory, is rejected *before* the
  command runs.
- Every failure comes back as `false, err`. Nothing throws, so this is safe to
  call straight from an autocmd or a `uv` callback via `vim.schedule`.

## Usage

```lua
local chdir = require("lib.nvim.fs.chdir")

chdir("~/projects/app")                          --> true
chdir("/repo", { scope = "tab" })                -- :tcd in the current tabpage
chdir("/repo", { scope = "win", win = winid })   -- :lcd in that window
chdir("/repo", { scope = "tab", tab = tabid })   -- :tcd in that tabpage

local ok, err = chdir("/does/not/exist")
-- false, "chdir: not a directory: /does/not/exist"
```

## Parameters

| Name   | Type                  | Default    | Meaning                                                        |
|--------|-----------------------|------------|----------------------------------------------------------------|
| `path` | `string`              | —          | Directory to change into. `~` and relative paths are allowed.  |
| `opts.scope` | `"global"\|"tab"\|"win"` | `"global"` | Which scope the change applies to.                   |
| `opts.win`   | `integer?`      | current    | Window to run the change in (via `nvim_win_call`).             |
| `opts.tab`   | `integer?`      | current    | Tabpage whose current window is borrowed; ignored when `win` is set. |

## Returns

`boolean ok, string? err` — the resolved path is deliberately not returned;
read it back with `vim.fn.getcwd()` (optionally scoped: `getcwd(win, tab)`).

## Notes

- A tab-local `:tcd` has to run from *some* window inside that tabpage — there
  is no tabpage-call API — so the tab's current window is borrowed via
  `nvim_win_call`, which does not fire window-enter autocmds.
- `scope = "global"` uses `:cd`, which per Vim semantics also clears a
  window-local directory for the current window. That is intentional: a global
  change that a stale `:lcd` silently overrides would be a lie.
- To *hold* a directory against other code changing it, see
  [`dir_guard`](../dir_guard/README.md), which is built on this module.
