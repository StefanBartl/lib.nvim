-- TESTS/output_viewer_spec.lua — lib.nvim.output.viewer: a thin, dump-friendly
-- wrapper around lib.nvim.ui.kit.viewer (stub, analogous to notify_popup_spec.lua).

return function(H)
  local eq = H.eq
  local output_viewer = require("lib.nvim.output.viewer")

  local function with_stub_viewer(fn)
    local seen
    local saved = package.loaded["lib.nvim.ui.kit.viewer"]
    package.loaded["lib.nvim.ui.kit.viewer"] = {
      open = function(opts)
        seen = opts
        return { winid = 1, bufnr = 1 }
      end,
    }
    local ok, result = pcall(fn)
    package.loaded["lib.nvim.ui.kit.viewer"] = saved
    if not ok then
      error(result, 0)
    end
    return seen, result
  end

  local seen = with_stub_viewer(function()
    output_viewer.show_lines("results", { "line 1", "line 2" })
  end)
  eq(seen.title, "results", "show_lines forwards the title")
  eq(#seen.lines, 2, "show_lines forwards the lines")
  eq(seen.lines[1], "line 1", "lines are forwarded verbatim")

  -- Extra opts (width, height, close_on_focus_lost, ...) are merged through,
  -- and cannot override title/lines.
  seen = with_stub_viewer(function()
    output_viewer.show_lines("t", { "x" }, { width = 42, title = "hijacked" })
  end)
  eq(seen.width, 42, "opts are passed through to ui.kit.viewer.open")
  eq(seen.title, "t", "the title argument wins over an opts.title collision")

  -- The surface returned by ui.kit.viewer.open is returned as-is.
  local _, surf = with_stub_viewer(function()
    return output_viewer.show_lines("t", { "x" })
  end)
  eq(surf.winid, 1, "show_lines returns the surface from ui.kit.viewer.open")
end
