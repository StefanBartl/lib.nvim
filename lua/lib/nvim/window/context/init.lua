---@module 'lib.nvim.window.context'
--- Window-metadata accessor with a same-event cache.
---
--- Lighter than `lib.nvim.buffer.context`: there is no `changedtick` for a
--- window, so instead of validating the cache, callers own its lifetime.
--- Use it to avoid rebuilding the same window snapshot from several
--- unrelated handlers reacting to the same event; call `clear_cache()` once
--- that event has finished (or whenever staleness is undesirable — e.g. from
--- a `CursorMoved`/`WinScrolled` autocmd).
---
---   local ctx = require("lib.nvim.window.context")
---   local snap = ctx.get()                       -- current window, cached
---   if snap.is_valid and snap:is_cursor_in_range(1, 10) then
---     ...
---   end
---   ctx.clear_cache()                            -- caller decides when

require("lib.nvim.window.context.@types")

local api = vim.api

local M = {}

--- Lightweight cache; no tick validation, cleared by the caller.
local cache = {}

M.stats = {
  hits = 0,
  misses = 0,
}

---@return Lib.Window.Context.Ctx
local function invalid_ctx(winid)
  return {
    winid = winid,
    is_valid = false,
    bufnr = -1,
    cursor = { 0, 0 },
    topline = 0,
    botline = 0,
    width = 0,
    height = 0,
  }
end

--- Return a cached window snapshot.
---@param winid? integer # Window handle; defaults to the current window.
---@return Lib.Window.Context.Ctx
function M.get(winid)
  winid = winid or api.nvim_get_current_win()

  if not api.nvim_win_is_valid(winid) then
    return invalid_ctx(winid)
  end

  local cached = cache[winid]
  if cached then
    M.stats.hits = M.stats.hits + 1
    return cached
  end

  M.stats.misses = M.stats.misses + 1

  local bufnr = api.nvim_win_get_buf(winid)
  local cursor = api.nvim_win_get_cursor(winid)
  local width = api.nvim_win_get_width(winid)
  local height = api.nvim_win_get_height(winid)

  local view = vim.fn.winsaveview()
  local topline = view.topline or 1
  local botline = topline + height - 1

  ---@type Lib.Window.Context.Ctx
  local ctx = {
    winid = winid,
    is_valid = true,
    bufnr = bufnr,
    cursor = cursor,
    topline = topline,
    botline = botline,
    width = width,
    height = height,
  }

  function ctx:is_cursor_in_range(start_line, end_line)
    local row = self.cursor[1]
    return row >= start_line and row <= end_line
  end

  function ctx:get_visible_lines()
    return self.botline - self.topline + 1
  end

  cache[winid] = ctx
  return ctx
end

--- Drop every cached snapshot. Call this once the caller's current event has
--- finished processing (window state such as cursor/viewport is only valid
--- for the duration of that event).
function M.clear_cache()
  cache = {}
end

--- Drop the cached snapshot for one window.
---@param winid integer
function M.invalidate(winid)
  cache[winid] = nil
end

---@return Lib.Window.Context.Stats
function M.get_stats()
  local total = M.stats.hits + M.stats.misses
  return {
    hits = M.stats.hits,
    misses = M.stats.misses,
    total_requests = total,
    hit_rate = total > 0 and (M.stats.hits / total * 100) or 0,
  }
end

---@type Lib.Window.Context
return M
