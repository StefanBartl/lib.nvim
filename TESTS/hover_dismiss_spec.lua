-- TESTS/hover_dismiss_spec.lua — waving one hover away, and switching the
-- feature off for the session.
--
-- Two things that look like the same feature and are not. `dismiss` ends by
-- itself the moment the cursor reaches another target; `toggle` ends only
-- when someone turns it back on. The asymmetry is the reason both exist, and
-- most of what is asserted here is about where each one stops.
--
-- The dismiss keys are borrowed globally like the scroll keys, for the same
-- reason: the float is `focusable = false` and can never hold a mapping of
-- its own, so `q` and `<Esc>` pressed "in" it are really pressed in the
-- document. Unlike the scroll keys they are bound for *every* hover, because
-- every hover can be waved away — including one with nothing to scroll.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local hover = require("lib.nvim.hover")
  local float = require("lib.nvim.hover.float")

  --- `H.eq` compares by identity, and the key config is a list.
  ---@param a any
  ---@param b any
  ---@param msg string
  local function same(a, b, msg)
    ok(vim.deep_equal(a, b), msg .. " (got " .. vim.inspect(a) .. ")")
  end

  ---@return string|nil desc of the normal-mode mapping for `lhs`, if any
  local function mapped(lhs)
    local m = vim.fn.maparg(lhs, "n", false, true)
    return type(m) == "table" and m.desc or nil
  end

  -- ── Configuration ───────────────────────────────────────────────────────
  local c = hover.setup({ enabled = true })
  same(c.dismiss_keys, { "q", "<Esc>" }, "q and <Esc> are the defaults")

  c = hover.setup({ dismiss_keys = { "<C-c>" } })
  same(
    c.dismiss_keys,
    { "<C-c>" },
    "a configured list replaces the default, index-merging none of it"
  )

  hover.setup({ dismiss_keys = { "q", "<Esc>" } })

  -- ── Borrowing and returning the keys ────────────────────────────────────
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local short = tmp .. "/short.txt"
  vim.fn.writefile({ "one", "two" }, short)
  local doc = tmp .. "/doc.md"
  vim.fn.writefile({ "see ./short.txt here", "nothing to see on this line" }, doc)

  -- A key of the user's that the default is about to shadow.
  vim.keymap.set("n", "q", "<Cmd>echo 'mine'<CR>", { desc = "user mapping" })

  vim.cmd.edit(doc)
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  ok(hover.show(), "a bare path in the line opens a hover")
  ok(float.is_open(), "…and the float is really on screen")

  ok((mapped("q") or ""):find("dismiss", 1, true) ~= nil, "q is borrowed while a hover is up")
  ok((mapped("<Esc>") or ""):find("dismiss", 1, true) ~= nil, "…and so is <Esc>")
  eq(
    mapped("<M-PageDown>"),
    nil,
    "a two-line preview fits, so the scroll keys are left alone — the dismiss keys are not conditional the same way"
  )

  ok(hover.dismiss(), "dismissing reports that there was something to dismiss")
  eq(float.is_open(), false, "the float is gone")
  eq(mapped("q"), "user mapping", "…and the mapping it had borrowed is handed back, not deleted")

  -- ── Where the dismissal stops ───────────────────────────────────────────
  eq(
    hover.show(),
    false,
    "the same target stays dismissed while the cursor is still standing on it — otherwise the next CursorHold undoes the keystroke"
  )
  eq(float.is_open(), false, "and nothing reopened behind it")

  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  eq(hover.show(), false, "a line with no target shows nothing (and ends the dismissal)")

  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  ok(hover.show(), "coming back to the target hovers again: no second keystroke to remember")

  ok(hover.dismiss(), "dismiss it once more")
  ok(hover.show({ force = true }), "an explicit forced show overrides a standing dismissal")
  hover.hide()
  eq(hover.dismiss(), false, "dismissing with no hover open reports false rather than throwing")

  -- ── The session-wide switch ─────────────────────────────────────────────
  local said = {}
  local orig_notify = vim.notify
  -- A test double for the duration of this case; the original is restored
  -- below.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    said[#said + 1] = tostring(msg)
  end

  eq(hover.toggle(false), false, "toggle reports the state it leaves behind")
  eq(hover.is_enabled(), false, "the hover is off")
  eq(
    vim.g.lib_nvim_hover_disable,
    true,
    "…stored in the vim.g switch the module already documents, not in a second private flag that could disagree with it"
  )

  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  eq(hover.show(), false, "nothing hovers while it is off")
  ok(hover.show({ force = true }), "force still overrides the enabled flag, as it always did")
  hover.hide()

  -- Dismiss something *while it is off*, so the on-switch has a standing
  -- dismissal to clear. A per-target "not now" that survives an off/on cycle
  -- is invisible state, and makes the hover look like it came back half on.
  ok(hover.show({ force = true }), "force opens one more, to be dismissed")
  ok(hover.dismiss(), "…and it is dismissed")

  eq(hover.toggle(), true, "toggling with no argument flips it back on")
  eq(vim.g.lib_nvim_hover_disable, false, "…by clearing the same flag")
  ok(hover.show(), "and a target hovers again — the switch clears any standing dismissal")
  hover.hide()

  vim.notify = orig_notify
  eq(#said, 2, "each toggle says so: an invisible off-state gets reported as a broken feature")
  ok(said[1]:find("off", 1, true) ~= nil, "the first one announced the off state")
  ok(said[2]:find("on", 1, true) ~= nil, "…the second the on state")

  -- ── Leave the editor as the next spec expects to find it ────────────────
  pcall(vim.keymap.del, "n", "q")
  vim.g.lib_nvim_hover_disable = nil
  -- toggle(true) re-runs enable(), which installs a global FileType autocmd.
  pcall(vim.api.nvim_del_augroup_by_name, "LibNvimHoverEnable")
  vim.fn.delete(tmp, "rf")
  vim.cmd("silent! %bwipeout!")
  hover.setup({ dismiss_keys = { "q", "<Esc>" }, enabled = true })
end
