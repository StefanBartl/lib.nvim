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
end
