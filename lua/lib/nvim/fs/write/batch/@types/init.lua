---@meta
---@module 'lib.nvim.fs.write.batch.@types'

---@class Lib.Fs.Write.Batch.Entry
---@field path string
---@field content string

---@class Lib.Fs.Write.Batch.Result
---@field path string
---@field ok boolean
---@field err string|nil

---Write many files asynchronously; `cb` fires once all have settled.
---`results` is index-aligned with `entries`.
---@alias Lib.Fs.Write.Batch fun(entries: Lib.Fs.Write.Batch.Entry[], cb: fun(all_ok: boolean, results: Lib.Fs.Write.Batch.Result[])): nil
