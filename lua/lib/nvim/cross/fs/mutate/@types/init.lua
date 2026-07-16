---@meta
---@module 'lib.nvim.cross.fs.mutate.@types'

---@class Lib.Cross.Fs.Mutate
---@field delete_file fun(path: string): boolean, string|nil
---@field copy_file fun(src: string, dst: string): boolean, string|nil
---@field rename_file fun(src: string, dst: string): boolean, string|nil
---@field mkdir_p fun(path: string): boolean, string|nil
