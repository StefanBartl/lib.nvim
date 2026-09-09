-- TESTS/window_spec.lua — lib.nvim.window: tag.lua and open_scratch_split.lua.

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

  -- ---------- set_title ----------

  do
    local set_title = require("lib.nvim.window.set_title")
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 12,
      height = 2,
      style = "minimal",
      border = "rounded",
      title = "Parent",
    })
    local function frame_title()
      local cfg = vim.api.nvim_win_get_config(win)
      return cfg.title and cfg.title[1] and cfg.title[1][1] or nil
    end
    H.eq(frame_title(), "Parent", "set_title: fixture starts titled")

    H.ok(set_title(win, "Child"), "set_title: applies a new title")
    H.eq(frame_title(), "Child", "set_title: the new title is on the frame")

    -- The documented "pass nil to clear" contract. It used to be written as
    -- `{ title = nil }`, which in Lua is the *omitted* key -- and an omitted
    -- key leaves nvim_win_set_config's existing value alone, so clearing
    -- silently did nothing. Only an empty string removes it.
    H.ok(set_title(win, nil), "set_title: clearing reports success")
    H.eq(frame_title(), nil, "set_title: nil actually removes the title")

    pcall(vim.api.nvim_win_close, win, true)
  end

  -- ---------- make_scratch: anchor flip near a screen edge ----------
  --
  -- relative="cursor"/"mouse" floats used to always anchor NW (extend
  -- downward) with no check for whether that fits -- a click low on screen
  -- plus a tall enough float (a long context menu, say) opened anyway,
  -- extending past the bottom edge with nothing to show there. Should flip
  -- to anchor SW (extend upward) instead whenever it doesn't fit below.

  do
    local make_scratch = require("lib.nvim.window.make_scratch")
    local orig_screenrow = vim.fn.screenrow
    local orig_getmousepos = vim.fn.getmousepos
    local orig_lines = vim.o.lines

    vim.o.lines = 40

    -- Cursor near the bottom (row 38 of 40), a float 10 rows tall: 38+1+10
    -- would overshoot -- must flip.
    vim.fn.screenrow = function()
      return 38
    end
    local winid = make_scratch({ lines = { "x" }, height = 10, relative = "cursor" })
    H.ok(winid ~= nil, "make_scratch: cursor-relative float near the bottom opens")
    local cfg = vim.api.nvim_win_get_config(winid)
    H.eq(cfg.anchor, "SW", "make_scratch: flips to SW when it doesn't fit below the cursor")
    H.eq(cfg.row, 0, "make_scratch: SW row is 0 (bottom edge right at the anchor point)")
    pcall(vim.api.nvim_win_close, winid, true)

    -- Cursor near the top: the same float fits below it -- no flip.
    vim.fn.screenrow = function()
      return 2
    end
    local winid2 = make_scratch({ lines = { "x" }, height = 10, relative = "cursor" })
    local cfg2 = vim.api.nvim_win_get_config(winid2)
    H.eq(cfg2.anchor, "NW", "make_scratch: stays NW when it fits below the cursor")
    H.eq(cfg2.row, 1, "make_scratch: NW keeps the default 1-row downward offset")
    pcall(vim.api.nvim_win_close, winid2, true)

    -- Same check for relative="mouse", via getmousepos() instead of screenrow().
    vim.fn.getmousepos = function()
      return { screenrow = 39, screencol = 10 }
    end
    local winid3 = make_scratch({ lines = { "x" }, height = 10, relative = "mouse" })
    local cfg3 = vim.api.nvim_win_get_config(winid3)
    H.eq(cfg3.anchor, "SW", "make_scratch: mouse-relative also flips near the bottom")
    pcall(vim.api.nvim_win_close, winid3, true)

    -- relative="editor" is untouched: still centers, anchor stays the
    -- (explicit-but-equivalent) default NW.
    local winid4 = make_scratch({ lines = { "x" }, height = 5, width = 10, relative = "editor" })
    local cfg4 = vim.api.nvim_win_get_config(winid4)
    H.eq(cfg4.anchor, "NW", "make_scratch: editor-relative float keeps the default NW anchor")
    pcall(vim.api.nvim_win_close, winid4, true)

    vim.fn.screenrow = orig_screenrow
    vim.fn.getmousepos = orig_getmousepos
    vim.o.lines = orig_lines
  end

  -- ---------- make_scratch: scrolloff/sidescrolloff pinned to 0 ----------
  --
  -- Both are window-local but fall back to the global value when unset, so
  -- a scratch float otherwise inherits whatever a user's own config sets
  -- (up to the "keep the cursor centered" 999) instead of behaving like the
  -- self-contained overlay it is meant to be. Confirms the window-local
  -- value itself, regardless of what the global one is set to.

  do
    local make_scratch = require("lib.nvim.window.make_scratch")
    local saved_so, saved_siso = vim.o.scrolloff, vim.o.sidescrolloff
    vim.o.scrolloff = 10
    vim.o.sidescrolloff = 10

    local winid = make_scratch({ lines = { "one line" }, height = 3, relative = "editor" })
    assert(winid, "make_scratch: fixture window failed to open")

    H.eq(vim.wo[winid].scrolloff, 0, "make_scratch: scrolloff pinned to 0 regardless of the global")
    H.eq(
      vim.wo[winid].sidescrolloff,
      0,
      "make_scratch: sidescrolloff pinned to 0 regardless of the global"
    )

    pcall(vim.api.nvim_win_close, winid, true)
    vim.o.scrolloff = saved_so
    vim.o.sidescrolloff = saved_siso
  end
end
