---@meta
---@module 'lib.nvim.cross.fs.mutate.@types'

---Retry behaviour for a single mutation. Defaults come from
---`require("lib.nvim.cross.fs.mutate").defaults`.
---@class Lib.Cross.Fs.Mutate.RetryOpts
---@field attempts? integer Maximum attempts including the first (default `3` on Windows, `1` elsewhere)
---@field backoff_ms? integer Base delay between attempts, doubled each round (default `50`)
---@field on_retry? fun(attempt: integer, err: string) Called before each retry, e.g. to release own handles on the path

---@class Lib.Cross.Fs.Mutate
---@field defaults Lib.Cross.Fs.Mutate.RetryOpts
---@field retry fun(op: fun(): boolean|nil, string|nil, opts?: Lib.Cross.Fs.Mutate.RetryOpts): boolean, string|nil
---@field delete_file fun(path: string, opts?: Lib.Cross.Fs.Mutate.RetryOpts): boolean, string|nil
---@field copy_file fun(src: string, dst: string, opts?: Lib.Cross.Fs.Mutate.RetryOpts): boolean, string|nil
---@field rename_file fun(src: string, dst: string, opts?: Lib.Cross.Fs.Mutate.RetryOpts): boolean, string|nil
---@field mkdir_p fun(path: string, opts?: Lib.Cross.Fs.Mutate.RetryOpts): boolean, string|nil
