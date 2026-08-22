---@meta
---@module 'lib.nvim.cross.@types.run'

---Options accepted by `run`/`run_blocking`, on top of the command itself.
---@class Lib.Cross.Run.RunOpts
---@field env? table<string,string>|false Explicit vars folded into the completed environment (highest priority), or `false` to skip enrichment entirely and let the subprocess inherit Neovim's raw environment (the pre-`cross.run.env` behaviour).
---@field env_opts? Lib.Cross.Run.Env.Opts Passed straight through to `cross.run.env.build()` — e.g. `{ login_shell = true, mason = true }`.

---@class Lib.Cross.Run
---@field shell fun(): OsShell
---@field run fun(cmd: string, cb: fun(ok:boolean, res:OsRunResult), opts?: Lib.Cross.Run.RunOpts): nil
---@field run_blocking fun(cmd: string, opts?: Lib.Cross.Run.RunOpts): OsRunResult
---@field run_detached fun(argv: string[]): boolean, string|nil # Launch argv detached (fire-and-forget); routes through jobstart on Windows/WSL since vim.system detach is unreliable there for GUI processes.
---@field run_argv { run_blocking: fun(cmd: string[], input?: string): boolean, string|nil, run_blocking_captured: fun(cmd: string[], input?: string): boolean, string, run_async_captured: fun(cmd: string[], on_done: fun(ok: boolean, output: string, code: integer), input?: string): { stop: fun() } }
---@field env Lib.Cross.Run.Env # Spawn-environment builder: completed PATH + recoverable session/keyring variables.

return {}
