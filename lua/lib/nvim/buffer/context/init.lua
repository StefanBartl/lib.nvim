---@module 'lib.nvim.buffer.context'
--- Buffer-metadata accessor cached by `changedtick`.
---
--- Building a buffer snapshot (name, filetype, line count, ...) touches
--- several `nvim_buf_*` calls; callers that ask for it repeatedly within the
--- same "version" of a buffer (e.g. once per keystroke from several
--- unrelated autocmd handlers) would otherwise redo that work every time.
--- `get()` keys its cache on the buffer's `changedtick`, so repeated calls
--- between edits are free.
---
---   local ctx = require("lib.nvim.buffer.context")
---   local snap = ctx.get()              -- current buffer, cached
---   if snap.is_valid and snap:is_normal() then
---     ...
---   end
---
--- The cache is weak-keyed (`bufnr -> snapshot`), so entries for deleted
--- buffers are collected automatically; `invalidate`/`clear_all` exist for
--- callers that want to force a rebuild sooner (e.g. after mutating a buffer
--- through a path that does not bump `changedtick`).

require("lib.nvim.buffer.context.@types")

local api, bo = vim.api, vim.bo

local M = {}

--- Weak-keyed cache (auto-cleanup on buffer deletion / GC).
local cache = setmetatable({}, { __mode = "k" })

M.stats = {
  hits = 0,
  misses = 0,
  invalidations = 0,
}

---@param ctx Lib.Buffer.Context.Ctx
---@param ignore_buftypes string[]|nil
---@param ignore_filetypes string[]|nil
---@return boolean
local function is_processable(ctx, ignore_buftypes, ignore_filetypes)
  if ignore_buftypes then
    for _, bt in ipairs(ignore_buftypes) do
      if ctx.buftype == bt then
        return false
      end
    end
  end

  if ignore_filetypes then
    for _, ft in ipairs(ignore_filetypes) do
      if ctx.filetype == ft then
        return false
      end
    end
  end

  return true
end

---@return Lib.Buffer.Context.Ctx
local function invalid_ctx(bufnr)
  return {
    bufnr = bufnr,
    is_valid = false,
    name = "",
    filetype = "",
    buftype = "",
    modifiable = false,
    modified = false,
    tick = 0,
    line_count = 0,
    size_bytes = 0,
  }
end

--- Return a cached, changedtick-validated buffer snapshot.
---@param bufnr? integer # Buffer handle; defaults to the current buffer.
---@return Lib.Buffer.Context.Ctx
function M.get(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if not api.nvim_buf_is_valid(bufnr) then
    return invalid_ctx(bufnr)
  end

  local tick = api.nvim_buf_get_changedtick(bufnr)

  local cached = cache[bufnr]
  if cached and cached.tick == tick then
    M.stats.hits = M.stats.hits + 1
    return cached
  end

  M.stats.misses = M.stats.misses + 1

  local name = api.nvim_buf_get_name(bufnr)
  local line_count = api.nvim_buf_line_count(bufnr)

  ---@type Lib.Buffer.Context.Ctx
  local ctx = {
    bufnr = bufnr,
    is_valid = true,
    name = name,
    filetype = bo[bufnr].filetype or "",
    buftype = bo[bufnr].buftype or "",
    modifiable = bo[bufnr].modifiable,
    modified = bo[bufnr].modified,
    tick = tick,
    line_count = line_count,
    -- Rough estimate (80 bytes/line) until `lines` is actually read.
    size_bytes = #name + (line_count * 80),
  }

  -- Lazy-load full buffer content only if a caller reads `.lines`.
  setmetatable(ctx, {
    __index = function(t, k)
      if k == "lines" then
        local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
        rawset(t, "lines", lines)

        local total_bytes = 0
        for _, line in ipairs(lines) do
          total_bytes = total_bytes + #line + 1 -- +1 for the newline
        end
        rawset(t, "size_bytes", total_bytes)

        return lines
      end
    end,
  })

  function ctx:is_normal()
    return self.buftype == "" and self.modifiable
  end

  function ctx:is_processable(ignore_buftypes, ignore_filetypes)
    return is_processable(self, ignore_buftypes, ignore_filetypes)
  end

  function ctx:has_filetype(ft)
    if type(ft) == "string" then
      return self.filetype == ft
    elseif type(ft) == "table" then
      for _, v in ipairs(ft) do
        if self.filetype == v then
          return true
        end
      end
    end
    return false
  end

  cache[bufnr] = ctx
  return ctx
end

--- Drop the cached snapshot for one buffer, forcing a rebuild on next `get`.
---@param bufnr integer
function M.invalidate(bufnr)
  if cache[bufnr] then
    M.stats.invalidations = M.stats.invalidations + 1
    cache[bufnr] = nil
  end
end

--- Drop every cached snapshot.
function M.clear_all()
  cache = setmetatable({}, { __mode = "k" })
  M.stats.invalidations = M.stats.invalidations + 1
end

--- Cache hit/miss/invalidation counters since the process started.
---@return Lib.Buffer.Context.Stats
function M.get_stats()
  local total = M.stats.hits + M.stats.misses
  return {
    hits = M.stats.hits,
    misses = M.stats.misses,
    invalidations = M.stats.invalidations,
    total_requests = total,
    hit_rate = total > 0 and (M.stats.hits / total * 100) or 0,
  }
end

--- `print()` a formatted stats table; debugging aid.
function M.print_stats()
  local stats = M.get_stats()
  print(string.format(
    [[
Buffer Context Cache Stats:
  Hits:          %d
  Misses:        %d
  Invalidations: %d
  Total:         %d
  Hit Rate:      %.2f%%
]],
    stats.hits,
    stats.misses,
    stats.invalidations,
    stats.total_requests,
    stats.hit_rate
  ))
end

---@type Lib.Buffer.Context
return M
