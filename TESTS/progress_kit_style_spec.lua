-- TESTS/progress_kit_style_spec.lua — lib.nvim.progress.styles.kit: the
-- floating-window renderer sizes itself to what it actually renders, so the
-- (n/total) counter it exists to show is never silently clipped by a fixed
-- width the line has already outgrown by the time start() runs.

return function(H)
  local kit_style = require("lib.nvim.progress.styles.kit")

  do
    -- A caller that seeds text/current/total before start() runs (gitsuite's
    -- dashboard scan calls update() synchronously, ahead of the style's own
    -- 150ms start delay) can already produce a line well past a fixed 40
    -- cells by the time the float opens.
    local spec = {
      title = "[gitsuite] ",
      text = "reading git state of 67 repositories",
      current = 0,
      total = 67,
    }
    local surf = kit_style.start(spec, {}, function() end)
    H.ok(surf ~= nil, "kit style: start() opens a surface")

    local expected_line = spec.title .. spec.text .. (" (%d/%d)"):format(spec.current, spec.total)
    H.ok(
      vim.api.nvim_win_get_width(surf.winid) >= vim.fn.strdisplaywidth(expected_line),
      "kit style: the float is wide enough to show its own first render without clipping the counter"
    )
    surf:close()
  end

  do
    -- Short text still gets a sane, not needlessly wide, float: "[p] " ..
    -- "working…" (the bare fallback, no suffix) is 12 display cells (the
    -- ellipsis is one column), so the floor of 20 -- not the content --
    -- deterministically governs this case.
    local surf = kit_style.start(
      { title = "[p] ", text = "", current = nil, total = nil },
      {},
      function() end
    )
    H.ok(surf ~= nil, "kit style: start() opens a surface for the bare fallback text")
    H.eq(
      vim.api.nvim_win_get_width(surf.winid),
      20,
      "kit style: the floor width (20) applies to a short/bare render, not something inflated"
    )
    surf:close()
  end

  do
    -- Regression: `col` must be computed from the SAME width `make_scratch`
    -- actually opens the window with. A rendered line wider than the
    -- editor's own ceiling (`vim.o.columns - 4`) used to compute `col` from
    -- the unclamped (larger) width, opening the float flush against the left
    -- edge instead of staying anchored near the right.
    local orig_columns = vim.o.columns
    vim.o.columns = 80

    local spec = {
      title = "[gitsuite] ",
      text = "scanning a very long list of repositories across the whole workspace for pending changes",
      current = 0,
      total = 128,
    }
    local surf = kit_style.start(spec, {}, function() end)
    H.ok(surf ~= nil, "kit style: start() opens a surface for a line wider than the editor")

    local max_w = math.max(1, vim.o.columns - 4)
    local actual_width = vim.api.nvim_win_get_width(surf.winid)
    H.eq(
      actual_width,
      max_w,
      "kit style: a render wider than the editor clamps to the editor's own ceiling"
    )

    local cfg = vim.api.nvim_win_get_config(surf.winid)
    H.eq(
      cfg.col,
      math.max(0, vim.o.columns - actual_width - 2),
      "kit style: col is computed from the SAME (clamped) width the window actually opened with"
    )
    surf:close()

    vim.o.columns = orig_columns
  end

  do
    -- update() must grow the float in place when a later render outgrows
    -- the width it opened with -- gitsuite's dashboard scan seeds a short
    -- "working…" line at start() and only fills in the real (long) status
    -- once the scan reaches it, well after the float already opened.
    local orig_columns = vim.o.columns
    vim.o.columns = 200 -- ceiling (196) far above anything rendered here

    local spec = { title = "[p] ", text = "", current = nil, total = nil }
    local surf = kit_style.start(spec, {}, function() end)
    H.eq(
      vim.api.nvim_win_get_width(surf.winid),
      20,
      "kit style update(): starts at the floor width"
    )

    spec.text = "a moderately longer status line"
    kit_style.update(surf, spec, {})
    local expected_line = spec.title .. spec.text
    local want_width = math.max(20, vim.fn.strdisplaywidth(expected_line) + 2)
    local grown_width = vim.api.nvim_win_get_width(surf.winid)
    H.eq(
      grown_width,
      want_width,
      "kit style update(): grows to exactly fit the new render when under the ceiling"
    )
    H.eq(
      vim.api.nvim_win_get_config(surf.winid).col,
      math.max(0, vim.o.columns - grown_width - 2),
      "kit style update(): col is recomputed from the SAME width it just resized to"
    )

    -- One-way ratchet: a later render shrinking back down must NOT shrink
    -- the float -- only clipping is a bug, a few cells of unused padding on
    -- a shrinking counter is not, and shrinking-then-regrowing as
    -- current/total tick between 1 and 2 digits would be visible jitter.
    spec.text = ""
    kit_style.update(surf, spec, {})
    H.eq(
      vim.api.nvim_win_get_width(surf.winid),
      grown_width,
      "kit style update(): never shrinks back down once grown"
    )

    surf:close()
    vim.o.columns = orig_columns
  end

  do
    -- update() growing past the editor's own ceiling clamps there, same as
    -- start() (regression coverage for the growth path, not just start()'s).
    local orig_columns = vim.o.columns
    vim.o.columns = 80

    local spec = { title = "[p] ", text = "", current = nil, total = nil }
    local surf = kit_style.start(spec, {}, function() end)

    spec.text = "scanning a very long list of repositories across the whole workspace"
    spec.current, spec.total = 3, 128
    kit_style.update(surf, spec, {})

    local max_w = math.max(1, vim.o.columns - 4)
    H.eq(
      vim.api.nvim_win_get_width(surf.winid),
      max_w,
      "kit style update(): a grown render wider than the editor clamps to the editor's own ceiling"
    )

    surf:close()
    vim.o.columns = orig_columns
  end

  do
    -- cancel() must actually call maybe_resize too, not just share
    -- render_line/fit_width with update()/finish() while skipping the growth
    -- check itself.
    local orig_columns = vim.o.columns
    vim.o.columns = 200

    local spec = { title = "[p] ", text = "", current = nil, total = nil }
    local surf = kit_style.start(spec, {}, function() end)
    local before_width = vim.api.nvim_win_get_width(surf.winid)

    kit_style.cancel(surf, {
      title = "[a long-titled operation that outgrows the starting float] ",
      text = "cancelled",
    }, {})
    H.ok(
      vim.api.nvim_win_get_width(surf.winid) > before_width,
      "kit style cancel(): grows the float too when its own message outgrows it"
    )

    surf:close()
    vim.o.columns = orig_columns
  end
end
