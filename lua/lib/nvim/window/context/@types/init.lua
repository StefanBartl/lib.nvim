---@meta
---@module 'lib.nvim.window.context.@types'

--- Cached window metadata snapshot returned by `lib.nvim.window.context.get`.
---@class Lib.Window.Context.Ctx
---@field winid integer Window handle
---@field is_valid boolean Whether the window still exists
---@field bufnr integer Buffer displayed in the window (-1 if invalid)
---@field cursor integer[] `{row, col}`, 1-indexed row (as returned by `nvim_win_get_cursor`)
---@field topline integer First visible line (1-indexed)
---@field botline integer Last visible line (1-indexed)
---@field width integer Window width in columns
---@field height integer Window height in rows
---@field is_cursor_in_range fun(self: Lib.Window.Context.Ctx, start_line: integer, end_line: integer): boolean
---@field get_visible_lines fun(self: Lib.Window.Context.Ctx): integer

---@class Lib.Window.Context.Stats
---@field hits integer
---@field misses integer
---@field total_requests integer
---@field hit_rate number # Percentage 0-100

--- `lib.nvim.window.context` module surface.
---@class Lib.Window.Context
---@field get fun(winid?: integer): Lib.Window.Context.Ctx # Cached per-window; default is the current window.
---@field clear_cache fun(): nil # Drop every cached entry. Window context has no tick to key on, so callers own the invalidation moment (e.g. end of an event handler, or a CursorMoved/WinScrolled autocmd).
---@field invalidate fun(winid: integer): nil # Drop the cached entry for one window.
---@field get_stats fun(): Lib.Window.Context.Stats

return {}
