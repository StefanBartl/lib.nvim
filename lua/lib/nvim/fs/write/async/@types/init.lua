---@meta
---@module 'lib.nvim.fs.write.async.@types'

---Asynchronously write `content` to `path`, creating parent directories.
---`cb` runs on the main loop via `vim.schedule`.
---@alias Lib.Fs.Write.Async fun(path: string, content: string, cb: fun(ok: boolean, err: string|nil)): nil
