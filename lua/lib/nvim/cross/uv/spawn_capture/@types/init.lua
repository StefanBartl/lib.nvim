---@meta
---@module 'lib.nvim.cross.uv.spawn_capture.@types'

---@class Lib.Cross.Uv.SpawnCapture.Opts
---@field timeout_ms? integer
---@field cwd? string
---@field env? string[] Array of "KEY=VALUE" strings (libuv's own env shape), not a `{[key]=value}` dict.
---@field stdin? string Written to the child, then the pipe is closed (for values that must not appear in argv).

---@class Lib.Cross.Uv.SpawnCapture.Result
---@field ok boolean
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string
---@field timed_out boolean

---@alias Lib.Cross.Uv.SpawnCapture fun(argv: string[], opts: Lib.Cross.Uv.SpawnCapture.Opts|nil, on_done: fun(result: Lib.Cross.Uv.SpawnCapture.Result)): nil
