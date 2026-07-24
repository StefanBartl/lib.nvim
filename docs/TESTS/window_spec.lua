-- docs/TESTS/window_spec.lua — lib.nvim.window: tag.lua and open_scratch_split.lua.

return function(H)
  local window = require("lib.nvim.window")

  -- tag: set / get / find ------------------------------------------------------
  do
    vim.cmd("new")
    local win = vim.api.nvim_get_current_win()

    H.eq(window.tag.get(win), nil, "tag.get: untagged window returns nil")

    window.tag.set(win, "lib.nvim.window_spec.tag")
    H.eq(window.tag.get(win), "lib.nvim.window_spec.tag", "tag.get: reads back the tag just set")

    local found = window.tag.find("lib.nvim.window_spec.tag")
    H.eq(found, win, "tag.find: locates the tagged window")

    H.eq(
      window.tag.find("lib.nvim.window_spec.does-not-exist"),
      nil,
      "tag.find: nil for unknown tag"
    )

    vim.api.nvim_win_close(win, true)
    H.eq(window.tag.get(win), nil, "tag.get: invalid window id returns nil")
  end

  -- open_scratch_split -----------------------------------------------------
  do
    local bufnr, winid = window.open_scratch_split(
      { "hello", "world" },
      { filetype = "window-spec" }
    )

    H.ok(vim.api.nvim_buf_is_valid(bufnr), "open_scratch_split: returns a valid bufnr")
    H.ok(vim.api.nvim_win_is_valid(winid), "open_scratch_split: returns a valid winid")
    H.eq(
      vim.api.nvim_win_get_buf(winid),
      bufnr,
      "open_scratch_split: window shows the returned buffer"
    )
    H.eq(vim.bo[bufnr].buftype, "nofile", "open_scratch_split: buftype is nofile")
    H.eq(vim.bo[bufnr].filetype, "window-spec", "open_scratch_split: filetype applied")
    H.eq(vim.bo[bufnr].modifiable, false, "open_scratch_split: locked read-only by default")
    H.eq(
      table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"),
      "hello\nworld",
      "open_scratch_split: content set"
    )

    local bufnr2, winid2 = window.open_scratch_split({ "second" })
    H.ok(bufnr2 ~= bufnr, "open_scratch_split: a second call opens its own buffer (no de-dup)")
    H.ok(winid2 ~= winid, "open_scratch_split: a second call opens its own window")

    pcall(vim.api.nvim_win_close, winid, true)
    pcall(vim.api.nvim_win_close, winid2, true)
  end
end
