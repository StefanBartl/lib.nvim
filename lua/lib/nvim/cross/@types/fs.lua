---@meta
---@module 'lib.nvim.cross.@types.fs'

---@class Lib.Cross.Fs
---@field cwd fun(): string
---@field expand_path fun(path: string): string # Expand ~, $VAR/${VAR} and %VAR% references in a path string.
---@field mutate Lib.Cross.Fs.Mutate # Injection-safe file mutation primitives (delete_file/copy_file/rename_file/mkdir_p).

---@class Lib.Cross.Separators
---@field has_win_sep fun(s: string): boolean
---@field normalize fun(path: string): string|nil
---@field unify_slashes fun(path: string): string
---@field collapse_dots fun(path: string): string # Lexically collapse './..' + repeated separators (pure; forward-slash form; keeps POSIX root & 'C:' drive prefix)
---@field drive_upper fun(path: string): string # Uppercase a bare Windows drive prefix ("c:/foo" -> "C:/foo"); no-op elsewhere

return {}
