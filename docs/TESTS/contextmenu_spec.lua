-- docs/TESTS/contextmenu_spec.lua — lib.nvim.contextmenu: entry/group/submenu
-- (pure data builders) and bind_buffer's soft-dependency degradation.

return function(H)
  local eq = H.eq
  local ok = H.ok
  local contextmenu = require("lib.nvim.contextmenu")

  -- ---------- entry ----------

  do
    eq(contextmenu.entry(false, "X", function() end), nil, "entry: nil when unavailable")
    eq(contextmenu.entry(nil, "X", function() end), nil, "entry: nil for falsy nil")

    local fn = function() end
    local e = contextmenu.entry(true, "  Do X", fn, "<leader>x")
    ok(type(e) == "table", "entry: table when available")
    eq(e.name, "  Do X", "entry: name")
    eq(e.rtxt, "<leader>x", "entry: rtxt")
    eq(e.cmd, fn, "entry: cmd is the passed function")

    local e_no_rtxt = contextmenu.entry(true, "Y", fn)
    eq(e_no_rtxt.rtxt, nil, "entry: rtxt omitted stays nil")
  end

  -- ---------- group ----------

  do
    local out = {}
    local added = contextmenu.group(out, nil, nil)
    eq(added, false, "group: false when every item is nil")
    eq(#out, 0, "group: nothing appended for an all-nil group")

    local a = { name = "A" }
    local b = { name = "B" }
    -- `b` sits after a nil gap — this is exactly the case a table-literal
    -- implementation (`ipairs`/`#`) would silently drop.
    added = contextmenu.group(out, a, nil, b)
    eq(added, true, "group: true when at least one item survives")
    eq(#out, 2, "group: nils dropped, non-nils appended (including past a nil gap)")
    eq(out[1], a, "group: first item in order")
    eq(out[2], b, "group: second item in order, survives despite the preceding nil")

    -- A second group on a non-empty `out` gets a separator prefix.
    local c = { name = "C" }
    contextmenu.group(out, c)
    eq(#out, 4, "group: separator + new item appended")
    eq(out[3].name, "separator", "group: separator inserted before a second group")
    eq(out[4], c, "group: new group's item appended after the separator")

    -- An empty/all-nil group after existing content adds nothing, not even
    -- a dangling separator.
    contextmenu.group(out)
    eq(#out, 4, "group: an empty group adds no separator")
  end

  -- ---------- submenu ----------

  do
    eq(contextmenu.submenu("Label", {}), nil, "submenu: nil for empty items")
    eq(contextmenu.submenu("Label", "not-a-table"), nil, "submenu: nil for non-table items")

    local items = { { name = "A" } }
    local sub = contextmenu.submenu("  MyPlugin", items)
    ok(type(sub) == "table", "submenu: table when items non-empty")
    eq(sub.name, "  MyPlugin", "submenu: name is the label")
    eq(sub.items, items, "submenu: items passed through")
  end

  -- ---------- bind_buffer: soft dependency, no nvzone/menu required ----------

  do
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()

    local get_items_called = false
    contextmenu.bind_buffer(buf, function()
      get_items_called = true
      return {}
    end, { desc = "test menu" })

    -- Triggering the keymap must not error even though "menu" (nvzone/menu)
    -- is not installed in the test environment — bind_buffer soft-requires
    -- it at trigger time and degrades to a single notify.
    local mapped = vim.fn.maparg("<RightMouse>", "n", false, true)
    ok(
      type(mapped) == "table" and mapped.buffer == 1,
      "bind_buffer: registers a buffer-local mapping"
    )
    eq(mapped.desc, "test menu", "bind_buffer: keymap desc passed through")

    local call_ok = pcall(mapped.callback)
    ok(call_ok, "bind_buffer: triggering without nvzone/menu installed doesn't error")
    -- get_items is only invoked after the soft-require of "menu" succeeds;
    -- it must NOT have been reached here, since "menu" isn't installed.
    eq(get_items_called, false, "bind_buffer: get_items not called when menu is missing")

    vim.cmd("bwipeout! " .. buf)
  end
end
