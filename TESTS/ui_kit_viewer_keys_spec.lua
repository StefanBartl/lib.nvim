-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_viewer_keys_spec.lua -- the winbar legend of a kit.viewer with `keys` (`viewer_keys`), the `kit.keys` export and the status tokens of the theme. The full spec of the viewer keys lives in ui.nvim, which runs it through `ui.kit`.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local viewer_keys = require("lib.nvim.ui.kit.viewer_keys")

  ok(kit.keys == viewer_keys, "kit.keys is the viewer_keys module")

  local bar = viewer_keys.legend({
    { lhs = "r", legend = "Refresh" },
    { lhs = "x", desc = "works, is not advertised" },
    { lhs = "<CR>", legend = "Open" },
  })
  ok(bar:find("r %%#Comment#Refresh"), "an entry with a legend is listed")
  ok(bar:find("<CR> %%#Comment#Open"), "in order")
  ok(not bar:find("x %%#Comment#"), "an entry without a legend is not advertised")
  ok(bar:find("%? %%#Comment#Keys%%#Normal#$"), "`? Keys` comes last")

  local escaped = viewer_keys.legend({ { lhs = "%", legend = "50%{&shell}" } })
  ok(escaped:find("%%#Special#%%%% %%#Comment#50%%%%{&shell}"), "% in a key or text is escaped")
  ok(not escaped:find("[^%%]%%{"), "so the winbar never evaluates it")

  local moved = viewer_keys.legend({ { lhs = "r", legend = "Refresh" } }, {
    help_lhs = "g?",
    help_label = "Tasten",
  })
  ok(moved:find("g%? %%#Comment#Tasten%%#Normal#$"), "a moved help key and its own text")

  local theme = require("lib.nvim.ui.kit.theme")
  eq(type(theme.resolve), "function", "theme resolves")
  local hl = theme.resolve().hl
  for _, token in ipairs({ "ok", "warn", "info", "dim" }) do
    ok(hl[token] ~= nil, "the theme has the status token " .. token)
  end
end
