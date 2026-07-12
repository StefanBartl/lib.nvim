-- docs/TESTS/ui_kit_spec.lua — lib.nvim.ui.kit
-- Phase 1 (theme, surface, note) + Phase 2 (toast, input, select/prompt).

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

  -- --------------------------------------------------------------- toast
  local toast_mod = require("lib.nvim.ui.kit.toast")
  toast_mod.clear()
  local t1 = assert(kit.toast({ message = "first", timeout = 0 }), "toast opens")
  ok(t1:is_valid(), "toast float valid")
  eq(toast_mod.active(), 1, "one toast active")
  local t2 = assert(kit.toast({ message = "second", timeout = 0 }), "second toast opens")
  eq(toast_mod.active(), 2, "two toasts stack")
  -- stacked below the first (higher row)
  local r1 = vim.api.nvim_win_get_config(t1.winid).row
  local r2 = vim.api.nvim_win_get_config(t2.winid).row
  ok(tonumber(tostring(r2)) > tonumber(tostring(r1)), "second toast sits below the first")
  toast_mod.clear()
  eq(toast_mod.active(), 0, "clear removes all toasts")

  -- --------------------------------------------------------------- input
  local inp = assert(kit.input({ prompt = "Name", default = "sb" }), "input opens")
  ok(inp:is_valid(), "input float valid")
  eq(vim.api.nvim_buf_get_lines(inp.bufnr, 0, 1, false)[1], "sb", "input seeded with default")
  vim.cmd("stopinsert")
  inp:close()

  -- --------------------------------------------------------------- prompt (confirm)
  kit.prompt({ question = "OK?", answer_type = "confirm" })
  local hs = require("lib.nvim.ui.hover_select")
  ok(hs.is_open(), "confirm prompt opened a chooser")
  hs.close()

  -- popup dispatch: still-unimplemented types return nil without throwing
  eq(kit.popup({ type = "menu" }), nil, "planned type returns nil (no throw)")
end
