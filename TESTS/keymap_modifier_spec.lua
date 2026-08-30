-- TESTS/keymap_modifier_spec.lua -- lib.nvim.bindings.keymap.modifier
--
-- The modifier reads the keys that follow it with `getcharstr()`, so every
-- case here goes through `nvim_feedkeys(..., "mtx")`: "m" so the modifier
-- mapping itself fires, "t" so the following keys reach `getcharstr` as
-- typeahead, "x" to run it all before the assertion.
--
-- Targets are shaped like the real ones this has to survive: buffer-local,
-- string-rhs, `expr`, and callbacks that return nothing at all.

return function(H)
  local eq, ok = H.eq, H.ok

  local modifier = require("lib.nvim.bindings.keymap.modifier")

  -- Every capture assertion below reads register `+`. A bare CI runner has no
  -- clipboard provider, so writes to `+` are dropped there and the whole spec
  -- would fail for a reason that has nothing to do with the modifier. An
  -- in-process provider makes `+` behave the same on a developer machine and
  -- on a runner -- and it keeps the spec from touching the real clipboard of
  -- whoever runs it. Restored at the end: the runner shares one Neovim
  -- process across all spec files.
  local prev_clipboard = vim.g.clipboard
  local clip_lines = { "" }

  local function reload_clipboard()
    vim.cmd("unlet! g:loaded_clipboard_provider")
    vim.cmd("runtime autoload/provider/clipboard.vim")
  end

  vim.g.clipboard = {
    name = "keymap-modifier-spec",
    copy = {
      ["+"] = function(lines)
        clip_lines = lines
      end,
      ["*"] = function(lines)
        clip_lines = lines
      end,
    },
    paste = {
      ["+"] = function()
        return clip_lines, "v"
      end,
      ["*"] = function()
        return clip_lines, "v"
      end,
    },
    cache_enabled = 0,
  }
  reload_clipboard()

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mtx", false)
    vim.wait(30)
  end

  local function clipboard()
    return vim.fn.getreg("+")
  end

  local function reset_registers()
    for _, r in ipairs({ "+", "*", '"', "0" }) do
      pcall(vim.fn.setreg, r, "")
    end
  end

  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta" })
  local buf = vim.api.nvim_get_current_buf()

  -- Tier 2: cooperative, hands its result back.
  vim.keymap.set("n", "[r", function()
    return "RESULT-FROM-RETURN"
  end, { buffer = buf })

  -- Tier 3: the shape a file tree's "yank path" mapping actually has --
  -- moves a register, returns nothing, buffer-local.
  --
  -- These targets write the *unnamed* register, not `+`, on purpose. A real
  -- one would write `+`, but then asserting on `+` would pass whether or not
  -- the modifier captured anything -- the target set it either way. Writing
  -- `"` and asserting `+` makes the modifier the only thing that could have
  -- put the value there. (Checked: with tier 3 stubbed out these fail.)
  vim.keymap.set("n", "[y", function()
    vim.fn.setreg('"', "RESULT-FROM-REGISTER")
  end, { buffer = buf })

  -- Tier 3 via a string rhs: no callback exists to call at all.
  vim.keymap.set(
    "n",
    "[s",
    ':let @" = "RESULT-FROM-STRING-RHS"<CR>',
    { buffer = buf, silent = true }
  )

  -- Tier 4: only mutates the buffer, produces no string.
  local opaque_runs = 0
  vim.keymap.set("n", "[o", function()
    opaque_runs = opaque_runs + 1
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "MUTATED" })
  end, { buffer = buf })

  -- `expr`: its return value is a key sequence, never a result.
  vim.keymap.set("n", "[e", function()
    return "ix<Esc>"
  end, { buffer = buf, expr = true })

  -- Tier 1: declared separately, overrides everything the mapping does.
  vim.keymap.set("n", "[d", function()
    vim.fn.setreg('"', "WRONG-LOW-TIER-VALUE")
  end, { buffer = buf })

  -- ------------------------------------------------------------- setup

  eq(modifier.keys().copy, nil, "keys(): nothing bound before setup")
  eq(modifier.setup(), false, "setup(): returns false without `experimental`")
  eq(vim.fn.maparg("\\", "n"), "", "setup(): binds nothing without `experimental`")

  ok(modifier.setup({ experimental = true }), "setup(): returns true when opted in")
  eq(modifier.keys().copy, "\\", "setup(): default copy modifier is `\\`")
  eq(modifier.keys().insert, "\\\\", "setup(): default insert modifier is `\\\\`")

  eq(
    modifier.setup({ experimental = true, copy = "gm", insert = "gm" }),
    false,
    "setup(): rejects two identical keys"
  )
  modifier.setup({ experimental = true })

  -- ------------------------------------------------- the four capture tiers

  reset_registers()
  press("\\[r")
  eq(clipboard(), "RESULT-FROM-RETURN", "tier 2: a returned string is captured")

  reset_registers()
  press("\\[y")
  eq(
    clipboard(),
    "RESULT-FROM-REGISTER",
    "tier 3: a moved register is captured with no cooperation"
  )

  reset_registers()
  press("\\[s")
  eq(
    clipboard(),
    "RESULT-FROM-STRING-RHS",
    "tier 3: works for a string rhs, which has no callback to call"
  )

  -- tier 4: the mapping still runs, nothing is claimed to be captured
  reset_registers()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta" })
  press("\\[o")
  eq(opaque_runs, 1, "tier 4: the target mapping still ran")
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "MUTATED", "tier 4: its effect happened")
  eq(clipboard(), "", "tier 4: nothing bogus was copied")

  -- `expr`: fed as keys, and its return value never mistaken for a result
  reset_registers()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta" })
  press("\\[e")
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "xalpha", "expr: executed as keys")
  eq(clipboard(), "", "expr: its return value is not treated as a result")

  -- tier 1 outranks the register the mapping moved
  reset_registers()
  modifier.declare("n", "[d", function()
    return "RESULT-FROM-DECLARATION"
  end)
  press("\\[d")
  eq(clipboard(), "RESULT-FROM-DECLARATION", "tier 1: a declaration wins over a moved register")
  modifier.undeclare("n", "[d")
  reset_registers()
  press("\\[d")
  eq(clipboard(), "WRONG-LOW-TIER-VALUE", "undeclare(): falls back to the observed register")

  -- --------------------------------------------- `\` and `\\` coexist

  reset_registers()
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
  local buf2 = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "[r", function()
    return "INSERTED-VALUE"
  end, { buffer = buf2 })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("\\\\[r")
  eq(clipboard(), "INSERTED-VALUE", "insert modifier copies too")
  ok(
    vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("INSERTED-VALUE", 1, true) ~= nil,
    "insert modifier put the result into the writable buffer"
  )

  -- the single-key modifier still resolves when the next key is not a `\`
  reset_registers()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
  press("\\[r")
  eq(clipboard(), "INSERTED-VALUE", "copy modifier still resolves next to the longer one")
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "one", "copy modifier did not insert anything")

  -- ------------------------------------------------------- unresolved target

  reset_registers()
  press("\\[z") -- nothing is mapped there
  eq(clipboard(), "", "an unmapped target copies nothing")

  -- ------------------------------------------------------------ teardown

  modifier.teardown()
  eq(modifier.keys().copy, nil, "teardown(): forgets the copy modifier")
  eq(vim.fn.maparg("\\", "n"), "", "teardown(): removes the copy keymap")
  eq(vim.fn.maparg("\\\\", "n"), "", "teardown(): removes the insert keymap")

  modifier.setup({ experimental = true })
  eq(
    modifier.setup({ experimental = false }),
    false,
    "setup(): `experimental = false` returns false"
  )
  eq(vim.fn.maparg("\\", "n"), "", "setup(): `experimental = false` unbinds")

  for _, k in ipairs({ "[r", "[y", "[s", "[o", "[e", "[d" }) do
    pcall(vim.keymap.del, "n", k, { buffer = buf })
  end
  pcall(vim.keymap.del, "n", "[r", { buffer = buf2 })

  vim.g.clipboard = prev_clipboard
  reload_clipboard()
end
