-- docs/TESTS/context_spec.lua — lib.nvim.buffer.context, lib.nvim.window.context

return function(H)
  local eq, ok = H.eq, H.ok

  -- --------------------------------------------------------- buffer.context
  local buffer_ctx = require("lib.nvim.buffer.context")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
  vim.bo[bufnr].filetype = "lua"

  buffer_ctx.clear_all()
  local misses_before = buffer_ctx.get_stats().misses

  local snap = buffer_ctx.get(bufnr)
  eq(snap.is_valid, true, "buffer.context: valid buffer")
  eq(snap.bufnr, bufnr, "buffer.context: bufnr echoed back")
  eq(snap.filetype, "lua", "buffer.context: filetype captured")
  eq(snap.buftype, "nofile", "buffer.context: buftype captured")
  eq(snap.line_count, 3, "buffer.context: line_count")
  eq(buffer_ctx.get_stats().misses, misses_before + 1, "buffer.context: first get is a miss")

  local hits_before = buffer_ctx.get_stats().hits
  local snap2 = buffer_ctx.get(bufnr)
  eq(snap2, snap, "buffer.context: unchanged tick returns the cached table")
  eq(buffer_ctx.get_stats().hits, hits_before + 1, "buffer.context: repeat get is a hit")

  eq(snap:has_filetype("lua"), true, "buffer.context: has_filetype (string)")
  eq(snap:has_filetype({ "python", "lua" }), true, "buffer.context: has_filetype (list)")
  eq(snap:has_filetype("python"), false, "buffer.context: has_filetype negative")
  eq(snap:is_normal(), false, "buffer.context: scratch buffer is not 'normal' (buftype=nofile)")
  eq(snap:is_processable({ "nofile" }), false, "buffer.context: is_processable respects ignore_buftypes")
  eq(snap:is_processable({ "help" }), true, "buffer.context: is_processable allows non-ignored buftype")

  eq(snap.lines[1], "one", "buffer.context: lazy .lines loads content")
  eq(#snap.lines, 3, "buffer.context: lazy .lines has all lines")

  -- Editing the buffer bumps changedtick -> next get() is a miss again.
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "four" })
  local misses_before2 = buffer_ctx.get_stats().misses
  local snap3 = buffer_ctx.get(bufnr)
  ok(snap3 ~= snap, "buffer.context: edited buffer rebuilds the snapshot")
  eq(snap3.line_count, 4, "buffer.context: rebuilt snapshot reflects the edit")
  eq(buffer_ctx.get_stats().misses, misses_before2 + 1, "buffer.context: edit invalidates the cache")

  buffer_ctx.invalidate(bufnr)
  local misses_before3 = buffer_ctx.get_stats().misses
  buffer_ctx.get(bufnr)
  eq(buffer_ctx.get_stats().misses, misses_before3 + 1, "buffer.context: invalidate forces a rebuild")

  local invalid_snap = buffer_ctx.get(999999)
  eq(invalid_snap.is_valid, false, "buffer.context: invalid bufnr -> is_valid = false")

  buffer_ctx.print_stats() -- smoke: must not error

  vim.api.nvim_buf_delete(bufnr, { force = true })

  -- --------------------------------------------------------- window.context
  local window_ctx = require("lib.nvim.window.context")

  window_ctx.clear_cache()
  local winid = vim.api.nvim_get_current_win()

  local wsnap = window_ctx.get(winid)
  eq(wsnap.is_valid, true, "window.context: valid window")
  eq(wsnap.winid, winid, "window.context: winid echoed back")
  ok(wsnap.width > 0, "window.context: width is positive")
  ok(wsnap.height > 0, "window.context: height is positive")

  local wsnap2 = window_ctx.get(winid)
  eq(wsnap2, wsnap, "window.context: cache hit returns the same table before clear_cache()")

  window_ctx.clear_cache()
  local wsnap3 = window_ctx.get(winid)
  ok(wsnap3 ~= wsnap, "window.context: clear_cache() forces a rebuild")

  eq(wsnap3:is_cursor_in_range(1, 1000000), true, "window.context: is_cursor_in_range positive")
  eq(wsnap3:is_cursor_in_range(1000000, 2000000), false, "window.context: is_cursor_in_range negative")
  eq(
    wsnap3:get_visible_lines(),
    wsnap3.botline - wsnap3.topline + 1,
    "window.context: get_visible_lines matches topline/botline"
  )

  local invalid_wsnap = window_ctx.get(999999)
  eq(invalid_wsnap.is_valid, false, "window.context: invalid winid -> is_valid = false")

  local stats = window_ctx.get_stats()
  ok(stats.total_requests > 0, "window.context: get_stats reports requests")
end
