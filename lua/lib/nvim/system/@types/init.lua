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

--- Aggregator surface of `require("lib.nvim.system")`.
---@class Lib.System
---@field env Lib.System.Env.Module
---@field rpc_pipe Lib.System.RpcPipe
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

return {}
