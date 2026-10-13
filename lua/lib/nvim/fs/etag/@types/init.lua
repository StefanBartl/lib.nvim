---@meta
---@module 'lib.nvim.fs.etag.@types'

---@class Lib.Fs.Etag
---@field sha256 fun(text: string): string  The SHA-256 of some bytes, 64 hex digits (NUL-safe).
---@field of fun(text: string): string      The version tag: `sha256:` and the first 16 hex digits.

return {}
