-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_confirm_hotkeys_spec.lua -- every button of a lib.nvim.ui.kit.confirm dialog has a key
-- that picks it at once: y/n on Yes/No (as in the `more` prompt), the first free letter of the label
-- (collisions take the next free letter, left to right, earlier buttons first), else its digit. The
-- key is marked in the button (accent + `KitHotkey` underline, or a superscript digit); the focus
-- still starts on the default and <CR> still confirms it. Text fields get no letter keys.

return function(H)
  local restores = {}
  local function stub(tbl, key, fn)
    restores[#restores + 1] = { tbl, key, tbl[key] }
    tbl[key] = fn
  end
  local ok_body, err_body = pcall(function()
    local kit = require("lib.nvim.ui.kit")
    local confirm = require("lib.nvim.ui.kit.confirm")
    local api = vim.api

    local function eq(actual, expected, msg)
      H.ok(
        vim.deep_equal(actual, expected),
        ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
      )
    end
    local function ok(cond, msg)
      H.ok(cond, msg)
    end

    confirm.close()
    local warnings = {}
    stub(vim, "notify", function(msg)
      warnings[#warnings + 1] = msg
    end)

    --- Open a dialog; returns its answers (`nil` becomes "nil") and its surface.
    local function open(opts)
      local calls = {}
      opts.on_answer = function(v)
        calls[#calls + 1] = v == nil and "nil" or v
      end
      local surf = kit.confirm(opts)
      ok(surf, "the dialog opened")
      return calls, surf
    end

    local function type_keys(keys)
      api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    end

    --- The texts the dialog marks with `group`, in buffer order.
    local function marked(buf, group)
      local out = {}
      for _, m in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        if m[4].hl_group == group then
          out[#out + 1] = api.nvim_buf_get_text(buf, m[2], m[3], m[2], m[4].end_col, {})[1]
        end
      end
      return out
    end

    --- The superscript digits drawn over the buttons, with the byte column they sit at.
    local function superscripts(buf)
      local out = {}
      for _, m in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        if m[4].virt_text then
          out[#out + 1] = { col = m[3], text = m[4].virt_text[1][1] }
        end
      end
      return out
    end

    -- ------------------------------------------------- the example of the task
    local calls, surf =
      open({ question = "Exists.", choices = { "Yes", "No", "Cancel", "Overwrite" }, default = 2 })
    eq(confirm.current_focus(), 2, "the focus starts on the default No")
    eq(marked(surf.bufnr, "KitHotkey"), { "Y", "N", "C", "O" }, "every button marks its key")
    eq(marked(surf.bufnr, "KitAccent"), { "Y", "N", "C", "O" }, "drawn with the accent too")
    eq(superscripts(surf.bufnr), {}, "no digit where there is a letter")
    type_keys("o")
    eq(calls, { "Overwrite" }, "the first letter picks the button without moving the focus")
    for key, want in pairs({ y = "Yes", n = "No", c = "Cancel", O = "Overwrite" }) do
      calls = open({ question = "Exists.", choices = { "Yes", "No", "Cancel", "Overwrite" } })
      type_keys(key)
      eq(calls, { want }, key .. " picks " .. want)
    end
    calls = open({ question = "Exists.", choices = { "Yes", "No", "Cancel" }, default = 2 })
    type_keys("<CR>")
    eq(calls, { "No" }, "<CR> still confirms the focused button")

    -- ------------------------------------------------- y/n as in `more`
    calls, surf = open({ question = "Sure?" })
    eq(marked(surf.bufnr, "KitHotkey"), { "Y", "N" }, "the Yes/No default marks y and n")
    type_keys("n")
    eq(calls, { false }, "n answers no")
    -- the safe answer first (lib.nvim.ui.dialog.yesno): y and n follow the words, not the places
    calls = open({ question = "Delete?", choices = { "No", "Yes, delete" } })
    type_keys("y")
    eq(calls, { "Yes, delete" }, "y picks the button that starts with Yes")
    calls = open({ question = "Delete?", choices = { "Nope", "Not now", "No" } })
    type_keys("n")
    eq(calls, { "No" }, "n is the word No, not any label that starts with n")
    -- y/n win over a first letter that an earlier button would take
    calls = open({ question = "Q?", choices = { "Yank", "Yes", "Next", "No" } })
    type_keys("y")
    eq(calls, { "Yes" }, "y belongs to Yes even after Yank")
    calls = open({ question = "Q?", choices = { "Yank", "Yes", "Next", "No" } })
    type_keys("a")
    eq(calls, { "Yank" }, "Yank takes its next free letter")
    surf = select(2, open({ question = "Q?", choices = { "Yes", "No" }, legend = true }))
    ok(vim.wo[surf.winid].winbar:find("y/n", 1, true), "the legend shows y/n for Yes/No labels")
    confirm.cancel()

    -- ------------------------------------------------- collisions
    -- Cancel takes c; Close: c taken, l moves focus, o is free; Copy: c and o taken, p is free.
    calls, surf = open({ question = "Q?", choices = { "Cancel", "Close", "Copy" } })
    eq(marked(surf.bufnr, "KitHotkey"), { "C", "o", "p" }, "the letter each button got is marked")
    type_keys("p")
    eq(calls, { "Copy" }, "p picks Copy")
    calls = open({ question = "Q?", choices = { "Cancel", "Close", "Copy" } })
    type_keys("o")
    eq(calls, { "Close" }, "o picks Close")
    calls = open({ question = "Q?", choices = { "Cancel", "Close", "Copy" } })
    type_keys("l")
    eq(confirm.current_focus(), 2, "l still moves the focus")
    eq(calls, {}, "and answers nothing")
    confirm.cancel()
    -- the same labels give the same keys every time
    for _ = 1, 3 do
      surf = select(2, open({ question = "Q?", choices = { "Cancel", "Close", "Copy" } }))
      eq(marked(surf.bufnr, "KitHotkey"), { "C", "o", "p" }, "deterministic")
      confirm.cancel()
    end

    -- an & letter that is refused falls back to a free letter of its label
    warnings = {}
    calls, surf = open({ question = "Q?", choices = "&Help\n&Save" })
    eq(#warnings, 1, "the refused & letter is still reported")
    eq(marked(surf.bufnr, "KitHotkey"), { "e", "S" }, "Help shows its fallback letter")
    type_keys("e")
    eq(calls, { "Help" }, "and answers to it")
    -- an & letter keeps its own place in the label even when an earlier letter would do
    surf = select(2, open({ question = "Q?", choices = "Re&name\n&Cancel" }))
    eq(marked(surf.bufnr, "KitHotkey"), { "n", "C" }, "the & letter is the one marked")
    confirm.cancel()

    -- ------------------------------------------------- no free letter: a digit
    calls, surf = open({ question = "Q?", choices = { "Ok", "Ko", "?!" } })
    eq(marked(surf.bufnr, "KitHotkey"), { "O", "K" }, "Ok o, Ko k")
    local sup = superscripts(surf.bufnr)
    eq(#sup, 1, "one superscript, for the button without a letter")
    eq(sup[1].text, "³", "its digit")
    local r = confirm.button_ranges()[3]
    eq(sup[1].col, r.end_col - 2, "drawn in the space before ]")
    local line = api.nvim_buf_get_lines(surf.bufnr, r.row, r.row + 1, false)[1]
    eq(line:sub(r.start_col + 1, r.end_col), "[ ?! ]", "the box keeps its text and its size")
    type_keys("3")
    eq(calls, { "?!" }, "the digit picks it")
    -- every button keeps its digit, also one with a letter
    calls = open({ question = "Q?", choices = { "Ok", "Ko", "?!" } })
    type_keys("2")
    eq(calls, { "Ko" }, "2 picks the second button")

    -- a 0-5 scale: every digit label owns its digit, 0 included
    local scale = { "0", "1", "2", "3", "4", "5" }
    for _, want in ipairs(scale) do
      calls = open({ question = "Rate?", choices = scale })
      type_keys(want)
      eq(calls, { want }, want .. " picks the button labelled " .. want)
    end
    surf = select(2, open({ question = "Rate?", choices = scale }))
    eq(marked(surf.bufnr, "KitHotkey"), scale, "every digit label is marked")
    confirm.cancel()
    -- a letterless button whose place digit a digit label owns takes the first free digit
    calls, surf = open({ question = "Q?", choices = { "-", "1" } })
    sup = superscripts(surf.bufnr)
    eq(#sup, 1, "the letterless button shows a digit")
    eq(sup[1].text, "³", "the first free one (1 is the label's, 2 is the place of button 2)")
    type_keys("3")
    eq(calls, { "-" }, "and answers to it")
    calls = open({ question = "Q?", choices = { "-", "1" } })
    type_keys("1")
    eq(calls, { "1" }, "1 still picks the button labelled 1")
    -- past the ninth: the tenth letterless button gets 0, the eleventh only h/l
    local many = {}
    for i = 1, 11 do
      many[i] = "#" .. i
    end
    calls, surf = open({ question = "Q?", choices = many })
    sup = superscripts(surf.bufnr)
    eq(#sup, 10, "ten buttons show a digit")
    local texts = vim.tbl_map(function(s)
      return s.text
    end, sup)
    ok(vim.tbl_contains(texts, "⁰"), "the tenth shows 0")
    type_keys("0")
    eq(calls, { many[10] }, "0 picks the tenth button")

    -- the marks survive moving the focus
    surf = select(2, open({ question = "Q?", choices = { "Ok", "Ko", "?!" } }))
    confirm.move(1)
    confirm.move(1)
    eq(#marked(surf.bufnr, "KitHotkey"), 2, "letter marks after the focus moved")
    eq(#superscripts(surf.bufnr), 1, "and the digit")
    confirm.cancel()

    -- ------------------------------------------------- the theme token
    eq(api.nvim_get_hl(0, { name = "KitHotkey" }).underline, true, "KitHotkey is an underline")
    local theme = require("lib.nvim.ui.kit.theme")
    theme.materialize(theme.resolve({ hl = { hotkey = { bold = true } } }))
    local spec = api.nvim_get_hl(0, { name = "KitHotkey" })
    eq({ spec.bold, spec.underline }, { true, true }, "an override adds to the underline")
    theme.materialize(theme.resolve())

    -- ------------------------------------------------- a text field gets no letter keys
    kit.form({
      back = true,
      fields = { { name = "a", label = "Yes or No" }, { name = "b", label = "B" } },
      on_submit = function() end,
      on_cancel = function() end,
    })
    local buf = api.nvim_get_current_buf()
    for _, key in ipairs({ "y", "n", "c", "o", "1" }) do
      for _, mode in ipairs({ "n", "i" }) do
        local m = vim.fn.maparg(key, mode, false, true)
        ok(
          not (m.buffer == 1 and m.lhs == key),
          ("%s is not mapped in the field (%s mode)"):format(key, mode)
        )
      end
    end
    api.nvim_buf_set_lines(buf, 0, 1, false, { "yes" })
    type_keys("<Esc>")
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end)
  for i = #restores, 1, -1 do
    local r = restores[i]
    r[1][r[2]] = r[3]
  end
  require("lib.nvim.ui.kit.confirm").close()
  if not ok_body then
    error(err_body, 0)
  end
end
