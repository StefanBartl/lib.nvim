---@meta
---@module 'lib.nvim.fs.@types.write'

--- CDX: no `lib.nvim.fs.write` aggregate module exists (write/ exposes
--- CDX: to_file, append, async, batch as separate requires); this class is
--- CDX: fictional scaffolding and only ever listed `to_file`. Original casing
--- CDX: was `Lib.FS.Write`, out of line with every other `Lib.Fs.*` class.
---@class Lib.Fs.Write
---@field to_file fun(path: string, content: string): boolean, string|nil # Write content to path, creating the parent directory. Returns a success boolean, plus a message on failure.

return {}
