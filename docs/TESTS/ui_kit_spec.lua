-- docs/TESTS/ui_kit_spec.lua — lib.nvim.ui.kit
-- Phase 1 (theme, surface, note), Phase 2 (toast, input, prompt),
-- Phase 3 (layout + picker, native chooser + hover_select shim, interactive picker),
-- Phase 4 (button-confirm).

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

  -- --------------------------------------------------------------- chooser (native select)
  local chooser = require("lib.nvim.ui.kit.chooser")

  -- single select: submit fires on_select(item, idx) and closes
  local picked_item, picked_idx
  kit.select({
    selection = { "alpha", "beta", "gamma" },
    on_select = function(it, i)
      picked_item, picked_idx = it, i
    end,
  })
  ok(chooser.is_open(), "chooser opened")
  chooser.move(1) -- alpha -> beta
  eq(chooser.current_index(), 2, "move advances selection")
  chooser.submit()
  eq(picked_item, "beta", "single-select returned the highlighted item")
  eq(picked_idx, 2, "single-select returned its index")
  ok(not chooser.is_open(), "chooser closed after submit")

  -- move wraps around
  kit.select({ selection = { "a", "b" }, on_select = function() end })
  chooser.move(-1) -- from line 1 wraps to line 2
  eq(chooser.current_index(), 2, "move(-1) wraps to the last row")
  chooser.close()

  -- multi-select: toggle marks then submit returns (items[], indices[])
  local multi_items, multi_idx
  kit.select({
    selection = { "one", "two", "three" },
    multi = true,
    on_select = function(items, idxs)
      multi_items, multi_idx = items, idxs
    end,
  })
  chooser.toggle() -- mark line 1
  chooser.move(2) -- to line 3
  chooser.toggle() -- mark line 3
  chooser.submit()
  eq(table.concat(multi_items, ","), "one,three", "multi-select returned marked items in order")
  eq(table.concat(multi_idx, ","), "1,3", "multi-select returned marked indices")

  -- theme selection highlight is wired
  ok(vim.fn.hlexists("KitSelection") == 1, "KitSelection group defined for the chooser")

  -- --------------------------------------------------------------- layout (pure)
  local geo = kit.layout.compute(kit.layout.templates.picker.spec)
  ok(geo.slots.prompt ~= nil, "picker layout has a prompt slot")
  ok(geo.slots.results ~= nil, "picker layout has a results slot")
  ok(geo.slots.preview ~= nil, "picker layout has a preview slot")

  -- prompt spans the full outer width; results+preview are narrower halves
  ok(geo.slots.prompt.width >= geo.slots.results.width, "prompt wider than results")
  ok(geo.slots.results.width < geo.slots.preview.width, "results (0.4) narrower than preview (0.6)")

  -- prompt sits above the results/preview row
  ok(geo.slots.prompt.row < geo.slots.results.row, "prompt above results")
  eq(geo.slots.results.row, geo.slots.preview.row, "results and preview share a row")

  -- gap = 0, border = 1 -> preview.col == results.col + results.width + 2
  eq(
    geo.slots.preview.col,
    geo.slots.results.col + geo.slots.results.width + 2,
    "results and preview align edge-to-edge (shared border, no gap)"
  )

  -- --------------------------------------------------------------- layout (mount)
  local group =
    assert(kit.layout.template("picker", { theme = "double" }), "picker template mounts")
  ok(group.slots.prompt:is_valid(), "prompt slot surface valid")
  ok(group.slots.results:is_valid(), "results slot surface valid")
  ok(group.slots.preview:is_valid(), "preview slot surface valid")
  -- closing the group closes every slot
  group.close()
  ok(not group.slots.results:is_valid(), "group.close() closed the results slot")
  ok(not group.slots.preview:is_valid(), "group.close() closed the preview slot")

  -- unknown template returns nil without throwing
  eq(kit.layout.template("nope"), nil, "unknown template returns nil")

  -- --------------------------------------------------------------- picker (interactive)
  local submit_idx, submit_text
  local p = assert(
    kit.picker({
      on_submit = function(i, t)
        submit_idx, submit_text = i, t
      end,
    }),
    "picker opens"
  )
  ok(p.slots.prompt:is_valid(), "picker prompt slot valid")
  ok(p.slots.results:is_valid(), "picker results slot valid")
  ok(p.slots.preview:is_valid(), "picker preview slot valid")

  -- caller fills the results slot (as on_change would), selection resets to top
  p.set_results({ "match-1", "match-2", "match-3" })
  p.move(1) -- to match-2
  p.submit()
  eq(submit_idx, 2, "picker submit reports the highlighted index")
  eq(submit_text, "match-2", "picker submit reports the highlighted line text")
  vim.cmd("stopinsert")

  -- plain mode falls back to a bare template mount
  local plain = assert(kit.picker({ prompt = "plain" }), "plain picker mounts")
  ok(plain.slots.prompt:is_valid(), "plain picker has slots")
  plain.close()
  vim.cmd("stopinsert")

  -- --------------------------------------------------------------- confirm (buttons)
  local confirm = require("lib.nvim.ui.kit.confirm")

  -- default Yes/No -> boolean; focus starts on Yes
  local yn
  local cs = assert(
    kit.confirm({
      question = "Delete 3 files?",
      on_answer = function(a)
        yn = a
      end,
    }),
    "confirm opens"
  )
  ok(cs:is_valid(), "confirm float valid")
  eq(confirm.current_focus(), 1, "focus starts on the first button")
  confirm.confirm() -- Yes
  eq(yn, true, "default confirm: Yes -> true")

  -- move to No, confirm -> false
  kit.confirm({
    question = "Sure?",
    on_answer = function(a)
      yn = a
    end,
  })
  confirm.move(1) -- Yes -> No
  eq(confirm.current_focus(), 2, "move advances focus")
  confirm.confirm()
  eq(yn, false, "default confirm: No -> false")

  -- move wraps around
  kit.confirm({ question = "Wrap?", on_answer = function() end })
  confirm.move(-1) -- from Yes wraps to No
  eq(confirm.current_focus(), 2, "move(-1) wraps to the last button")
  confirm.close()

  -- custom choices -> chosen string
  local choice
  kit.confirm({
    question = "Pick",
    choices = { "Keep", "Discard", "Cancel" },
    on_answer = function(c)
      choice = c
    end,
  })
  confirm.move(1) -- Keep -> Discard
  confirm.confirm()
  eq(choice, "Discard", "custom confirm returns the chosen label")

  -- cancel: default -> false, custom -> nil
  kit.confirm({
    question = "X",
    on_answer = function(a)
      yn = a
    end,
  })
  confirm.cancel()
  eq(yn, false, "cancel on default confirm -> false")

  local custom_cancel = "sentinel"
  kit.confirm({
    question = "Y",
    choices = { "A", "B" },
    on_answer = function(a)
      custom_cancel = a
    end,
  })
  confirm.cancel()
  eq(custom_cancel, nil, "cancel on custom confirm -> nil")

  -- routed via prompt(answer_type = "confirm", layout = "buttons")
  kit.prompt({
    question = "Route?",
    answer_type = "confirm",
    layout = "buttons",
    on_answer = function() end,
  })
  ok(confirm.is_open(), "prompt layout=buttons opens the button-confirm")
  confirm.close()

  -- focused button carries the selection highlight
  ok(vim.fn.hlexists("KitSelection") == 1, "KitSelection group defined for confirm focus")

  -- --------------------------------------------------------------- menu
  local ran
  local ms = assert(
    kit.menu({
      title = "Actions",
      items = {
        {
          label = "Rename",
          action = function()
            ran = "rename"
          end,
        },
        {
          label = "Delete",
          action = function()
            ran = "delete"
          end,
        },
      },
    }),
    "menu opens"
  )
  ok(ms:is_valid(), "menu float valid")
  eq(vim.api.nvim_buf_get_lines(ms.bufnr, 0, 1, false)[1], "Rename", "menu shows the item labels")
  -- pick the second item -> runs its action
  chooser.move(1)
  chooser.submit()
  eq(ran, "delete", "menu runs the picked item's action")

  -- --------------------------------------------------------------- progress (passthrough)
  local ph = kit.progress({ text = "working", style = "notify" })
  ok(
    type(ph) == "table" and type(ph.finish) == "function",
    "kit.progress returns a lib.nvim.progress handle"
  )
  ph:finish() -- stays silent (never became visible)

  -- popup dispatch: unknown types return nil without throwing
  eq(kit.popup({ type = "does-not-exist" }), nil, "unknown type returns nil (no throw)")
end
