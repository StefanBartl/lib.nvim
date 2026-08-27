---@meta
---@module 'lib.nvim.cross.run.env.@types'

---Options accepted by `lib.nvim.cross.run.env.build`/`.path`/`.apply`.
---@class Lib.Cross.Run.Env.Opts
---@field base? table<string,string> Starting environment (default `vim.fn.environ()`)
---@field extra_paths? string[] Directories prepended to `PATH`, highest priority
---@field passthrough? string[] Extra variable names to carry over from `vim.env` when absent from `base`
---@field vars? table<string,string> Explicit overrides, applied last
---@field mason? boolean Also put Mason's `bin` directory on `PATH` (default `false`)
---@field login_shell? boolean Harvest a POSIX login shell's environment and fill gaps from it (blocking, cached; no-op on Windows)
---@field timeout_ms? integer Timeout for the `login_shell` probe (default `3000`)

---Spawn-environment builder — completed `PATH` plus recoverable
---session/keyring variables for `vim.system`/`vim.uv.spawn`/`jobstart`.
---@class Lib.Cross.Run.Env
---@field SESSION_VARS table<string, string[]> Known session/keyring variable names, keyed by platform (`common`, `linux`, `wsl`, `macos`, `windows`)
---@field session_vars fun(): string[] # Names relevant on the current platform, `common` first
---@field missing fun(): string[] # Known session variables absent from Neovim's own environment (diagnostic)
---@field candidate_dirs fun(): string[] # Existing well-known binary directories for this platform (cached)
---@field login_shell_env fun(timeout_ms?: integer): table<string,string>|nil # Environment of `$SHELL -lc env`; nil on native Windows (cached)
---@field path fun(opts?: Lib.Cross.Run.Env.Opts): string # `PATH` with every known binary directory guaranteed present
---@field build fun(opts?: Lib.Cross.Run.Env.Opts): table<string,string> # Completed environment table for a spawn call
---@field array fun(vars?: table<string,string>): string[] # Completed environment as `"KEY=VALUE"` strings, for raw `uv.spawn`'s array-shaped `env`
---@field apply fun(spawn_opts?: table, opts?: Lib.Cross.Run.Env.Opts): table # Copy of `spawn_opts` with `env` filled in by `build`
---@field clear fun(): nil # Drop the cached directory scan and login-shell probe

return {}
