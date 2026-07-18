# `lib.nvim.cross.uv.spawn_stream`

Async spawn of an argv command with **line-by-line** streaming of stdout/stderr
and an optional timeout.

## Where it sits

| Module                        | argv-safe | async | output delivery              |
|-------------------------------|-----------|-------|------------------------------|
| `cross.run.run`               | ✗ (shell string) | ✓ | buffered, once at exit  |
| `cross.run_argv`              | ✓         | ✗ (blocks) | buffered, returned      |
| `cross.uv.spawn_capture`      | ✓         | ✓     | buffered, once at exit       |
| `cross.uv.spawn_command`      | ✓         | ✓     | inherited stdio (not captured) |
| **`cross.uv.spawn_stream`**   | ✓         | ✓     | **streamed, per line**       |

Use this one when output must be consumed while the process is still running:
a long `rg` scan filling a picker incrementally, a dev server whose log lines
are relayed into a buffer, a build reporting progress live.

Note there is **no `vim.system` / `jobstart` version fallback** here, and none
is needed: `vim.uv`/`vim.loop` has existed since Neovim 0.5, whereas
`vim.system` only landed in 0.10. Plugins that stream via `vim.system` carry a
`jobstart` fallback purely to cover that gap.

## Usage

```lua
local spawn_stream = require("lib.nvim.cross.uv.spawn_stream")

local results = {}

local kill = spawn_stream(
  { "rg", "--vimgrep", "--", pattern, cwd },
  { cwd = cwd, timeout_ms = 10000 },
  function(line)              -- one complete stdout line, no trailing newline
    results[#results + 1] = line
  end,
  function(res)               -- runs via vim.schedule — full API available
    if res.timed_out then
      vim.notify("search timed out", vim.log.levels.WARN)
    end
    render(results)
  end
)

-- later, e.g. when the picker closes:
if kill then kill() end
```

## Fast event context

`on_line` and `on_stderr_line` are driven straight from the libuv read
callback, so they run in a **fast event context**. Most of `vim.fn`/`vim.api`
is off-limits in there (`E5560`). Collect into a table and render from
`on_exit`, wrap the body in `vim.schedule`, or use fast-event-safe helpers such
as [`lib.nvim.fs.mkdirp`](../../../fs/mkdirp/README.md).

`on_exit` is dispatched through `vim.schedule` and has no such restriction.

## Options — `Lib.Cross.Uv.SpawnStream.Opts`

| Field            | Type                 | Default     | Meaning                                              |
|------------------|----------------------|-------------|------------------------------------------------------|
| `timeout_ms`     | `integer?`           | none        | Kill after N ms, settle with `timed_out = true`.      |
| `cwd`            | `string?`            | inherited   | Working directory for the child.                      |
| `env`            | `string[]?`          | inherited   | libuv's shape: `{"KEY=VALUE", …}`, not a dict.         |
| `on_stderr_line` | `fun(line)?`         | none        | Per-line stderr callback. Omit to discard stderr.     |
| `kill_signal`    | `string?`            | `"sigterm"` | Signal sent by the returned kill function.            |

## Result — `Lib.Cross.Uv.SpawnStream.Result`

| Field         | Type       | Meaning                                                |
|---------------|------------|--------------------------------------------------------|
| `ok`          | `boolean`  | Exited 0 and did not time out.                          |
| `code`        | `integer`  | Exit code; `-1` when killed or not spawnable.           |
| `signal`      | `integer`  | Terminating signal, `0` when none.                      |
| `timed_out`   | `boolean`  | `timeout_ms` elapsed and the process was killed.        |
| `spawn_error` | `string?`  | Set only when the spawn itself failed (binary missing). |

## Line semantics

- Lines are split on `\n`; a trailing `\r` is stripped, so CRLF output from
  Windows tooling yields clean lines.
- A process that exits without a final newline still gets its last partial
  line emitted, immediately before `on_exit`.
- The module settles only once the child has exited **and** both pipes have
  reported EOF. The process-exit callback can fire while pipes still hold
  unread data — settling on exit alone would truncate the tail of a chatty
  process.
