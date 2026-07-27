# `lib.nvim.fs.dir_guard`

Hold the working directory on a path until released.

## Why this exists

Neovim's cwd is global mutable state that any plugin may change at any time — a
picker that `:lcd`s into a result, a session restore, a test runner, an LSP
`root_dir` hook. Code that deliberately pins the cwd (a project lock, a per-tab
workspace) therefore cannot just call `chdir` once and assume it stuck: it has
to notice when something else moved the cwd and put it back.

This module is that watcher, built on [`chdir`](../chdir/README.md):

- `hold(path)` changes into `path` and keeps it there via `DirChanged`.
- Changes the guard makes itself are ignored, so re-asserting cannot loop.
- The guard watches **exactly the scope it holds** — a global hold ignores a
  window-local `:lcd`, because that does not change the global cwd.
- Releasing does *not* restore the previous directory. The guard holds a
  position; it is not an undo stack.

## Usage

```lua
local dir_guard = require("lib.nvim.fs.dir_guard")

local held = dir_guard.hold("/repo")

vim.cmd.cd("/tmp")
vim.fn.getcwd()  --> "/repo"   (the foreign change was undone)

held.bypass(function()
  vim.cmd.cd("/tmp")   -- allowed for the duration of the callback
end)
vim.fn.getcwd()  --> "/repo"   (restored afterwards)

held.update("/other/repo")  -- move the pin, guard stays active
held.path()                 --> "/other/repo"
held.release()
```

Per-tab hold:

```lua
local held = dir_guard.hold("/repo", { scope = "tab" })
```

Letting the user win:

```lua
local held = dir_guard.hold(root, {
  on_violation = function(new_cwd, held_dir)
    if vim.startswith(new_cwd, held_dir) then
      return false   -- accept: they moved deeper into the same project
    end
    -- anything else is undone
  end,
})
```

## `hold(path, opts)`

Returns `Lib.Fs.DirGuard.Handle`, or `nil, err` when the *initial* change
already failed (unusable path, invalid window/tabpage).

| Option         | Type                                            | Default    | Meaning                                                                 |
|----------------|-------------------------------------------------|------------|--------------------------------------------------------------------------|
| `scope`        | `"global"\|"tab"\|"win"`                        | `"global"` | Passed to `chdir`; also the scope whose cwd is watched.                  |
| `win` / `tab`  | `integer?`                                      | current    | Passed to `chdir`; also used to read the scoped cwd back.                |
| `on_violation` | `fun(new_cwd, held): boolean?`                  | —          | Called before a foreign change is undone. Return `false` to accept it and release the guard. |
| `on_error`     | `fun(err: string)`                              | —          | Called when restoring failed (e.g. the held directory was deleted).      |

## Handle

| Method              | Meaning                                                                     |
|---------------------|------------------------------------------------------------------------------|
| `path()`            | The normalized directory currently held.                                     |
| `is_held()`         | `false` once released.                                                       |
| `update(new_path)`  | Move the pin without releasing. Returns `ok, err`.                           |
| `bypass(fn)`        | Run `fn` with the guard paused, then restore the pin if `fn` moved it. Returns `pcall`'s result. |
| `release()`         | Stop guarding. Does **not** restore the previous directory.                  |

All methods use dot syntax (`held.release()`): the state lives in a closure,
there is no implicit `self`.

## Notes

- The held path is read back from `getcwd()` after the initial change rather
  than taken from the argument, so the comparison key is exactly what Neovim
  reports — normalized, symlink-resolved, no trailing slash.
- Each guard gets its own augroup, so independent guards never clear each
  other. Guards are not reference-counted: two guards on different paths in the
  same scope will fight, and the later one wins each round. Hold one per scope.
- The watcher only reacts to `DirChanged`, which Neovim fires for `:cd`,
  `:tcd`, `:lcd` and `chdir()`. A directory that vanishes underneath the guard
  is not an event; `on_error` reports it on the next restore attempt.
