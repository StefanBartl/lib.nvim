-- docs/TESTS/ui_kit_spec.lua — lib.nvim.ui.kit Phase 1 (theme, surface, note).

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local theme = kit.theme

  -- --------------------------------------------------------------- theme
  -- preset by name
  local double = theme.resolve("double")
  eq(double.border, "double", "preset name resolves border")

  -- default when nil
  local def = theme.resolve(nil)
  eq(def.border, "rounded", "nil resolves to default preset (rounded)")

  -- ascii preset flag
  eq(theme.resolve("ascii").ascii_border, true, "ascii preset sets ascii_border")

  -- partial override merges over the active default
  local custom = theme.resolve({ hl = { accent = "WarningMsg" } })
  eq(custom.border, "rounded", "override keeps default preset's border")
  eq(custom.hl.accent, "WarningMsg", "override replaces one hl key")
  eq(custom.hl.normal, "NormalFloat", "override leaves other hl keys intact")

  -- unknown preset name falls back to default
  eq(theme.resolve("does-not-exist").border, "rounded", "unknown preset -> default")

  -- setup registers a user preset and can switch the default
  kit.setup({ presets = { spec_preset = { border = "single" } } })
  eq(theme.resolve("spec_preset").border, "single", "user preset registered")
  ok(vim.tbl_contains(theme.presets(), "spec_preset"), "preset listed")

  -- --------------------------------------------------------------- surface
  local s = assert(
    kit.surface.open({ lines = { "hello", "world" }, theme = "double", title = "T" }),
    "surface.open returns a handle"
  )
  ok(s:is_valid(), "surface window is valid")
  eq(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false)[1], "hello", "surface content set")

  -- winhighlight wired to the Kit* groups
  local winhl = vim.api.nvim_get_option_value("winhighlight", { win = s.winid })
  ok(winhl:find("NormalFloat:KitNormal", 1, true), "winhighlight maps NormalFloat->KitNormal")

  -- Kit* highlight groups were materialized
  ok(vim.fn.hlexists("KitNormal") == 1, "KitNormal highlight group defined")
  ok(vim.fn.hlexists("KitBorder") == 1, "KitBorder highlight group defined")

  -- set_lines respects the modifiable lock
  s:set_lines({ "changed" })
  eq(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false)[1], "changed", "set_lines updates content")

  -- on_close fires exactly once
  local closes = 0
  s:on_close(function()
    closes = closes + 1
  end)
  s:close()
  ok(not s:is_valid(), "surface closed")
  eq(closes, 1, "on_close fired once")
  s:close() -- idempotent
  eq(closes, 1, "on_close not fired again on second close")

  -- --------------------------------------------------------------- note
  local n = assert(kit.note({ title = "Saved", message = "wrote 3 files" }), "note opens")
  ok(n:is_valid(), "note float is valid")
  eq(vim.api.nvim_buf_get_lines(n.bufnr, 0, -1, false)[1], "wrote 3 files", "note shows message")
  n:close()

  -- note accepts a multiline (array) message
  local n2 = assert(kit.note({ message = { "a", "b", "c" } }), "note (array) opens")
  eq(#vim.api.nvim_buf_get_lines(n2.bufnr, 0, -1, false), 3, "note renders array message lines")
  n2:close()

  -- popup dispatch: unimplemented types return nil without throwing
  eq(kit.popup({ type = "toast", message = "x" }), nil, "planned type returns nil (no throw)")
end
