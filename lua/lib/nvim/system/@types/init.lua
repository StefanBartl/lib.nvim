---@meta
---@module 'lib.nvim.system.@types'

--- Computed snapshot of the host environment (see `lib.nvim.system.env`).
--- Platform booleans are mutually exclusive: on WSL `is_wsl == true` and
--- `is_linux == false`.
---@class Lib.System.Env
---@field is_windows boolean  # Native Windows (not WSL).
---@field is_wsl boolean      # Windows Subsystem for Linux (v1 or v2).
---@field is_linux boolean    # Linux, excluding WSL.
---@field is_macos boolean    # macOS (Darwin).
---@field is_pwsh boolean     # `pwsh` (PowerShell Core) is on PATH.
---@field repo_base string|nil # Value of `$REPOS_DIR`, or nil if unset.
---@field pathsep string      # Path separator for the current OS ("\\" or "/").
---@field home string         # Expanded home directory (`~`).

--- Options accepted by `require("lib.nvim.system").setup`.
---@class Lib.System.SetupOptions
---@field publish_globals? boolean|{ fields?: string[] } # Mirror the snapshot to `vim.g.*`. `true` uses defaults; a table forwards `fields`.
---@field rpc_pipe? boolean|table # Start the Windows named-pipe RPC server. `true` uses defaults; a table is forwarded to `rpc_pipe.setup`.
---@field info_usercmd? boolean|string # Register the system-info user command. `true` uses ":SystemInfo"; a string sets the command name.

--- Aggregator surface of `require("lib.nvim.system")`.
---@class Lib.System
---@field env Lib.System.Env.Module
---@field rpc_pipe Lib.System.RpcPipe
---@field info Lib.System.Info
---@field proc_trace Lib.System.ProcTrace
---@field setup fun(opts?: Lib.System.SetupOptions): Lib.System.Env

--- `lib.nvim.system.env` module surface.
---@class Lib.System.Env.Module
---@field get fun(opts?: { refresh?: boolean }): Lib.System.Env
---@field publish_globals fun(opts?: { fields?: string[] }): Lib.System.Env

--- `lib.nvim.system.rpc_pipe` module surface.
---@class Lib.System.RpcPipe
---@field setup fun(opts?: { debug?: boolean, allow_override?: boolean }): nil
---@field is_active fun(): boolean
---@field get_address fun(): string|nil
---@field clear fun(): nil

--- Options for `lib.nvim.system.info.build_cmd` / `get`.
---@class Lib.System.Info.BuildCmdOpts
---@field prefer_fetch? boolean # Use fastfetch/neofetch when installed (default true). `false` forces the uniform "Key : Value" platform probe.

--- Options for `lib.nvim.system.info.show`.
---@class Lib.System.Info.ShowOpts : Lib.System.Info.BuildCmdOpts
---@field clipboard? boolean # Copy the output to the system clipboard (default true).
---@field title? string # Float title, defaults to " System Information ".

--- `lib.nvim.system.info` module surface (cross-platform system information).
---@class Lib.System.Info
---@field build_cmd fun(opts?: Lib.System.Info.BuildCmdOpts): string[] # Probe command as argv list (fastfetch/neofetch or platform-native fallback).
---@field get fun(opts?: Lib.System.Info.BuildCmdOpts): string[]|nil, string|nil # Run the probe; cleaned output lines or nil + error.
---@field show fun(opts?: Lib.System.Info.ShowOpts): integer|nil, integer|nil # Float + clipboard; returns winid, bufnr.
---@field create_usercmd fun(name?: string, opts?: Lib.System.Info.ShowOpts): nil # Register the user command (default :SystemInfo).

--- Options accepted by `lib.nvim.system.proc_trace.start`.
---@class Lib.System.ProcTrace.StartOptions
---@field threshold_ms? integer # Calls at/above this duration get a traceback logged (default 200).
---@field path? string # Log file path (default: stdpath("state") .. "/proc_trace.log").

--- Result returned by `start`/`stop`.
---@class Lib.System.ProcTrace.Result
---@field path string # Log file path.
---@field active boolean # Whether tracing is active after the call.

--- `lib.nvim.system.proc_trace` module surface (blocking-call instrumentation).
---@class Lib.System.ProcTrace
---@field start fun(opts?: Lib.System.ProcTrace.StartOptions): Lib.System.ProcTrace.Result # Wrap vim.fn.system/systemlist, vim.system, vim.fn.jobstart; idempotent.
---@field stop fun(): Lib.System.ProcTrace.Result # Restore the original functions.
---@field is_active fun(): boolean
---@field log_path fun(): string|nil # Path of the active (or last) log file.

return {}
