-- TESTS/terminal_spawn_spec.lua — lib.nvim.terminal.spawn: the pure parts (geometry, argv), the
-- failure path (no window left behind) and a real short-lived program in a float and a split.

return function(H)
  local eq, ok = H.eq, H.ok
  local spawn = require("lib.nvim.terminal.spawn")

  local function wait_for(pred)
    vim.wait(10000, pred, 10)
    return pred()
  end

  -- geometry and argv are pure
  local g = spawn.float_geometry(200, 50)
  eq(g.width, 180, "geometry: 90% of the columns")
  eq(g.height, 45, "geometry: 90% of the lines")
  eq(g.col, 10, "geometry: centered horizontally")
  eq(g.row, 1, "geometry: centered vertically, one line up for the cmdline")
  eq(spawn.float_geometry(100, 40, 0.5).width, 50, "geometry: ratio")

  eq(spawn.normalize_argv("lazygit")[1], "lazygit", "argv: a string is one program name")
  eq(select(2, spawn.normalize_argv("")), "argv is empty", "argv: empty string is refused")
  eq(select(2, spawn.normalize_argv({})), "argv must be a non-empty list", "argv: empty list")
  eq(select(2, spawn.normalize_argv({ "a", 1 })), "argv holds a non-string", "argv: non-string")
  eq(select(2, spawn.normalize_argv(nil)), "argv must be a non-empty list", "argv: nil")

  -- a program that does not exist: nil + message, nothing left open, on_exit never fires
  local wins, bufs = #vim.api.nvim_list_wins(), #vim.api.nvim_list_bufs()
  local fired = false
  local res, err = spawn.spawn({
    argv = { "lib-nvim-no-such-program-xyz" },
    on_exit = function()
      fired = true
    end,
  })
  eq(res, nil, "missing program: nil")
  ok(err and err:find("lib-nvim-no-such-program-xyz", 1, true), "missing program: names it")
  eq(#vim.api.nvim_list_wins(), wins, "missing program: no window left behind")
  eq(#vim.api.nvim_list_bufs(), bufs, "missing program: no buffer left behind")
  vim.wait(100, function()
    return fired
  end, 10)
  eq(fired, false, "missing program: on_exit never fires")

  -- jobstart returning 0 / -1 instead of throwing: the same clean failure
  for _, rc in ipairs({ 0, -1 }) do
    local r, e
    H.with_patched(vim.fn, "jobstart", function()
      return rc
    end, function()
      r, e = spawn.spawn({ argv = { vim.v.progpath } })
    end)
    eq(r, nil, ("jobstart %d: nil"):format(rc))
    ok(e and e:find("failed to start", 1, true), ("jobstart %d: message"):format(rc))
    eq(#vim.api.nvim_list_wins(), wins, ("jobstart %d: no window left behind"):format(rc))
    eq(#vim.api.nvim_list_bufs(), bufs, ("jobstart %d: no buffer left behind"):format(rc))
  end

  -- a real program, float, close_on_exit = "always"
  local prog = { vim.v.progpath, "--headless", "-u", "NONE", "-c", "cq 3" }
  local code, opened
  local f = spawn.spawn({
    argv = prog,
    title = " t ",
    close_on_exit = "always",
    startinsert = false,
    on_open = function(bufnr, winid, job)
      opened = { bufnr = bufnr, winid = winid, job = job }
    end,
    on_exit = function(c)
      code = c
    end,
  })
  ok(f ~= nil, "float: started")
  eq(opened.winid, f.winid, "float: on_open got the window")
  eq(vim.api.nvim_win_get_config(f.winid).relative, "editor", "float: is a float")
  eq(vim.bo[f.bufnr].buftype, "terminal", "float: the buffer is a terminal")
  ok(
    wait_for(function()
      return code ~= nil
    end),
    "float: on_exit fired"
  )
  eq(code, 3, "float: exit code is passed on")
  ok(
    wait_for(function()
      return not vim.api.nvim_win_is_valid(f.winid)
    end),
    "float: window closed on exit"
  )
  eq(vim.api.nvim_buf_is_valid(f.bufnr), false, "float: the finished terminal buffer is wiped")

  -- split, close_on_exit = "ok" keeps the window of a failing program
  code = nil
  local s = spawn.spawn({
    argv = prog,
    layout = "split",
    size = 8,
    close_on_exit = "ok",
    startinsert = false,
    on_exit = function(c)
      code = c
    end,
  })
  ok(s ~= nil, "split: started")
  eq(vim.api.nvim_win_get_config(s.winid).relative, "", "split: is not a float")
  eq(vim.api.nvim_win_get_height(s.winid), 8, "split: size")
  ok(
    wait_for(function()
      return code ~= nil
    end),
    "split: on_exit fired"
  )
  eq(vim.api.nvim_win_is_valid(s.winid), true, "split: a failing program keeps its window")
  vim.api.nvim_win_close(s.winid, true)
  pcall(vim.api.nvim_buf_delete, s.bufnr, { force = true })

  -- vsplit: size is the width; the window beside it keeps its height
  local orig = vim.api.nvim_get_current_win()
  local orig_height = vim.api.nvim_win_get_height(orig)
  local v = spawn.spawn({ argv = prog, layout = "vsplit", size = 20, startinsert = false })
  ok(v ~= nil, "vsplit: started")
  eq(vim.api.nvim_win_get_width(v.winid), 20, "vsplit: size is the width")
  eq(vim.api.nvim_win_get_height(orig), orig_height, "vsplit: the other window keeps its height")
  wait_for(function()
    return vim.fn.jobwait({ v.job }, 0)[1] ~= -1
  end)
  vim.api.nvim_win_close(v.winid, true)
  pcall(vim.api.nvim_buf_delete, v.bufnr, { force = true })

  -- no room for a split (E36): nil + message, no buffer left behind, no throw
  local extra = {}
  while pcall(vim.cmd, "split") do
    extra[#extra + 1] = vim.api.nvim_get_current_win()
  end
  local bufs_full = #vim.api.nvim_list_bufs()
  local thrown, r_full, e_full = pcall(spawn.spawn, { argv = prog, layout = "split" })
  ok(thrown, "no room: spawn does not throw")
  eq(r_full, nil, "no room: nil")
  ok(e_full and e_full:find("failed to open the window", 1, true), "no room: message")
  eq(#vim.api.nvim_list_bufs(), bufs_full, "no room: no buffer left behind")
  for _, w in ipairs(extra) do
    pcall(vim.api.nvim_win_close, w, true)
  end

  -- on_open throwing: the job is stopped, nothing is left open, nil + message
  local wins_oo = #vim.api.nvim_list_wins()
  local job_oo
  local r_oo, e_oo = spawn.spawn({
    argv = { vim.v.progpath, "--headless", "-u", "NONE", "-c", "sleep 5", "-c", "qa!" },
    startinsert = false,
    on_open = function(_, _, job)
      job_oo = job
      error("boom")
    end,
  })
  eq(r_oo, nil, "on_open throws: nil")
  ok(e_oo and e_oo:find("boom", 1, true), "on_open throws: the error is in the message")
  eq(#vim.api.nvim_list_wins(), wins_oo, "on_open throws: no window left behind")
  eq(vim.fn.jobwait({ job_oo }, 2000)[1] ~= -1, true, "on_open throws: the job is stopped")

  -- close_on_exit with the terminal as the last window: no E444, on_exit still runs
  local last_code
  local errs = {}
  local l
  H.with_patched(vim, "notify", function(msg)
    errs[#errs + 1] = msg
  end, function()
    l = spawn.spawn({
      argv = { vim.v.progpath, "--headless", "-u", "NONE", "-c", "sleep 300m", "-c", "cq 4" },
      layout = "split",
      close_on_exit = "always",
      startinsert = false,
      on_exit = function(c)
        last_code = c
      end,
    })
    vim.cmd("only")
    wait_for(function()
      return last_code ~= nil
    end)
  end)
  ok(l ~= nil, "last window: started")
  eq(last_code, 4, "last window: on_exit runs although the window could not close")
  eq(vim.api.nvim_win_is_valid(l.winid), true, "last window: the window stays")
  vim.cmd("enew")
  pcall(vim.api.nvim_buf_delete, l.bufnr, { force = true })
end
