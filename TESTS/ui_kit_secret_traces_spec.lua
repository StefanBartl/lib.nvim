-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_secret_traces_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_secret_traces_spec.lua (the kit exists twice, see ui.nvim's
-- docs/modules.md): what a secret leaves behind in the last Insert run.
--
-- `secret = true` hides a prompt's text on screen and turns its undo off, but the
-- Insert run that typed it is also what Neovim keeps in the `.` register (and
-- `<C-r>.`) and in the redo buffer: after the prompt closed, `.` in any buffer
-- typed the password there. A prompt with a secret (and a sheet with a secret
-- field) overwrites that with an empty run once it is gone. This shared headless
-- run never enters Insert mode for real, so what is pinned is that the scrub runs
-- and what it does; the whole path is ui.nvim's `ui_kit_input_ui_spec.lua` and
-- `ui_kit_sheet_ui_spec.lua`, in a UI-attached child.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local input = require("lib.nvim.ui.kit.input")
  local api = vim.api

  vim.o.showmode = false

  local function keys(k)
    api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "x", false)
  end

  local function close_floats()
    for _ = 1, 10 do
      local closed = false
      for _, w in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
          pcall(api.nvim_win_close, w, true)
          closed = true
        end
      end
      if not closed then
        return
      end
    end
  end

  -- The helper itself: an Insert run is what `.` holds; after the scrub it holds
  -- nothing and replays nothing.
  vim.cmd("enew")
  vim.cmd("normal! ihunter2\27")
  eq(vim.fn.getreg("."), "hunter2", "an Insert run is what `.` holds")
  input.scrub_insert_traces()
  ok(
    vim.wait(1000, function()
      return vim.fn.getreg(".") == ""
    end, 10),
    "the register is empty once the scrub has run"
  )
  api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
  vim.cmd("normal! gg0.")
  eq(api.nvim_buf_get_lines(0, 0, -1, false)[1], "hello", ". types nothing")
  vim.cmd("silent! %bwipeout!")

  -- Who calls it.
  local calls = 0
  local real = input.scrub_insert_traces
  input.scrub_insert_traces = function()
    calls = calls + 1
  end
  local done, err = pcall(function()
    kit.input({ secret = true, on_submit = function() end })
    keys("<CR>")
    eq(calls, 1, "a secret prompt that is submitted")
    kit.input({ secret = true, on_cancel = function() end })
    keys("<Esc>")
    eq(calls, 2, "a secret prompt that is cancelled")
    local surf = kit.input({
      secret = true,
      on_cancel = function()
        error("boom")
      end,
    })
    surf:close()
    eq(calls, 3, "a secret prompt whose callback raises")

    kit.input({ on_submit = function() end })
    keys("<CR>")
    eq(calls, 3, "a prompt without a secret is left alone")

    local fields = { { name = "user" }, { name = "token", secret = true } }
    local sheet = kit.sheet({ fields = fields, on_submit = function() end })
    sheet:submit()
    eq(calls, 4, "a sheet with a secret field that is submitted")
    sheet = kit.sheet({ fields = fields, on_cancel = function() end })
    sheet:cancel()
    eq(calls, 5, "a sheet with a secret field that is cancelled")
    sheet = kit.sheet({ fields = { { name = "user" } }, on_submit = function() end })
    sheet:submit()
    eq(calls, 5, "a sheet without one is left alone")
  end)
  input.scrub_insert_traces = real
  close_floats()
  assert(done, err)
end
