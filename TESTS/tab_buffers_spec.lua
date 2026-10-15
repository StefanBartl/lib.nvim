-- TESTS/tab_buffers_spec.lua — lib.nvim.buf_win_tab.tab_buffers: vim.t.bufs -> tabpagebuflist -> windows -> getbufinfo.

return function(H)
  local eq = H.eq
  local tb = require("lib.nvim.buf_win_tab.tab_buffers")

  vim.cmd("silent! only")
  vim.cmd("silent! %bwipeout!")
  local a = vim.api.nvim_create_buf(true, false)
  local b = vim.api.nvim_create_buf(true, false)
  local c = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, a)
  vim.t.bufs = nil

  -- 1) vim.t.bufs wins, in its own order, invalid and duplicate entries dropped
  vim.t.bufs = { c, a, 99999, c, b }
  local list, source = tb.list()
  eq(
    table.concat(list, ","),
    table.concat({ c, a, b }, ","),
    "vim.t.bufs: own order, stale and duplicates dropped"
  )
  eq(source, "vim.t.bufs", "vim.t.bufs: reported as the source")

  -- only stale entries -> falls through to the next step
  vim.t.bufs = { 99998, 99999 }
  list, source = tb.list()
  eq(source, "tabpagebuflist", "all stale: tabpagebuflist answers")
  eq(table.concat(list, ","), tostring(a), "tabpagebuflist: the buffers shown in the tab")

  -- an empty or non-table vim.t.bufs is skipped
  vim.t.bufs = {}
  eq(select(2, tb.list()), "tabpagebuflist", "empty vim.t.bufs: skipped")
  vim.t.bufs = "junk"
  eq(select(2, tb.list()), "tabpagebuflist", "non-table vim.t.bufs: skipped")
  vim.t.bufs = nil
  eq(select(2, tb.list()), "tabpagebuflist", "no vim.t.bufs: skipped")

  -- 2) tabpagebuflist: several windows, one buffer in two of them is listed once
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, b)
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, a)
  list, source = tb.list()
  eq(source, "tabpagebuflist", "windows: tabpagebuflist answers first")
  eq(#list, 2, "tabpagebuflist: a buffer shown twice is listed once")
  eq(vim.tbl_contains(list, a) and vim.tbl_contains(list, b), true, "tabpagebuflist: both buffers")

  -- 3) the windows step answers when tabpagebuflist fails
  local real = vim.fn.tabpagebuflist
  local patched = setmetatable({}, {
    __index = vim.fn,
  })
  patched.tabpagebuflist = function()
    error("simulated")
  end
  H.with_patched(vim, "fn", patched, function()
    list, source = tb.list()
  end)
  eq(source, "windows", "a failing tabpagebuflist falls to the windows step")
  eq(vim.tbl_contains(list, a) and vim.tbl_contains(list, b), true, "windows: the window buffers")
  eq(vim.fn.tabpagebuflist, real, "the patch is gone again")

  -- 4) getbufinfo: nothing from the earlier steps
  local patched2 = setmetatable({}, { __index = vim.fn })
  patched2.tabpagebuflist = function()
    return {}
  end
  local real_tab_list_wins = vim.api.nvim_tabpage_list_wins
  H.with_patched(vim, "fn", patched2, function()
    H.with_patched(vim.api, "nvim_tabpage_list_wins", function()
      return {}
    end, function()
      list, source = tb.list()
    end)
  end)
  eq(source, "getbufinfo", "nothing else: the listed buffers")
  eq(vim.tbl_contains(list, c), true, "getbufinfo: a listed buffer that no window shows")
  eq(vim.api.nvim_tabpage_list_wins, real_tab_list_wins, "the api patch is gone again")

  -- nth
  vim.t.bufs = { c, a, b }
  eq(tb.nth(1), c, "nth: first")
  eq(tb.nth(3), b, "nth: third")
  eq(tb.nth(4), nil, "nth: past the end is nil")
  eq(tb.nth(0), nil, "nth: 0 is nil")
  eq(tb.nth("x"), nil, "nth: not a number is nil")
  vim.t.bufs = nil

  vim.cmd("silent! only")
  vim.cmd("silent! %bwipeout!")
end
