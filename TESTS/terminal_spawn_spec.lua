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
end
