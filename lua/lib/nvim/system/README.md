# `lib.nvim.system`

Host-environment namespace: a cached snapshot of the OS / shell / well-known
paths, a Windows named-pipe RPC helper, and a cross-platform system-information
probe. This is the library-side home of what used to live in a per-config
`system` module.

Guiding ideas:

* **compute once** — the environment snapshot is memoized; detection runs a
  single time and every later `get()` returns the same table.
* **pure by default** — nothing global is touched on `require` or `get()`;
  publishing to `vim.g.*` and starting the RPC server are **opt-in**.
* **no duplicated detection** — platform booleans delegate to
  [`lib.nvim.cross.platform`](../cross), so OS logic lives in exactly one place.

---

## Module structure

```
lib.nvim.system/
├── init.lua        -- aggregator: env, rpc_pipe, info, proc_trace, and opt-in setup()
├── env.lua         -- computed, memoized host-environment snapshot
├── rpc_pipe.lua    -- predictable Windows named-pipe RPC server
├── info.lua        -- cross-platform system information (float + clipboard)
├── proc_trace.lua  -- instrumentation for system()/jobstart/vim.system calls
└── @types/         -- LuaLS types (Lib.System.*)
```

Entry point is `require("lib.nvim.system")`. Individual submodules can also be
required directly (tree-shake friendly, recommended in plugin code):

```lua
local env = require("lib.nvim.system.env").get()
```

---

## `lib.nvim.system.env`

A memoized snapshot of the host environment.

### Fields (`Lib.System.Env`)

| Field        | Type          | Meaning                                          |
| ------------ | ------------- | ------------------------------------------------ |
| `is_windows` | `boolean`     | Native Windows (not WSL).                        |
| `is_wsl`     | `boolean`     | Windows Subsystem for Linux (v1 or v2).          |
| `is_linux`   | `boolean`     | Linux, **excluding** WSL.                        |
| `is_macos`   | `boolean`     | macOS (Darwin).                                  |
| `is_pwsh`    | `boolean`     | `pwsh` (PowerShell Core) is on `PATH`.           |
| `repo_base`  | `string\|nil` | Value of `$REPOS_DIR`, or `nil` if unset.        |
| `pathsep`    | `string`      | Path separator for the current OS (`\` or `/`).  |
| `home`       | `string`      | Expanded home directory (`~`).                   |

> **WSL semantics.** Unlike a naive `not win and not mac` definition, the
> platform booleans here are **mutually exclusive**. On WSL you get
> `is_wsl == true` and `is_linux == false`.

### `env.get(opts?) -> Lib.System.Env`

Returns the cached snapshot, computing it once on first call.

```lua
local env = require("lib.nvim.system.env").get()

if env.is_windows then
  -- ...
elseif env.is_wsl then
  -- ...
end
```

Pass `{ refresh = true }` to recompute (rarely needed — the host OS does not
change during a session):

```lua
local fresh = require("lib.nvim.system.env").get({ refresh = true })
```

### `env.publish_globals(opts?) -> Lib.System.Env`

Opt-in side effect: mirror selected snapshot fields to `vim.g.<field>`. This
exists for consumers that read the globals directly — e.g. from a plugin spec
or Vimscript — rather than calling `get()`.

```lua
require("lib.nvim.system.env").publish_globals()
-- now vim.g.is_windows, vim.g.is_wsl, vim.g.is_linux,
--     vim.g.is_macos, vim.g.is_pwsh, vim.g.repo_base are set
```

By default the platform/shell/repo fields are published; `pathsep` and `home`
are intentionally left out (read them from the snapshot). Override the set with
`{ fields = { ... } }`.

---

## `lib.nvim.system.rpc_pipe`

Starts a **predictable** RPC server on a Windows named pipe, so external tools
can always reach Neovim at `\\.\pipe\nvim-<USERNAME>` instead of a random
address. It is a no-op off Windows and stays out of the way inside test runners
(`NEOTEST_RUNNING`, Plenary, `nvim-test`).

### `rpc_pipe.setup(opts?)`

```lua
require("lib.nvim.system.rpc_pipe").setup({
  debug = false,          -- emit vim.notify debug/warn messages
  allow_override = true,  -- respect a pre-set NVIM_LISTEN_ADDRESS (default)
})
```

Behavior:

* On non-Windows: returns immediately.
* In a detected test environment: skips setup (keeps neotest & friends happy).
* If `NVIM_LISTEN_ADDRESS` is already set and `allow_override` is true: leaves
  it untouched.
* Otherwise: `serverstart(\\.\pipe\nvim-<USERNAME>)` and export
  `NVIM_LISTEN_ADDRESS`. Failures fall back silently (only surfaced with
  `debug = true`).

### Introspection helpers

```lua
local rpc = require("lib.nvim.system.rpc_pipe")
rpc.is_active()    -- boolean: is NVIM_LISTEN_ADDRESS set?
rpc.get_address()  -- string|nil: current address
rpc.clear()        -- unset NVIM_LISTEN_ADDRESS (useful in tests)
```

---

## `lib.nvim.system.info`

Cross-platform system information (OS, CPU, RAM, GPU, uptime, …), extracted
from a per-config `:SystemInfo` user command.

Backend selection (`build_cmd`):

1. `fastfetch --logo none` if installed,
2. `neofetch --off` if installed,
3. otherwise a platform-native probe with uniform `Key : Value` output:
   * **Windows** — PowerShell (`pwsh` preferred) + CIM queries,
   * **macOS** — `sw_vers` / `sysctl` / `system_profiler`,
   * **Linux & WSL** — `/etc/os-release`, `/proc`, DMI (each field degrades
     gracefully when a source is missing).

Commands are built as **argv lists**, never shell strings — Neovim executes
them directly (no `'shell'`/cmd.exe), so quoting problems (^M remnants, broken
escapes) cannot occur. Pass `{ prefer_fetch = false }` to skip the fetch tools
and force the uniform probe.

### API

```lua
local info = require("lib.nvim.system.info")

info.build_cmd(opts?)          -- string[]: the probe argv
info.get(opts?)                -- string[]|nil, string|nil: cleaned lines or nil + error
info.show(opts?)               -- winid|nil, bufnr|nil: centered float, q/<Esc> closes
info.create_usercmd(name?, opts?)  -- register :SystemInfo (or a custom name)
```

`show` copies the output to the system clipboard by default (`+` register via
`lib.nvim.cross.copy_to_clipboard`, plus the `*` selection where available);
disable with `{ clipboard = false }`. The float reuses
`lib.nvim.window.make_scratch` (centered, rounded border, `nice_quit`).

```lua
-- Typical config bootstrap:
require("lib.nvim.system.info").create_usercmd()   -- :SystemInfo
-- or via setup (see below):
require("lib.nvim.system").setup({ info_usercmd = true })
```

---

## `lib.nvim.system.proc_trace`

Instrumentation for the process-spawning APIs: `vim.fn.system`,
`vim.fn.systemlist`, `vim.system`, `vim.fn.jobstart`. Wraps each one to
measure call duration and, for calls at or above a configurable threshold,
appends a stack traceback pointing at the caller to a log file.

**Why this exists.** A UI freeze on the main thread is almost always one of
these calls (or a burst of them) blocking longer than expected — a hung
external process, a slow filesystem/network path, or too many spawns in a
tight loop. `proc_trace` turns "something froze for a while" into "this call,
from this plugin, took this long" without attaching a debugger.

### API

```lua
local trace = require("lib.nvim.system.proc_trace")

trace.start(opts?)   -- Lib.System.ProcTrace.Result: { path, active }. Idempotent.
trace.stop()          -- Lib.System.ProcTrace.Result. Restores the originals.
trace.is_active()     -- boolean
trace.log_path()       -- string|nil: path of the active (or last) log file
```

`opts` (all optional):

| Field           | Default                                | Meaning                                    |
| --------------- | --------------------------------------- | ------------------------------------------ |
| `threshold_ms`  | `200`                                    | Calls at/above this duration get a traceback. |
| `path`          | `stdpath("state") .. "/proc_trace.log"`  | Log file location.                          |

```lua
-- As early as possible (ideally the first line of init.lua — see limits below):
require("lib.nvim.system.proc_trace").start({ threshold_ms = 200 })

-- ... reproduce the freeze ...

local result = require("lib.nvim.system.proc_trace").stop()
vim.cmd("edit " .. result.path)
```

Log format — one line per call, with a traceback appended for slow ones:

```
[+    2873ms] jobstart          2103ms  git -C . rev-parse --show-toplevel
    stack traceback:
    	.../workspace-diagnostics.nvim/lua/workspace-diagnostics/init.lua:13: in function 'workspace_files'
    	...
```

### Honest limits (read before relying on this alone)

* **Only calls through these exact API tables are seen.** A caller that
  cached a local reference before `start()` ran (`local system =
  vim.fn.system`) bypasses the wrapper entirely. Call `start()` as early as
  possible — ideally the very first line of `init.lua` — to minimize this.
* **LSP clients and other C-internal spawns are invisible here** — they never
  go through `vim.fn.*` / `vim.system`. Pair this with an OS-level process
  monitor for full coverage (debugging.nvim's `:Debug proc watch` drives one).
* **`vim.system(...):wait()`** (synchronous use) is not separately timed;
  only the async `on_exit` path is wrapped. The dominant real-world use
  (async with a callback) is covered.

Pure by default: nothing happens until `start()` is called, and `stop()`
fully restores the original functions.

---

## `lib.nvim.system.setup(opts?)`

One opt-in entry point that activates the environment "features" a config
wants. Everything is off by default, so the module stays a pure helper until
you ask for a side effect.

```lua
-- Typical config bootstrap:
require("lib.nvim.system").setup({
  publish_globals = true,  -- mirror the snapshot to vim.g.* (or { fields = {...} })
  rpc_pipe = true,         -- start the Windows named-pipe RPC server (or an opts table)
  info_usercmd = true,     -- register :SystemInfo (or a string for a custom name)
})
```

The flags accept either `true` (use defaults) or a table/string (forwarded to
`env.publish_globals` / `rpc_pipe.setup` / `info.create_usercmd`). The call
returns the cached `Lib.System.Env` snapshot.

---

## Consuming via the aggregator

```lua
local lib = require("lib")
lib.system.env.get().is_windows
lib.system.setup({ publish_globals = true })
lib.system.proc_trace.start()
```

Direct module paths (`require("lib.nvim.system.env")`) are always the most
efficient way to consume the library and are recommended in plugin code.

---
