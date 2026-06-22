---@meta
---@module 'lib.nvim.fs.polymorphic_rootresolver.@types'

---@class RootResolverCfg
---@field markers string[] List of filenames/folders that indicate project root.
---@field include_stdpath_config boolean If true, uses Neovim's stdpath("config") as fallback.
