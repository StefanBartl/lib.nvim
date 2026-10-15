-- TESTS/keymap_cheatsheet_spec.lua — lib.nvim.bindings.keymap.cheatsheet: lines + highlight spans of a g?
-- cheatsheet, built from what a plugin really has bound.

return function(H)
  local eq, ok = H.eq, H.ok
  local keymap = require("lib.nvim.bindings.keymap")

  local function noop() end

  ---@param plugin string
  ---@param user table|false|nil
  ---@param extra? table
  local function register(plugin, user, extra)
    keymap.register(plugin, {
      order = { "run", "next", "prev", "both", "gone", "keyless", "help" },
      actions = vim.tbl_extend("force", {
        run = { default = "<Plug>(cs-run)", rhs = noop, desc = "run the file" },
        next = { default = "<Plug>(cs-next)", rhs = noop, desc = "next failure" },
        prev = { default = "<Plug>(cs-prev)", rhs = noop, desc = "previous failure" },
        both = {
          default = { "<Plug>(cs-both-a)", "<Plug>(cs-both-b)" },
          mode = { "n", "x" },
          rhs = noop,
          desc = "one action on two keys",
        },
        gone = { default = "<Plug>(cs-gone)", rhs = noop, desc = "disabled below" },
        keyless = { rhs = noop, desc = "only by command" },
        help = { default = "<Plug>(cs-help)", rhs = noop, desc = "this help" },
      }, extra or {}),
    }, user)
  end

  -- a plain registered plugin: flat list, aligned, only bound actions
  register("cs_flat", { gone = false })
  local sheet = keymap.cheatsheet("cs_flat")
  local shown = {}
  for _, r in ipairs(sheet.rows) do
    shown[#shown + 1] = r.name
  end
  eq(
    table.concat(shown, ","),
    "run,next,prev,both,help",
    "flat: bound actions in declaration order"
  )
  eq(#sheet.lines, 5, "flat: one line per action, no heading")
  ok(sheet.lines[1]:find("run the file", 1, true) ~= nil, "flat: the description is on the line")
  ok(
    not sheet.lines[1]:find("cs_flat:", 1, true),
    "flat: the `plugin: ` prefix of the registry is stripped"
  )
  for _, l in ipairs(sheet.lines) do
    ok(not l:find("disabled below", 1, true), "flat: a disabled action is not listed")
    ok(not l:find("only by command", 1, true), "flat: an action with no key is not listed")
  end

  -- alignment: every description starts in the same column
  local col
  for i, r in ipairs(sheet.rows) do
    local at = sheet.lines[i]:find(r.desc, 1, true)
    col = col or at
    eq(at, col, "flat: descriptions are aligned (" .. r.name .. ")")
  end

  -- several keys per action, all shown
  local both_line
  for i, r in ipairs(sheet.rows) do
    if r.name == "both" then
      both_line = sheet.lines[i]
      eq(#r.keys, 2, "several keys: both are collected")
      eq(#r.modes, 2, "several keys: ... and the modes are merged")
    end
  end
  ok(
    both_line:find("<Plug>(cs-both-a) / <Plug>(cs-both-b)", 1, true) ~= nil,
    "several keys: shown together on one line"
  )

  -- highlight spans point at the key text and the description
  local key_span
  for _, h in ipairs(sheet.highlights) do
    if h.line == 0 and h.group == "Special" then
      key_span = h
    end
  end
  ok(key_span ~= nil, "spans: the key column is highlighted")
  eq(
    sheet.lines[1]:sub(key_span.col_start + 1, key_span.col_end),
    "<Plug>(cs-run)",
    "spans: ... exactly over the key text (0-based, end exclusive)"
  )

  -- groups: headings, leftovers under "Other", an unbound action in a group is skipped
  local grouped = keymap.cheatsheet("cs_flat", {
    groups = {
      { title = "Move", actions = { "next", "prev", "gone" } },
      { title = "Run", actions = { "run" } },
    },
    other_title = "Misc",
    footer = "q close",
  })
  eq(grouped.lines[1], "Move", "groups: first heading")
  local text = table.concat(grouped.lines, "\n")
  ok(text:find("\nRun\n", 1, true) ~= nil, "groups: second heading")
  ok(text:find("\nMisc\n", 1, true) ~= nil, "groups: the leftovers get `other_title`")
  ok(text:find("%f[%w]gone%f[%W]") == nil, "groups: a disabled action in a group is skipped")
  eq(grouped.lines[#grouped.lines], "  q close", "footer: the hint is the last line")
  ok(text:find("\n\n  q close", 1, true) ~= nil, "footer: separated from the list by a blank line")
  local heading_span
  for _, h in ipairs(grouped.highlights) do
    if h.line == 0 and h.group == "Title" then
      heading_span = h
    end
  end
  ok(heading_span ~= nil, "groups: headings are highlighted")

  -- width: a long description is cut, never wider than asked
  local narrow = keymap.cheatsheet("cs_flat", { width = 30 })
  eq(narrow.width <= 30, true, "width: no line is wider than the limit (" .. narrow.width .. ")")
  ok(
    table.concat(narrow.lines, "\n"):find("…", 1, true) ~= nil,
    "width: a cut text ends in an ellipsis"
  )

  -- modes column on request
  local with_modes = keymap.cheatsheet("cs_flat", { modes = true })
  local both_idx
  for i, r in ipairs(with_modes.rows) do
    if r.name == "both" then
      both_idx = i
    end
  end
  ok(
    with_modes.lines[both_idx]:find("n,x ", 1, true) ~= nil,
    "modes: an action not normal-only is prefixed"
  )
  eq(
    with_modes.lines[1]:sub(1, 16),
    "  <Plug>(cs-run)",
    "modes: a normal-only action is left plain"
  )

  -- nothing bound: no lines, not an error
  register("cs_off", false)
  local empty = keymap.cheatsheet("cs_off")
  eq(#empty.lines, 0, "preset = false: nothing is bound, nothing is listed")
  eq(#keymap.cheatsheet("cs_never_registered").lines, 0, "an unknown plugin gives an empty sheet")
  eq(
    #keymap.cheatsheet("cs_off", { footer = "x" }).lines,
    1,
    "empty sheet with a footer: just the footer"
  )

  -- buffer-local entries only appear for that buffer
  local buf = vim.api.nvim_create_buf(false, true)
  keymap.register("cs_buf", {
    actions = { here = { default = "<Plug>(cs-here)", rhs = noop, desc = "only here" } },
  }, nil, { buffer = buf })
  eq(
    #keymap.cheatsheet("cs_buf").lines,
    0,
    "buffer: a buffer-local action is not in the global sheet"
  )
  eq(
    #keymap.cheatsheet("cs_buf", { buffer = buf }).lines,
    1,
    "buffer: ... but in that buffer's sheet"
  )
  vim.api.nvim_buf_delete(buf, { force = true })

  -- a surface is its own registry key
  keymap.register("cs_surf", {
    actions = { s = { default = "<Plug>(cs-surf)", rhs = noop, desc = "on the list" } },
  }, nil, { surface = "list" })
  eq(#keymap.cheatsheet("cs_surf/list").lines, 1, "surface: `plugin/surface` is addressed as given")
  ok(
    keymap.cheatsheet("cs_surf/list").lines[1]:find("on the list", 1, true) ~= nil,
    "surface: ... prefix stripped too"
  )

  -- a description with a newline or a control character stays ONE buffer line
  keymap.register("cs_nl", {
    actions = {
      multi = {
        default = "<Plug>(cs-nl)",
        rhs = noop,
        desc = "first line" .. string.char(10) .. "second",
      },
      tabbed = { default = "<Plug>(cs-tab)", rhs = noop, desc = "a" .. string.char(9) .. "b" },
    },
  }, nil)
  local nl_sheet = keymap.cheatsheet("cs_nl", {
    footer = "hint" .. string.char(10) .. "more",
    groups = { { title = "T" .. string.char(10) .. "T", actions = { "multi", "tabbed" } } },
  })
  for _, l in ipairs(nl_sheet.lines) do
    ok(not l:find("%c"), "control characters: no line holds one: " .. vim.inspect(l))
  end
  eq(
    pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, nl_sheet.lines),
    true,
    "control characters: nvim accepts the lines"
  )

  -- a plain set() shows up too (recorded as direct, `bound = true`)
  keymap.set("n", "<Plug>(cs-direct)", noop, {}, "a direct map")
  local direct_found
  for _, r in ipairs(keymap.cheatsheet("(unknown)").rows) do
    if r.keys[1] == "<Plug>(cs-direct)" then
      direct_found = r
    end
  end
  ok(direct_found ~= nil, "direct set(): listed")
  eq(direct_found and direct_found.desc, "a direct map", "direct set(): with its description")

  -- a buffer-local direct set() (recorded as buffer 0/true) counts for the buffer asked about
  local dbuf = vim.api.nvim_create_buf(false, true)
  local prev_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(dbuf)
  keymap.set("n", "<Plug>(cs-direct-buf)", noop, { buffer = true }, "buffer-local direct")
  vim.api.nvim_set_current_buf(prev_buf)
  local in_sheet, in_global = false, false
  for _, r in ipairs(keymap.cheatsheet("(unknown)", { buffer = dbuf }).rows) do
    in_sheet = in_sheet or r.keys[1] == "<Plug>(cs-direct-buf)"
  end
  for _, r in ipairs(keymap.cheatsheet("(unknown)").rows) do
    in_global = in_global or r.keys[1] == "<Plug>(cs-direct-buf)"
  end
  eq(in_sheet, true, "direct buffer-local set(): in that buffer's sheet")
  eq(in_global, false, "direct buffer-local set(): not in the global sheet")
  vim.api.nvim_buf_delete(dbuf, { force = true })
  keymap.forget("(unknown)")

  -- bad input
  eq(pcall(keymap.cheatsheet, ""), false, "an empty plugin name is an error")
  eq(pcall(keymap.cheatsheet, nil), false, "a missing plugin name is an error")

  keymap.forget("cs_flat")
end
