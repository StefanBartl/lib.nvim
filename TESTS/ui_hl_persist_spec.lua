-- TESTS/ui_hl_persist_spec.lua — lib.nvim.ui.hl.persist
--
-- The behaviours that made this worth extracting from 19 hand-written
-- blocks, each asserted against real `ColorScheme` / `OptionSet background`
-- events rather than a stubbed autocmd layer: the point of the module is
-- that the events are wired correctly, which a stub cannot show.

return function(H)
  local eq, ok = H.eq, H.ok

  local hl = require("lib.nvim.ui.hl")

  --- Fire a real ColorScheme event.
  local function colorscheme()
    vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "*" })
  end

  --- Fire a real `OptionSet background` event.
  local function background_changed()
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
  end

  -- ------------------------------------------------- applies immediately
  do
    local calls = 0
    local handle = hl.persist(function()
      calls = calls + 1
    end, { name = "spec_hl_persist_immediate" })
    eq(calls, 1, "persist() applies once immediately by default")
    handle.detach()
  end

  -- `immediate = false` registers only.
  do
    local calls = 0
    local handle = hl.persist(function()
      calls = calls + 1
    end, { name = "spec_hl_persist_deferred", immediate = false })
    eq(calls, 0, "immediate = false does not apply on registration")
    colorscheme()
    eq(calls, 1, "...but the ColorScheme autocmd is still registered")
    handle.detach()
  end

  -- ------------------------------------------------------ re-application
  do
    local calls = 0
    local handle = hl.persist(function()
      calls = calls + 1
    end, { name = "spec_hl_persist_reapply" })
    colorscheme()
    eq(calls, 2, "re-applies on ColorScheme")
    background_changed()
    eq(calls, 3, "re-applies on OptionSet background by default")
    handle.detach()
  end

  -- The background half is what almost every hand-written site forgot, so
  -- it is on by default -- and opting out has to actually opt out.
  do
    local calls = 0
    local handle = hl.persist(function()
      calls = calls + 1
    end, { name = "spec_hl_persist_nobg", background = false })
    background_changed()
    eq(calls, 1, "background = false ignores OptionSet background")
    colorscheme()
    eq(calls, 2, "...while ColorScheme still re-applies")
    handle.detach()
  end

  -- ------------------------------------------------------------ set-ness
  do
    local handle = hl.persist({
      LibSpecPersistA = { fg = "#ff0000" },
      LibSpecPersistB = { bg = "NONE" },
    }, { name = "spec_hl_persist_static" })

    local a = vim.api.nvim_get_hl(0, { name = "LibSpecPersistA" })
    eq(a.fg, 0xff0000, "a static table's groups are actually defined")

    -- Wipe them the way a colorscheme would, then prove they come back.
    vim.api.nvim_set_hl(0, "LibSpecPersistA", {})
    eq(vim.api.nvim_get_hl(0, { name = "LibSpecPersistA" }).fg, nil, "group cleared")
    colorscheme()
    eq(
      vim.api.nvim_get_hl(0, { name = "LibSpecPersistA" }).fg,
      0xff0000,
      "a cleared group is redefined on ColorScheme"
    )
    handle.detach()
  end

  -- A function may return the table instead of being one.
  do
    local colour = "#00ff00"
    local handle = hl.persist(function()
      return { LibSpecPersistDerived = { fg = colour } }
    end, { name = "spec_hl_persist_derived" })
    eq(
      vim.api.nvim_get_hl(0, { name = "LibSpecPersistDerived" }).fg,
      0x00ff00,
      "a function spec's returned groups are applied"
    )

    -- The point of the function form: the value is re-read, not frozen.
    colour = "#0000ff"
    colorscheme()
    eq(
      vim.api.nvim_get_hl(0, { name = "LibSpecPersistDerived" }).fg,
      0x0000ff,
      "the function is re-evaluated, so derived colours follow the theme"
    )
    handle.detach()
  end

  -- ------------------------------------------------------------- detach
  do
    local calls = 0
    local handle = hl.persist(function()
      calls = calls + 1
    end, { name = "spec_hl_persist_detach" })
    handle.detach()
    colorscheme()
    background_changed()
    eq(calls, 1, "detach() stops both autocommands")
  end

  -- ----------------------------------------------------------- idempotent
  --
  -- Re-registering under the same name must replace, not stack: a caller
  -- re-running its setup after a config change is the normal case.
  do
    local calls = 0
    local function spec()
      calls = calls + 1
    end
    local h1 = hl.persist(spec, { name = "spec_hl_persist_twice" })
    local h2 = hl.persist(spec, { name = "spec_hl_persist_twice" })
    calls = 0
    colorscheme()
    eq(calls, 1, "a second persist() under the same name replaces the first")
    h1.detach()
    h2.detach()
  end

  -- ------------------------------------------------------------- errors
  --
  -- A throwing callback must not take the ColorScheme event down with it:
  -- every other listener in the session is behind the same event.
  do
    local later_ran = false
    local bad = hl.persist(function()
      error("spec: deliberate failure")
    end, { name = "spec_hl_persist_throws", immediate = false })
    local good = hl.persist(function()
      later_ran = true
    end, { name = "spec_hl_persist_after_throw", immediate = false })

    local fired = pcall(colorscheme)
    ok(fired, "a throwing callback does not propagate out of the event")
    ok(later_ran, "...and the next listener still runs")

    bad.detach()
    good.detach()
  end

  -- ------------------------------------------------------------ handle
  do
    local calls = 0
    local handle = hl.persist(function()
      calls = calls + 1
    end, { name = "spec_hl_persist_handle", immediate = false })
    handle.apply()
    eq(calls, 1, "handle.apply() re-applies on demand")
    handle.detach()
  end
end
