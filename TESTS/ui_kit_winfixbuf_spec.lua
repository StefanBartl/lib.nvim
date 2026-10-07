-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_winfixbuf_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_winfixbuf_spec.lua (the kit exists twice, see ui.nvim's
-- docs/modules.md): a kit float is one buffer for its whole life. Every kit
-- float's buffer is `bufhidden = "wipe"`, and a key that changes the buffer of the
-- WINDOW (`<C-o>`/`<C-^>` from the jumplist every new float inherits, `:bnext`,
-- `:e`) used to put the user's file into the float and wipe the component's
-- buffer from under it: the window stayed open and no callback was left to fire.
-- `surface.open` sets `winfixbuf`, which turns the swap into E1513.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local api = vim.api

  vim.o.showmode = false

  local function feed(keys)
    -- A refused swap raises E1513 inside the fed keys: that is the point, not a failure.
    pcall(api.nvim_feedkeys, api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  end

  local function close_floats()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end

  -- Two files in the jumplist of the window: a float opened from it inherits it,
  -- so `<C-o>` has somewhere to go.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "a" }, dir .. "/a.txt")
  vim.fn.writefile({ "b" }, dir .. "/b.txt")
  vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/a.txt"))
  vim.cmd("normal! m'")
  vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/b.txt"))
  vim.cmd("normal! m'")

  local done, err = pcall(function()
    -- Every surface, unless the caller says otherwise.
    local s = kit.surface.open({ lines = { "x" } })
    ok(vim.wo[s.winid].winfixbuf, "a surface is winfixbuf")
    local free = kit.surface.open({ lines = { "x" }, wo = { winfixbuf = false } })
    ok(not vim.wo[free.winid].winfixbuf, "wo.winfixbuf = false opts out")
    close_floats()

    -- A sheet on a select row (Normal mode).
    local result
    local sheet = kit.sheet({
      fields = {
        { name = "area", kind = "select", choices = { "Alpha", "Beta" } },
        { name = "title" },
      },
      on_submit = function(v)
        result = v
      end,
      on_cancel = function()
        result = "cancelled"
      end,
    })
    eq(sheet:state().focus, "area", "the focus is on the select row")
    ok(#vim.fn.getjumplist(sheet.winid)[1] >= 2, "the float inherited a jumplist")
    feed("<C-o>")
    ok(api.nvim_buf_is_valid(sheet.bufnr), "<C-o> on a select row keeps the sheet's buffer")
    eq(api.nvim_win_get_buf(sheet.winid), sheet.bufnr, "and the window shows it")
    feed("<Esc>")
    eq(result, "cancelled", "the sheet still answers <Esc>")
    ok(not sheet:is_valid(), "and closes")

    -- A prompt on its button row.
    local cancelled
    local prompt = kit.input({
      buttons = { { id = "submit", label = "OK" }, { id = "skip", label = "Skip" } },
      on_cancel = function()
        cancelled = true
      end,
    })
    feed("<Down>")
    ok(not vim.bo[prompt.bufnr].modifiable, "the focus is on the button row")
    feed("<C-o>")
    feed("<C-^>")
    ok(
      api.nvim_buf_is_valid(prompt.bufnr),
      "<C-o>/<C-^> on the button row keep the prompt's buffer"
    )
    eq(api.nvim_win_get_buf(prompt.winid), prompt.bufnr, "and the window shows it")
    feed("<Esc>")
    ok(cancelled, "the prompt still answers <Esc>")

    -- A prompt whose buffer was swapped by force (another plugin, through the API,
    -- after taking the option off) still answers when its window closes.
    local count = 0
    local forced = kit.input({
      on_cancel = function()
        count = count + 1
      end,
    })
    vim.wo[forced.winid].winfixbuf = false
    api.nvim_win_set_buf(forced.winid, api.nvim_create_buf(true, false))
    ok(not api.nvim_buf_is_valid(forced.bufnr), "the prompt's buffer is wiped")
    api.nvim_win_close(forced.winid, true)
    eq(count, 1, "on_cancel fires once, from the window closing")
  end)

  close_floats()
  vim.cmd("enew")
  vim.cmd("silent! %bwipeout!")
  vim.fn.delete(dir, "rf")
  assert(done, err)
end
