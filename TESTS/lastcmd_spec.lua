-- TESTS/lastcmd_spec.lua — lib.nvim.lastcmd
--
-- The tracker reads real keypresses through `vim.on_key`, so every command
-- here goes through `nvim_feedkeys(..., "mtx", ...)`: "m" so mappings
-- actually fire, "t" so the keys count as typed (which is what `on_key`
-- reports), "x" to execute them synchronously before the next assertion.
--
-- `record()` credits a mapping with the change it is *about* to make from a
-- `vim.schedule` callback (on_key runs before the mapping's rhs), so a short
-- `vim.wait` after each mapping press is needed for that bookkeeping to land
-- — without it the mapping's own edit would later read as a native change.

return function(H)
  local eq, ok = H.eq, H.ok

  local lastcmd = require("lib.nvim.lastcmd")

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mtx", false)
    vim.wait(20)
  end

  -- `replay()` feeds without "x" (it must not execute inside on_key), so a
  -- flush is needed to run what it queued.
  local function repeat_last()
    local ran = lastcmd.repeat_last()
    vim.api.nvim_feedkeys("", "x", false)
    vim.wait(20)
    return ran
  end

  local function lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
  end

  ---The recorded entry's lhs, or nil when nothing is recorded.
  ---@return string|nil
  local function peeked_keys()
    local e = lastcmd.peek()
    return e and e.keys
  end

  -- An indent-like mapping standing in for cascade.nvim's `api.indent`: a
  -- Lua callback editing through the API, which is precisely what native `.`
  -- cannot repeat.
  local indent_calls = 0
  local function indent()
    indent_calls = indent_calls + 1
    local n = vim.v.count1
    local r = vim.api.nvim_win_get_cursor(0)[1]
    for i = r, math.min(r + n - 1, vim.api.nvim_buf_line_count(0)) do
      local l = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
      vim.api.nvim_buf_set_lines(0, i - 1, i, false, { "  " .. l })
    end
  end

  local bullet_calls = 0
  local function bullet()
    bullet_calls = bullet_calls + 1
    local r = vim.api.nvim_win_get_cursor(0)[1]
    local l = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1]
    vim.api.nvim_buf_set_lines(0, r - 1, r, false, { "- " .. l })
  end

  vim.keymap.set("n", "<F5>", indent)
  vim.keymap.set("n", "<F6>", bullet)
  vim.keymap.set("n", "<F7>", function() end) -- a mapped "motion": changes nothing
  vim.keymap.set("n", "gzq", function() end) -- multi-key, to exercise prefixes
  vim.keymap.set("x", "<F8>", function()
    local s, e = require("lib.nvim.selection").lines()
    for i = s, e do
      local l = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
      if l then
        vim.api.nvim_buf_set_lines(0, i, i + 1, false, { ">" .. l })
      end
    end
  end)

  -- ------------------------------------------------------------- setup

  eq(lastcmd.enabled(), false, "enabled(): false before setup")

  -- The feature is opt-in: without `experimental` nothing is installed.
  eq(lastcmd.setup(), false, "setup(): returns false without `experimental`")
  eq(lastcmd.enabled(), false, "setup(): installs nothing without `experimental`")
  eq(lastcmd.trigger_key(), nil, "setup(): binds no trigger without `experimental`")

  eq(
    lastcmd.setup({ experimental = "gzt", ignore = { "<F7>" } }),
    true,
    "setup(): returns true when opted in"
  )
  ok(lastcmd.enabled(), "setup(): installs the tracker")
  eq(lastcmd.trigger_key(), "gzt", "setup(): binds the requested lhs")
  ok(vim.fn.maparg("gzt", "n") ~= "", "setup(): the trigger is a real keymap")

  lastcmd.setup({ experimental = "gzt", ignore = { "<F7>" } })
  ok(lastcmd.enabled(), "setup(): idempotent, no second handler")

  -- switching the key moves the binding rather than leaving both live
  lastcmd.setup({ experimental = "gzu", ignore = { "<F7>" } })
  eq(lastcmd.trigger_key(), "gzu", "setup(): re-binds when the lhs changes")
  eq(vim.fn.maparg("gzt", "n"), "", "setup(): drops the previous trigger")
  lastcmd.setup({ experimental = "gzt", ignore = { "<F7>" } })

  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a1", "a2", "a3", "a4", "a5", "a6" })
  lastcmd.clear()

  -- ------------------------------- mapping tracked, motion never counts

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("3<F5>")
  eq(indent_calls, 1, "mapping ran once")
  eq(lines()[1], "  a1", "mapping indented the first line")
  eq(lines()[3], "  a3", "count reached the third line")

  local entry = lastcmd.peek()
  ok(entry ~= nil, "peek(): a mapping was recorded")
  ---@cast entry -nil
  eq(entry.keys, "<F5>", "peek(): records the mapping lhs in keytrans notation")
  eq(entry.count, "3", "peek(): captures the typed count prefix")
  eq(entry.mode, "n", "peek(): records the matching mapping mode")

  -- pure motions: not mapped, change no text -> cannot become "last command"
  press("jj")
  press("5j")
  eq(indent_calls, 1, "motions do not run the mapping")
  eq(peeked_keys(), "<F5>", "motions do not overwrite the recorded mapping")

  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  ok(repeat_last(), "repeat_last(): reports it ran")
  eq(indent_calls, 2, "repeat_last(): re-ran the mapping")
  eq(lines()[4], "  a4", "repeat_last(): replayed at the new cursor")
  eq(lines()[6], "  a6", "repeat_last(): replayed the captured count (3 lines)")

  -- --------------------------------- most recently tracked mapping wins

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("<F6>")
  eq(bullet_calls, 1, "second mapping ran")
  press("jj")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  repeat_last()
  eq(bullet_calls, 2, "repeat_last(): replays the most recent mapping, not the earlier one")
  eq(indent_calls, 2, "repeat_last(): the earlier mapping did not fire again")

  -- ------------------------------------- a native change is more recent

  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "xxxx", "yyyy", "zzzz" })
  lastcmd.clear()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("<F5>")
  local calls_before = indent_calls
  eq(lines()[1], "  xxxx", "mapping ran in the fresh buffer")

  press("x") -- native change, more recent than the mapping
  eq(lines()[1], " xxxx", "native x deleted one char")

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  repeat_last()
  eq(
    indent_calls,
    calls_before,
    "repeat_last(): did NOT replay the mapping once a native change was newer"
  )
  eq(lines()[2], "yyy", "repeat_last(): repeated the native change via `normal! .`")

  -- a mapping afterwards takes the lead back
  press("<F5>")
  local calls2 = indent_calls
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  repeat_last()
  eq(indent_calls, calls2 + 1, "repeat_last(): a mapping run after a native change wins again")

  -- ------------------------------------------ the repeat key is not tracked
  --
  -- Regression: the guard used to compare the resolved mapping's callback
  -- against `M.repeat_last`, which only matched when the key was bound to
  -- that function *directly*. Every documented binding wraps it in a closure
  -- instead, so the trigger recorded itself and then replayed itself --
  -- feeding its own lhs back through `on_key` forever, hanging the editor.
  -- `gzw` below is that wrapper form; `gzt` is the one `setup` installed.

  local wrapper_calls = 0
  vim.keymap.set("n", "gzw", function()
    wrapper_calls = wrapper_calls + 1
    if wrapper_calls > 20 then
      error("lastcmd: the repeat trigger ran away (self-reference)")
    end
    require("lib.nvim.lastcmd").repeat_last()
  end)

  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "p1", "p2", "p3" })
  lastcmd.clear()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("<F6>")
  local b = bullet_calls
  press("gzt") -- the trigger `setup` bound
  eq(bullet_calls, b + 1, "the trigger replays the tracked mapping")
  eq(peeked_keys(), "<F6>", "the trigger never records itself (no self-reference)")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("gzw") -- a hand-rolled trigger wrapping repeat_last in a closure
  eq(wrapper_calls, 1, "a wrapped trigger fires once, not in a loop")
  eq(bullet_calls, b + 2, "a wrapped trigger replays the tracked mapping too")
  eq(peeked_keys(), "<F6>", "a wrapped trigger does not record itself either")

  -- Regression: pressing the trigger repeatedly must keep replaying. The
  -- replay is fed with "t" so it counts as typed; without that `on_key` never
  -- sees it, `seen` is never credited with the edit the replay just made, and
  -- from the second press on every repeat silently degrades to `normal! .`.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("gzt")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("gzt")
  eq(bullet_calls, b + 4, "the trigger keeps replaying when pressed repeatedly")

  -- ------------------------------------------------ ignore list & prefixes

  press("<F7>") -- mapped, but on the ignore list
  eq(peeked_keys(), "<F6>", "an ignored mapping does not become the last command")

  press("gzq") -- multi-key mapping resolves through its prefix
  eq(peeked_keys(), "gzq", "a multi-key mapping is recorded once complete")

  -- ------------------------------------------------------- visual mode

  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "v1", "v2", "v3", "v4", "v5", "v6" })
  lastcmd.clear()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("Vj<F8>") -- linewise over 2 lines
  eq(lines()[1], ">v1", "visual mapping applied to line 1")
  eq(lines()[2], ">v2", "visual mapping applied to line 2")

  local ventry = lastcmd.peek()
  ok(ventry ~= nil, "peek(): a visual mapping was recorded")
  ---@cast ventry -nil
  eq(ventry.mode, "x", "peek(): records the visual mapping mode")
  local vis = ventry.visual
  ok(vis ~= nil, "peek(): captured the selection shape")
  ---@cast vis -nil
  eq(vis.kind, "V", "peek(): captured linewise kind")
  eq(vis.lines, 2, "peek(): captured the 2-line span")

  vim.cmd("normal! \27")
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  repeat_last()
  eq(lines()[4], ">v4", "visual replay: same-size selection rebuilt at the cursor (line 4)")
  eq(lines()[5], ">v5", "visual replay: covered the second line too")
  eq(lines()[6], "v6", "visual replay: did not overshoot the recorded 2-line span")
  vim.cmd("normal! \27")

  -- ------------------------------------------------------ clear/teardown

  lastcmd.clear()
  eq(lastcmd.peek(), nil, "clear(): drops the recorded entry")

  lastcmd.teardown()
  eq(lastcmd.enabled(), false, "teardown(): removes the tracker")
  eq(lastcmd.trigger_key(), nil, "teardown(): forgets the trigger")
  eq(vim.fn.maparg("gzt", "n"), "", "teardown(): removes the trigger keymap it installed")

  -- `experimental = false` is the runtime off switch, not just an omission
  lastcmd.setup({ experimental = "gzt" })
  ok(lastcmd.enabled(), "setup(): back on")
  eq(
    lastcmd.setup({ experimental = false }),
    false,
    "setup(): `experimental = false` returns false"
  )
  eq(lastcmd.enabled(), false, "setup(): `experimental = false` tears the tracker down")
  eq(vim.fn.maparg("gzt", "n"), "", "setup(): `experimental = false` unbinds the trigger")

  for _, k in ipairs({ "<F5>", "<F6>", "<F7>", "gzq", "gzw" }) do
    pcall(vim.keymap.del, "n", k)
  end
  pcall(vim.keymap.del, "x", "<F8>")
end
