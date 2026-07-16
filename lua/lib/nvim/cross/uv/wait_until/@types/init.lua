---@meta
---@module 'lib.nvim.cross.uv.wait_until.@types'

---@alias Lib.Cross.Uv.WaitUntil fun(predicate: fun(): boolean, opts: { interval_ms?: integer, max_attempts?: integer }|nil, cb: fun(ok: boolean)): nil
