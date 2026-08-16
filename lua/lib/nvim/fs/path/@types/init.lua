---@meta
---@module 'lib.nvim.fs.path.@types'

---OOP `Path` instance returned by `require("lib.nvim.fs.path.object").new(path)`.
---@class Lib.Fs.Path.Object
---@field path string
---@field init fun(self: Lib.Fs.Path.Object, path: string)
---@field exists fun(self: Lib.Fs.Path.Object): boolean
---@field is_dir fun(self: Lib.Fs.Path.Object): boolean
---@field read fun(self: Lib.Fs.Path.Object): string|nil, string|nil
---@field write fun(self: Lib.Fs.Path.Object, content: string): boolean, string|nil
---@field joinpath fun(self: Lib.Fs.Path.Object, ...: string): Lib.Fs.Path.Object
---@field parent fun(self: Lib.Fs.Path.Object): Lib.Fs.Path.Object
---@field iter fun(self: Lib.Fs.Path.Object, opts?: Lib.Fs.CollectRecursive.Opts): string[]

--- `require("lib.nvim.fs.path.object")` itself: the `Path` class table.
---@class Lib.Fs.Path.ObjectModule
---@field new fun(path: string): Lib.Fs.Path.Object

return {}
