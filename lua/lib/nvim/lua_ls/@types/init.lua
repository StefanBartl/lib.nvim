---@meta
---@module 'lib.nvim.lua_ls.@types'

--- CDX: phantom aggregate-module class — documents `require("lib.nvim.lua_ls")` as if
--- it returns a table with these fields, but there is no `lua_ls/init.lua`; the real
--- entry points are `lib.nvim.lua_ls.get_module_path` and
--- `lib.nvim.lua_ls.insert.module_annnotation`, each required by its own path.
---@class Lib.LuaLS
---@field get_module_path fun(filepath: string): string|nil # Convert a filesystem path to a Lua module path. Returns nil if the file is not inside a /lua/ directory.
---@field insert_module_annotation fun(opts?: Lib.LuaLS.InsertModuleOpts): boolean # Insert a `---@module '...'` annotation into the current buffer or a specified buffer/position.

---@class Lib.LuaLS.InsertModuleOpts
---@field bufnr? integer Buffer handle; defaults to current buffer.
---@field row? integer 0-based row index; defaults to current cursor row.
---@field col? integer 0-based column index; defaults to current cursor column.

return {}
