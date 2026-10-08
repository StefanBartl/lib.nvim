-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_secret_buffer_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_secret_buffer_spec.lua (the kit exists twice, see ui.nvim's docs/modules.md):
-- the buffer a secret is typed into, and what shuts the doors the mask does not cover.
--
-- The mask hides the secret on screen, but the buffer holds the real text, and three things read a
-- buffer without looking at the mask:
--
--   * Insert-mode completion. `<C-n>`/`<C-p>` (and `<C-x><C-n>`, `<C-x><C-p>`) complete from the
--     words of the buffer -- which is the secret -- list them in a popup in clear text and insert
--     the pick unmasked; with 'autocomplete' (Neovim 0.12) the popup opens by itself as one types.
--   * The re-mask itself: a candidate inserted from a popup is a change that fires
--     `TextChangedP`, which the hook did not listen for.
--   * A keystroke HUD (ui.nvim's `ui.screenkey`) that shows what is typed: it looks for the buffer
--     variable `surface.SECRET_VAR`, which the prompt and a sheet with a secret field set. (The
--     HUD itself is ui.nvim's, and so is its spec; the name is pinned here because both copies of
--     the kit must use the same one.)
--
-- This runner has no UI and never enters Insert mode by itself, so the keys are fed with
-- `nvim_feedkeys(..., "x")` -- an `A` starts a real Insert run, and the run ends with the keys.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local surface = require("lib.nvim.ui.kit.surface")
  local autocmd = require("lib.nvim.bindings.autocmd")
  local api = vim.api

  --- What the control prompt takes from the buffer, and the secret one must not.
  local TYPED = "hunter2 hunter3 hun"

  ---@param keys string
  local function feed(keys)
    api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "x", false)
  end

  ---@param surf table
  ---@return string
  local function line_of(surf)
    return api.nvim_buf_get_lines(surf.bufnr, 0, 1, false)[1]
  end

  ---@param surf table
  ---@return integer
  local function mark_count(surf)
    local ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
    return #api.nvim_buf_get_extmarks(surf.bufnr, ns, 0, -1, {})
  end

  --- Run `body` with the messages of a fed Insert run (`-- (insert) --`, `match 1 of 2`) off,
  --- and every float closed again whatever happens inside it.
  ---@param name string
  ---@param body fun()
  local function section(name, body)
    local showmode, shortmess = vim.o.showmode, vim.o.shortmess
    vim.o.showmode = false
    vim.opt.shortmess:append("c")
    local done, err = pcall(body)
    vim.cmd("stopinsert")
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
    vim.o.showmode, vim.o.shortmess = showmode, shortmess
    if not done then
      error(("%s: %s"):format(name, tostring(err)), 0)
    end
  end

  -- ---- the buffer is marked (surface.SECRET_VAR) ---------------------------------------------
  section("marks", function()
    local secret = kit.input({ secret = true, relative = "editor" })
    ok(surface.is_secret(secret.bufnr), "a secret prompt is marked")
    ok(surface.is_secret(), "the prompt is the current buffer")
    eq(vim.b[secret.bufnr][surface.SECRET_VAR], true, "the variable itself")
    local plain = kit.input({ relative = "editor" })
    ok(not surface.is_secret(plain.bufnr), "a plain prompt is not")
    ok(not surface.is_secret(), "the plain prompt is the current buffer now")

    local noted = kit.sheet({
      fields = { { name = "user" }, { name = "token", secret = true } },
      relative = "editor",
      on_submit = function() end,
    })
    ok(surface.is_secret(noted.bufnr), "one secret row marks the whole sheet")
    noted:cancel()
    local open = kit.sheet({
      fields = { { name = "user" }, { name = "city" } },
      relative = "editor",
      on_submit = function() end,
    })
    ok(not surface.is_secret(open.bufnr), "a sheet without a secret row is not")
    open:cancel()

    ok(not surface.is_secret(999999), "the question about a buffer that is not there")
    ok(not surface.is_secret(nil), "a normal buffer")
    eq(surface.mark_secret(999999), nil, "marking one that is gone is a no-op")
    -- `ui.screenkey` is one HUD for both copies of the kit: they must use the same name.
    eq(surface.SECRET_VAR, "ui_kit_secret", "the name both copies of the kit use")
  end)

  -- ---- no completion from the words of the buffer ----------------------------------------------
  -- `<C-x><C-n>` and `<C-x><C-p>` complete whatever 'complete' says.
  for _, keys in ipairs({ "<C-n>", "<C-p>", "<C-x><C-n>", "<C-x><C-p>" }) do
    section("completion " .. keys, function()
      -- The control first: without it a changed runner that makes `A` do nothing would pass.
      local plain = kit.input({ default = TYPED, relative = "editor" })
      feed("A" .. keys)
      ok(line_of(plain) ~= TYPED, "the plain prompt completed: " .. line_of(plain))
      plain:close()

      local secret = kit.input({ secret = true, default = TYPED, relative = "editor" })
      feed("A" .. keys)
      eq(line_of(secret), TYPED, "nothing was inserted into the secret")
      secret:close()
    end)
  end

  section("completion in a sheet", function()
    local sheet = kit.sheet({
      fields = {
        { name = "token", secret = true, default = TYPED },
        { name = "note", default = TYPED },
      },
      relative = "editor",
      on_submit = function() end,
    })
    for focus = 1, 2 do
      sheet:focus_field(focus)
      feed("A<C-n>")
      feed("A<C-x><C-n>")
      eq(
        api.nvim_buf_get_lines(sheet.bufnr, focus - 1, focus, false)[1],
        TYPED,
        ("row %d took no word of the sheet"):format(focus)
      )
    end
    sheet:cancel()

    -- The control: only a sheet with a secret field is closed.
    local open = kit.sheet({
      fields = { { name = "note", default = TYPED } },
      relative = "editor",
      on_submit = function() end,
    })
    feed("A<C-n>")
    ok(api.nvim_buf_get_lines(open.bufnr, 0, 1, false)[1] ~= TYPED, "a sheet without a secret row")
    open:cancel()
  end)

  -- ---- ... except in the popup the prompt opened itself ------------------------------------------
  -- A popup of `opts.completion` (`<Tab>`) is cycled with <C-n>/<C-p>. This runner shows no popup,
  -- so `pumvisible()` and the feed are stubbed; the real popup is ui.nvim's UI spec.
  section("the prompt's own popup", function()
    ---@param pum integer
    ---@param key string
    ---@return string[]  # the keys fed to Neovim
    local function press(pum, key)
      local fed = {}
      H.with_patched(vim.fn, "pumvisible", function()
        return pum
      end, function()
        H.with_patched(api, "nvim_feedkeys", function(keys)
          fed[#fed + 1] = keys
        end, function()
          vim.fn.maparg(key, "i", false, true).callback()
        end)
      end)
      return fed
    end

    kit.input({ secret = true, completion = "file", relative = "editor" })
    eq(press(1, "<C-n>")[1], "\14", "<C-n> goes to the open popup")
    eq(press(1, "<C-p>")[1], "\16", "<C-p> too")
    eq(#press(0, "<C-n>"), 0, "<C-n> with no popup does nothing")
    eq(#press(0, "<C-p>"), 0, "<C-p> too")

    local went_back = 0
    kit.input({
      secret = true,
      relative = "editor",
      on_back = function()
        went_back = went_back + 1
      end,
    })
    eq(press(1, "<C-p>")[1], "\16", "<C-p> with on_back still belongs to an open popup")
    eq(went_back, 0, "...and does not go back then")
    press(0, "<C-p>")
    eq(went_back, 1, "with no popup <C-p> still steps back")
  end)

  section("<C-x> and 'autocomplete'", function()
    local secret = kit.input({ secret = true, default = TYPED, relative = "editor" })
    eq(vim.fn.maparg("<C-x>", "i", false, true).rhs, "<Nop>", "<C-x> does nothing")
    secret:close()
    local plain = kit.input({ default = TYPED, relative = "editor" })
    eq(vim.fn.maparg("<C-x>", "i"), "", "a plain prompt leaves it to Neovim")
    plain:close()

    if vim.fn.exists("&autocomplete") == 1 then
      --- The value the buffer really has: its own, else the global one (`vim.bo` and
      --- `nvim_get_option_value` say nil for a global-local option that is not set locally).
      ---@param surf table
      ---@return boolean
      local function autocomplete_of(surf)
        return api.nvim_buf_call(surf.bufnr, function()
          return vim.o.autocomplete
        end)
      end
      local was = vim.go.autocomplete
      vim.go.autocomplete = true
      local done, err = pcall(function()
        local p = kit.input({ relative = "editor" })
        eq(autocomplete_of(p), true, "a plain prompt follows the global one")
        p:close()
        local s = kit.input({ secret = true, relative = "editor" })
        eq(autocomplete_of(s), false, "'autocomplete' is off for a secret prompt")
        s:close()
      end)
      vim.go.autocomplete = was
      assert(done, err)
    end
  end)

  -- ---- masked again after a change made while a popup is open ------------------------------------
  section("re-mask", function()
    local secret = kit.input({ secret = true, relative = "editor" })
    eq(mark_count(secret), 0, "nothing typed, nothing masked")
    api.nvim_buf_set_lines(secret.bufnr, 0, -1, false, { "hunter22" })
    api.nvim_exec_autocmds("TextChangedP", { buffer = secret.bufnr })
    eq(mark_count(secret), 8, "a candidate put in by the popup is masked too")
    for i, event in ipairs({ "TextChangedI", "TextChanged", "TextChangedP" }) do
      api.nvim_buf_set_lines(secret.bufnr, 0, -1, false, { ("x"):rep(i + 2) })
      api.nvim_exec_autocmds(event, { buffer = secret.bufnr })
      eq(mark_count(secret), i + 2, event)
    end
  end)

  -- ---- the hook is the prompt's own ------------------------------------------------------------------
  -- It was in a group named after the buffer: a group and a record per prompt, none of them ever
  -- removed (the `groups`/`group_names` caches and the record list of `bindings.autocmd` grew with
  -- every secret prompt that was ever opened). A buffer-local autocmd needs no group and goes with
  -- its buffer.
  section("hook", function()
    local secret = kit.input({ secret = true, relative = "editor" })
    local found = {}
    for _, a in ipairs(api.nvim_get_autocmds({ buffer = secret.bufnr })) do
      if a.desc == "lib.nvim.ui.kit.input: re-mask secret input" then
        found[#found + 1] = a.event
        eq(a.group_name, nil, a.event .. " is in no group")
      end
    end
    table.sort(found)
    eq(
      table.concat(found, ","),
      "TextChanged,TextChangedI,TextChangedP",
      "buffer-local, on all three"
    )
    secret:close()

    local before = #autocmd.registered()
    local bufnrs = {}
    for i = 1, 5 do
      local s = kit.input({ secret = true, relative = "editor" })
      bufnrs[i] = s.bufnr
      s:close()
    end
    eq(#autocmd.registered(), before, "no record for a throwaway hook")
    for _, b in ipairs(bufnrs) do
      ok(not api.nvim_buf_is_valid(b), "the buffer is wiped, and the hook with it")
      ok(
        not pcall(api.nvim_get_autocmds, { group = "lib_kit_input_" .. b }),
        ("no augroup lib_kit_input_%d is left"):format(b)
      )
    end
  end)
end
