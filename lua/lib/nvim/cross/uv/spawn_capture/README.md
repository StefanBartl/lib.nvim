# `lib.nvim.cross.uv.spawn_capture`

Async spawn of an argv command with buffered stdout/stderr capture and an
optional timeout, built directly on `vim.uv`/`vim.loop` (no shell).
Complements `lib.nvim.cross.run`/`lib.nvim.cross.run_argv` (blocking, or
async via a shell string) and `lib.nvim.cross.uv.spawn_command`/
`spawn_shell_command` (fire-and-inherit-stdio, no capture): none of those
cover "spawn argv, buffer all output, invoke one callback at exit, with an
optional kill-on-timeout". For output delivered incrementally while the
process runs, see `lib.nvim.cross.uv.spawn_stream` instead.

## Usage

```lua
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

spawn_capture({ "git", "status", "--porcelain" }, { cwd = repo_root, timeout_ms = 5000 }, function(result)
  -- result = { ok, code, signal, stdout, stderr, timed_out }
  if result.ok then
    print(result.stdout)
  end
end)
```

`opts` is optional: `{ timeout_ms?, cwd?, env? }`. `env`, like libuv's own
spawn `env` option, is an array of `"KEY=VALUE"` strings — not a
`{ [key] = value }` dict — and is passed through unconverted.

If the timeout elapses before the process exits, the handle is killed with
`sigkill` and the result settles with `timed_out = true`, `ok = false`,
`code = -1`. If the process can't be spawned at all (e.g. binary missing),
`on_done` still fires, with `stderr` set to `"failed to spawn: " .. argv[1]`.

`on_done` is always dispatched via `vim.schedule`, so it runs with the full
Neovim API available — unlike the raw libuv pipe-read callbacks that feed
it internally.
