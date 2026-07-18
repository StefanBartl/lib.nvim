---@meta
---@module 'lib.nvim.cross.uv.spawn_stream.@types'

---@class Lib.Cross.Uv.SpawnStream.Opts
---@field timeout_ms? integer Kill the process after this many ms and settle with `timed_out = true`.
---@field cwd? string Working directory for the child process.
---@field env? string[] Array of "KEY=VALUE" strings (libuv's own env shape), not a `{[key]=value}` dict.
---@field on_stderr_line? fun(line: string) Per-line stderr callback. Omit to discard stderr.
---@field kill_signal? string Signal used by the returned kill function. Default "sigterm".

---@class Lib.Cross.Uv.SpawnStream.Result
---@field ok boolean True when the process exited with code 0 and did not time out.
---@field code integer Exit code, -1 when the process was killed or could not be spawned.
---@field signal integer Terminating signal, 0 when none.
---@field timed_out boolean True when `opts.timeout_ms` elapsed and the process was killed.
---@field spawn_error? string Set only when the spawn itself failed (binary not found, …).

---Async spawn of an argv command with line-by-line stdout/stderr streaming.
---Returns a kill function, or nil when the spawn failed outright.
---@alias Lib.Cross.Uv.SpawnStream fun(argv: string[], opts: Lib.Cross.Uv.SpawnStream.Opts|nil, on_line: fun(line: string), on_exit: (fun(result: Lib.Cross.Uv.SpawnStream.Result))|nil): (fun())|nil
