---@meta
---@module 'lib.nvim.fs.@types.transform'

---Options for `lib.nvim.fs.normkey`.
---@class Lib.Fs.NormkeyOpts
---@field realpath? boolean Resolve symlinks via `uv.fs_realpath`. Default true.

---Options for `lib.nvim.fs.path_shorten`.
---@class Lib.Fs.PathShortenOpts
---@field style? '"fit"'|'"label"' `"fit"` (default) fits a width budget; `"label"` always shows `<root>/<ellipsis>/<parent>/<file>`, ignoring `max_len`.
---@field ellipsis? string Marker for collapsed segments. Defaults to "…" for `"fit"`, "...." for `"label"`.

---@class Lib.Fs.Transform
---@field dedup fun(entries: string[]): string[]
---@field path_shorten fun(path: string, max_len: integer|nil, opts?: Lib.Fs.PathShortenOpts): string
---@field relpath fun(path: string, base: string): string
---@field normkey fun(p: string, opts?: Lib.Fs.NormkeyOpts): string
---@field project_key fun(path?: string): string

return {}


