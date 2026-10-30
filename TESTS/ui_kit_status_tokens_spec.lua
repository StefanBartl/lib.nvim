-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_status_tokens_spec.lua -- the status tokens `ok`, `warn`, `info` and `dim` of the kit theme
-- (groups KitOk, KitWarn, KitInfo, KitDim): their default links, an override table, a preset of the caller's
-- own that sets them, and the fixed-palette `hacker` preset that sets them as colours.

return function(H)
  local eq, ok = H.eq, H.ok
  local theme = require("lib.nvim.ui.kit.theme")

  local DEFAULTS =
    { ok = "DiagnosticOk", warn = "DiagnosticWarn", info = "DiagnosticInfo", dim = "Comment" }
  local GROUPS = { ok = "KitOk", warn = "KitWarn", info = "KitInfo", dim = "KitDim" }

  local function link_of(group)
    return vim.api.nvim_get_hl(0, { name = group, link = true }).link
  end

  -- Every link-based built-in preset keeps the diagnostic defaults.
  for _, name in ipairs({ "rounded", "minimal", "solid", "double", "ascii", "dock_left", "menu" }) do
    local hl = theme.resolve(name).hl
    for token, group in pairs(DEFAULTS) do
      eq(hl[token], group, ("preset %s: %s links to %s"):format(name, token, group))
    end
  end

  -- nil resolves to the active default, which carries them too.
  local active = theme.resolve(nil).hl
  for token, group in pairs(DEFAULTS) do
    eq(active[token], group, "the active default has " .. token)
  end

  -- Materializing defines the four global groups as links.
  theme.materialize(theme.resolve("rounded"))
  for token, group in pairs(GROUPS) do
    eq(link_of(group), DEFAULTS[token], group .. " links to " .. DEFAULTS[token])
  end

  -- An override table changes one token (to a link or to a spec) and leaves the others.
  local resolved = theme.resolve({ hl = { ok = "String", dim = { fg = "#808080" } } })
  eq(resolved.hl.ok, "String", "override: ok becomes a link to String")
  eq(resolved.hl.dim.fg, "#808080", "override: dim becomes a spec")
  eq(resolved.hl.warn, "DiagnosticWarn", "override: warn is untouched")
  eq(resolved.hl.info, "DiagnosticInfo", "override: info is untouched")
  theme.materialize(resolved)
  eq(link_of("KitOk"), "String", "KitOk follows the override")
  eq(link_of("KitWarn"), "DiagnosticWarn", "KitWarn keeps its default")
  eq(
    string.format("#%06x", vim.api.nvim_get_hl(0, { name = "KitDim" }).fg),
    "#808080",
    "KitDim carries the override's colour"
  )

  -- A preset of the caller's own (registered through setup) overrides them per preset. The name is
  -- unique to this spec and the active default stays as it was, so later specs are not affected.
  local before = theme.default()
  theme.setup({
    presets = { status_tokens_spec = { hl = { warn = "WarningMsg", info = "Identifier" } } },
  })
  eq(theme.default(), before, "registering a preset leaves the active default")
  local own = theme.resolve("status_tokens_spec").hl
  eq(own.warn, "WarningMsg", "own preset: warn")
  eq(own.info, "Identifier", "own preset: info")
  eq(own.ok, "DiagnosticOk", "own preset: ok keeps its default")
  eq(own.dim, "Comment", "own preset: dim keeps its default")

  -- The fixed-palette preset sets them as colours, not as links.
  local hacker = theme.resolve("hacker").hl
  for token in pairs(DEFAULTS) do
    ok(
      type(hacker[token]) == "table" and type(hacker[token].fg) == "string",
      "hacker: " .. token .. " is a colour"
    )
  end

  -- Leave the shared instance with the default groups again.
  theme.materialize(theme.resolve(nil))
end
