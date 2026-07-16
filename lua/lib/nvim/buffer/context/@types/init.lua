---@meta
---@module 'lib.nvim.buffer.context.@types'

--- Cached buffer metadata snapshot returned by `lib.nvim.buffer.context.get`.
--- Bound methods close over the snapshot itself (dot syntax, no `self` needed
--- at call sites, but `self` is still available since they are real methods).
---@class Lib.Buffer.Context.Ctx
---@field bufnr integer Buffer handle
---@field is_valid boolean Whether the buffer still exists
---@field name string Full buffer path (empty if unnamed or invalid)
---@field filetype string Buffer filetype (empty if invalid)
---@field buftype string Buffer type; empty for a normal file buffer
---@field modifiable boolean Whether the buffer can be modified
---@field modified boolean Whether the buffer has unsaved changes
---@field tick integer Buffer changedtick this snapshot was built from (cache key)
---@field lines string[]|nil Buffer lines; loaded lazily on first access, then cached on the snapshot
---@field line_count integer Number of lines in the buffer
---@field size_bytes integer Approximate size in bytes; refined once `lines` is accessed
---@field is_normal fun(self: Lib.Buffer.Context.Ctx): boolean # `buftype == "" and modifiable`
---@field has_filetype fun(self: Lib.Buffer.Context.Ctx, ft: string|string[]): boolean
---@field is_processable fun(self: Lib.Buffer.Context.Ctx, ignore_buftypes?: string[], ignore_filetypes?: string[]): boolean

---@class Lib.Buffer.Context.Stats
---@field hits integer
---@field misses integer
---@field invalidations integer
---@field total_requests integer
---@field hit_rate number # Percentage 0-100

--- `lib.nvim.buffer.context` module surface.
---@class Lib.Buffer.Context
---@field get fun(bufnr?: integer): Lib.Buffer.Context.Ctx # Cached by changedtick; default is the current buffer.
---@field invalidate fun(bufnr: integer): nil # Drop the cached entry for one buffer.
---@field clear_all fun(): nil # Drop every cached entry.
---@field get_stats fun(): Lib.Buffer.Context.Stats
---@field print_stats fun(): nil # `print()` a formatted stats table; debugging aid.

return {}
