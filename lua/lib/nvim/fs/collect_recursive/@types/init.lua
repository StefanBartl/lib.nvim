---@meta
---@module 'lib.nvim.fs.collect_recursive.@types'

---@alias Lib.Fs.CollectRecursive.Kind "all"|"files"|"dirs"

---@class Lib.Fs.CollectRecursive.Opts
---@field ignore (fun(abs_path: string, is_dir: boolean): boolean)|nil Return true to skip an entry; for directories this also prunes the whole subtree.
---@field kind Lib.Fs.CollectRecursive.Kind|nil Defaults to "all".

---@class Lib.Fs.CollectRecursive
---@field collect fun(root: string, opts?: Lib.Fs.CollectRecursive.Opts): string[]
---@field files fun(root: string, opts?: Lib.Fs.CollectRecursive.Opts): string[]
---@field dirs fun(root: string, opts?: Lib.Fs.CollectRecursive.Opts): string[]

return {}
