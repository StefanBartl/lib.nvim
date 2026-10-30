-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_chip_scheme_retint_spec.lua -- `lib.nvim.ui.kit.chip`: a table `color` whose `fg` or `bg`
-- is filled in from the colorscheme is re-resolved on `ColorScheme`.
--
-- A `{ fg, bg }` table used to count as "not theme-linked" whatever it held, so the ColorScheme
-- handler skipped it. But a missing `bg`, or a transparent shape (`classic`), takes the window's
-- background, and a missing `fg` takes `Special`'s -- both read from the current scheme. After
-- `:colorscheme` such a chip kept the old scheme's background (or fg) until the next `refresh()`.
-- A complete table on an opaque shape is the one case that really stays fixed.

return function(H)
  local eq, ok = H.eq, H.ok
  local chip = require("lib.nvim.ui.kit.chip")
  local api = vim.api

  local saved = {}
  for _, name in ipairs({ "Normal", "NormalFloat", "Special" }) do
    saved[name] = api.nvim_get_hl(0, { name = name, link = false })
  end

  --- The chip's own highlight (`UiKitChip_<id>`; the ids here are alphanumeric, so unescaped).
  ---@param id string
  ---@return { fg?: integer, bg?: integer }
  local function chip_hl(id)
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative == "editor" then
        local winhl = api.nvim_get_option_value("winhighlight", { win = w })
        local group = winhl:match("NormalFloat:([%w_]+)")
        if group == "UiKitChip_" .. id then
          return api.nvim_get_hl(0, { name = group, link = false })
        end
      end
    end
    error("no chip window for " .. id)
  end

  local ids = { "retintnobg", "retintclassic", "retintnofg", "retintfull", "retintpulse" }

  --- A new "colorscheme": empty the chip groups the way its `:hi clear` does (a real `:hi clear`
  --- would reset every other spec's groups too), set the scheme groups, then fire ColorScheme like
  --- `:colorscheme` does.
  ---@param bg integer
  ---@param special integer
  local function scheme(bg, special)
    for _, id in ipairs(ids) do
      api.nvim_set_hl(0, "UiKitChip_" .. id, {})
    end
    api.nvim_set_hl(0, "Normal", { fg = 0xdddddd, bg = bg })
    api.nvim_set_hl(0, "NormalFloat", { bg = bg })
    api.nvim_set_hl(0, "Special", { fg = special })
    api.nvim_exec_autocmds("ColorScheme", {})
  end

  local done, err = pcall(function()
    scheme(0x111111, 0x00aa00)
    chip.mount({ id = "retintnobg", text = "a", color = { fg = "#ff0000" } })
    chip.mount({
      id = "retintclassic",
      text = "b",
      shape = "classic",
      color = { fg = "#ff0000", bg = "#0000ff" },
    })
    chip.mount({ id = "retintnofg", text = "c", color = { bg = "#0000ff" } })
    chip.mount({ id = "retintfull", text = "d", color = { fg = "#ff0000", bg = "#0000ff" } })
    chip.mount({ id = "retintpulse", text = "e", color = { fg = "#ff0000", bg = "#0000ff" } })
    chip.pulse("retintpulse", { color = { fg = 0x123456, bg = 0x654321 }, duration_ms = 10000 })

    eq(chip_hl("retintnobg").bg, 0x111111, "missing bg: the window background")
    eq(chip_hl("retintclassic").bg, 0x111111, "classic: the window background")
    eq(chip_hl("retintnofg").fg, 0x00aa00, "missing fg: Special's fg")

    scheme(0x222222, 0x00bb00)

    eq(chip_hl("retintnobg").bg, 0x222222, "missing bg follows the new scheme's background")
    eq(chip_hl("retintclassic").bg, 0x222222, "classic follows the new scheme's background")
    eq(chip_hl("retintnofg").fg, 0x00bb00, "missing fg follows the new scheme's Special")
    local full = chip_hl("retintfull")
    ok(
      full.fg == 0xff0000 and full.bg == 0x0000ff,
      "a complete table on an opaque shape stays fixed (painted again after `:hi clear`)"
    )
    -- `refresh()` does not repaint it either: its fg/bg still match what it resolves to.
    chip.refresh("retintfull")
    full = chip_hl("retintfull")
    ok(
      full.fg == 0xff0000 and full.bg == 0x0000ff,
      "the fixed chip keeps its colours after refresh()"
    )
    local pulsing = chip_hl("retintpulse")
    ok(
      pulsing.fg == 0x123456 and pulsing.bg == 0x654321,
      "a running pulse keeps its colour across the scheme change"
    )
  end)

  for _, id in ipairs(ids) do
    pcall(chip.unmount, id)
  end
  for name, hl in pairs(saved) do
    api.nvim_set_hl(0, name, hl)
  end
  assert(done, err)
end
