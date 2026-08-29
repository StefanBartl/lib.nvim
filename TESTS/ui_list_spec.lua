-- TESTS/ui_list_spec.lua — lib.nvim.ui.list
-- Quickfix/location list sink: items + title in one call, stack semantics,
-- the open/focus policy, and the empty case.

return function(H)
  local eq, ok = H.eq, H.ok
  local list = require("lib.nvim.ui.list")

  local function items(n)
    local out = {}
    for i = 1, n do
      out[i] = { filename = "spec_file_" .. i .. ".lua", lnum = i, text = "entry " .. i }
    end
    return out
  end

  local function close_lists()
    vim.cmd("silent! cclose")
    vim.cmd("silent! lclose")
  end

  -- Start from a known state: a fresh list stack in a window that is not one.
  vim.cmd("silent! %bwipeout!")
  vim.fn.setqflist({}, "f")
  close_lists()

  -- ------------------------------------------------------------ items+title
  local n = list.qf(items(3), "spec: three", { open = false })
  eq(n, 3, "qf returns the number of entries placed")
  eq(#vim.fn.getqflist(), 3, "entries reached the quickfix list")
  eq(vim.fn.getqflist({ title = 1 }).title, "spec: three", "title set in the same call")

  -- ------------------------------------------------------------ stack: " "
  local before = vim.fn.getqflist({ nr = "$" }).nr
  list.qf(items(1), "spec: pushed", { open = false })
  eq(
    vim.fn.getqflist({ nr = "$" }).nr,
    before + 1,
    "default action pushes a new list, so :colder still reaches the old one"
  )

  -- ------------------------------------------------------------ stack: "r"
  local depth = vim.fn.getqflist({ nr = "$" }).nr
  list.set({ items = items(2), title = "spec: replaced", action = "r", open = false })
  eq(vim.fn.getqflist({ nr = "$" }).nr, depth, "action=r replaces in place, no new list")
  eq(vim.fn.getqflist({ title = 1 }).title, "spec: replaced", "replace still sets the title")
  eq(#vim.fn.getqflist(), 2, "replace swapped the entries")

  -- ------------------------------------------------------------ empty clears
  list.qf({}, "spec: empty", { open = false })
  eq(#vim.fn.getqflist(), 0, "an empty result clears the list rather than leaving stale entries")

  -- ------------------------------------------------------------ open = false
  local function qf_wins()
    local c = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "quickfix" then
        c = c + 1
      end
    end
    return c
  end
  eq(qf_wins(), 0, "open=false opened no window")

  -- ------------------------------------------------------------ open = auto
  list.qf({}, "spec: auto empty", { open = "auto" })
  eq(qf_wins(), 0, "open=auto keeps the window closed when there is nothing to show")

  list.qf(items(2), "spec: auto filled", { open = "auto" })
  eq(qf_wins(), 1, "open=auto opens once there are entries")

  -- ------------------------------------------------------------ focus
  eq(vim.bo[vim.api.nvim_get_current_buf()].buftype, "quickfix", "default focus lands in the list")
  close_lists()

  local source = vim.api.nvim_get_current_win()
  list.qf(items(2), "spec: focus source", { focus = "source" })
  eq(vim.api.nvim_get_current_win(), source, "focus=source hands the cursor back")
  ok(qf_wins() == 1, "focus=source still opened the window")
  close_lists()

  -- ------------------------------------------------------------ height
  list.qf(items(9), "spec: height", { height = 5 })
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "quickfix" then
      eq(vim.api.nvim_win_get_height(w), 5, "height reached :copen")
    end
  end
  close_lists()

  -- ------------------------------------------------------------ location list
  local win = vim.api.nvim_get_current_win()
  local m = list.loc(items(4), "spec: loc", { open = false })
  eq(m, 4, "loc returns its count too")
  eq(#vim.fn.getloclist(win), 4, "entries reached the window's location list")
  eq(vim.fn.getloclist(win, { title = 1 }).title, "spec: loc", "loclist title set")
  eq(#vim.fn.getqflist(), 9, "loc left the quickfix list alone")

  -- an explicit window id is honoured
  vim.fn.setloclist(win, {}, "f")
  list.set({ items = items(1), title = "spec: loc by id", loclist = win, open = false })
  eq(#vim.fn.getloclist(win), 1, "loclist = <winid> targets that window")

  vim.fn.setloclist(win, {}, "f")
  vim.fn.setqflist({}, "f")
  close_lists()
end
