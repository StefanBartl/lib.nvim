# `lib.nvim.cross`

Cross-platform namespace root: platform detection, path/separator helpers,
shell/process runners, and libuv-backed spawn primitives, aggregated behind
one table so callers don't have to know the internal file layout.

The `init.lua` itself defines no logic — it only `require`s the child
modules and re-exports them under a stable shape:

```lua
local cross = require("lib.nvim.cross")

cross.is_windows()        -- lua.nvim.cross.platform.is_windows
cross.is_wsl()
cross.is_macos()
cross.is_linux()
cross.is(platform_name)

cross.executable.exists("rg")
cross.executable.path("rg")
cross.executable.find({ "rg", "grep" })
cross.executable.mason_bin("stylua")

cross.fs.cwd()                          -- lib.nvim.cross.fs._cwd
cross.fs.expand_path("~/foo/$HOME/bar")
cross.fs.mutate.rename_file(old, new)   -- see lib.nvim.cross.fs.mutate

cross.separators.unify_slashes([[a\b]])
cross.separators.normalize("a/b/c")
cross.separators.collapse_dots("a/./b/../c")
cross.separators.has_win_sep([[C:\repos]])
cross.separators.drive_upper("c:/repos")

cross.uv.spawn_command(...)
cross.uv.spawn_shell_command(...)
cross.uv.spawn_capture(argv, opts, on_done)
cross.uv.spawn_stream(argv, opts, on_line, on_exit)
cross.uv.wait_until(predicate, opts, cb)

cross.run.shell()
cross.run.run(cmd, cb)
cross.run.run_blocking(cmd)
cross.run.run_detached(argv)
cross.run.run_argv.run_blocking(argv, input)

cross.open_default(target) -- open a path/URL with the OS default handler
cross.reveal_in_fm(path, opts) -- show a path in the system file manager
```

Note that `cross.fs.cwd` (`lib.nvim.cross.fs._cwd`) and `cross.uv.fs`
(`lib.nvim.cross.uv.fs`, not re-exported here) are two independent modules
with identical bodies — both resolve the cwd via `vim.uv`/`vim.loop`,
falling back to `vim.fn.getcwd()`. `cross.uv.fs` is not currently wired into
this table.

Prefer requiring a leaf module directly (e.g.
`require("lib.nvim.cross.fs.expand_path")`) when only one function is
needed; use this aggregate when a caller already holds `cross` and wants
several pieces off of it.
