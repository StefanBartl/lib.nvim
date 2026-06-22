---@meta
---@module 'lib.nvim.lua_ls.@types'

---@class Lib.LuaLS
---@field get_module_path fun(filepath: string): string|nil # Convert a filesystem path to a Lua module path. Returns nil if the file is not inside a /lua/ directory.
---@field insert_module_annotation fun(opts?: Lib.LuaLS.InsertModuleOpts): boolean # Insert a `---@module '...'` annotation into the current buffer or a specified buffer/position.

---@class Lib.LuaLS.GetModulePath
---@field __call fun(filepath: string): string|nil
--- Convert a filesystem path to a Lua module path.
--- Returns nil if the file is not inside a /lua/ directory.

---@class Lib.LuaLS.InsertModuleAnnotation
---@field __call fun(opts?: Lib.LuaLS.InsertModuleOpts): boolean
--- Insert a `---@module '...'` annotation into the current buffer or a specified buffer/position.

---@class Lib.LuaLS.InsertModuleOpts
---@field bufnr? integer Buffer handle; defaults to current buffer.
---@field row? integer 0-based row index; defaults to current cursor row.
---@field col? integer 0-based column index; defaults to current cursor column.

return {}
