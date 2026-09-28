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
    -- Short text still gets a sane, not needlessly wide, float.
    local surf = kit_style.start(
      { title = "[p] ", text = "", current = nil, total = nil },
      {},
      function() end
    )
    H.ok(surf ~= nil, "kit style: start() opens a surface for the bare fallback text")
    H.ok(
      vim.api.nvim_win_get_width(surf.winid) <= 30,
      "kit style: a short render doesn't get an oversized float"
    )
    surf:close()
  end
end
