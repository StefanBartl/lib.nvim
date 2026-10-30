-- TESTS/companion_headless_spec.lua — lib.nvim.companion end to end with a REAL companion: a second
-- `nvim --headless` started with vim.system (terminal = false, no window), which connects back over
-- msgpack-RPC. Attach, the pushed content and highlights in its buffer, an update that keeps the
-- cursor, a key-triggered action arriving in the main instance (simulated by calling the client's
-- `send` over the channel), set_title, close (process ends, on_close once), a companion that quits
-- by itself (main detaches; its `_detach` is a notification, so a companion leaving while the main
-- is busy and then closes the handle freezes neither side), a companion whose handle was closed
-- before it attached (quits), and a terminal that never runs the inner nvim (attach timeout).

return function(H)
  local eq, ok = H.eq, H.ok
  local companion = require("lib.nvim.companion")

  local function wait_for(pred, ms)
    vim.wait(ms or 10000, pred, 10)
    return pred()
  end

  ---Keep this instance's loop from running for `ms` (a synchronous stretch, as a DAP step or a
  ---render would be).
  local function busy(ms)
    local t0 = vim.uv.hrtime()
    while vim.uv.hrtime() - t0 < ms * 1e6 do
    end
  end

  ---@param h Lib.Companion.ProtocolHandle
  local function in_companion(h, code, args)
    local rok, res = pcall(vim.rpcrequest, h.chan, "nvim_exec_lua", code, args or {})
    ok(rok, "companion call: " .. tostring(res))
    return res
  end

  -- is_runnable: executable() first; the Windows alias folder only for a bare name
  eq(companion.is_runnable(vim.v.progpath, false), true, "runnable: a program on PATH")
  eq(companion.is_runnable("lib-nvim-no-such-program-xyz", true), false, "runnable: missing")
  eq(companion.is_runnable("no/such/dir/x.exe", true), false, "runnable: a path is not an alias")
  eq(
    companion.is_runnable("lib-nvim-no-such-program-xyz", false),
    false,
    "runnable: no alias off Windows"
  )

  local got = {}
  local closed = 0
  local h, err = companion.open({
    title = "Spec",
    lines = { "alpha", "beta", "gamma" },
    highlights = { { line = 1, col_start = 0, col_end = 2, group = "Title" } },
    filetype = "text",
    terminal = false,
    actions = {
      page = function(delta)
        got[#got + 1] = { "page", delta }
      end,
      jump = function(addr)
        got[#got + 1] = { "jump", addr }
      end,
    },
    keys = { n = { "page", 1 }, a = { "jump", prompt = "Address: " } },
    on_close = function()
      closed = closed + 1
    end,
  })
  ok(h ~= nil, "open: " .. tostring(err))
  eq(h:is_open(), true, "open: open")
  ok(
    wait_for(function()
      return h:is_attached()
    end),
    "attach: the companion connected within 10 s"
  )
  ok(h.chan and h.chan > 0, "attach: a channel back to the companion")

  -- the content arrived
  ok(
    wait_for(function()
      local lines = in_companion(h, "return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      return type(lines) == "table" and lines[1] == "alpha" and #lines == 3
    end),
    "render: the companion shows the lines"
  )
  local state = in_companion(
    h,
    [[local b = vim.api.nvim_get_current_buf()
      local ns = vim.api.nvim_create_namespace("lib.nvim.companion")
      local marks = vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
      return {
        buftype = vim.bo[b].buftype, modifiable = vim.bo[b].modifiable, ft = vim.bo[b].filetype,
        swap = vim.bo[b].swapfile, name = vim.api.nvim_buf_get_name(b), title = vim.o.titlestring,
        marks = #marks, group = marks[1] and marks[1][4].hl_group, q = vim.fn.maparg("q", "n") ~= "",
        n = vim.fn.maparg("n", "n") ~= "", a = vim.fn.maparg("a", "n") ~= "",
      }]]
  )
  eq(state.buftype, "nofile", "companion: nofile buffer")
  eq(state.modifiable, false, "companion: read-only")
  eq(state.swap, false, "companion: no swap")
  eq(state.ft, "text", "companion: filetype")
  ok(state.name:find("companion://Spec", 1, true), "companion: buffer name")
  eq(state.title, "Spec", "companion: title")
  eq(state.marks, 1, "companion: the highlight extmark")
  eq(state.group, "Title", "companion: its group")
  eq(state.q, true, "companion: q is bound")
  eq(state.n, true, "companion: n is bound")
  eq(state.a, true, "companion: a is bound")

  -- an update keeps the cursor line
  in_companion(h, "vim.api.nvim_win_set_cursor(0, { 3, 0 })")
  eq(h:update({ "one", "two", "three", "four" }), true, "update: ok")
  ok(
    wait_for(function()
      local lines = in_companion(h, "return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      return type(lines) == "table" and lines[4] == "four"
    end),
    "update: arrived"
  )
  eq(in_companion(h, "return vim.api.nvim_win_get_cursor(0)[1]"), 3, "update: cursor line kept")
  eq(h:update({ "only" }), true, "update: shorter")
  ok(
    wait_for(function()
      return in_companion(h, "return vim.api.nvim_buf_line_count(0)") == 1
    end),
    "update: shorter arrived"
  )
  eq(in_companion(h, "return vim.api.nvim_win_get_cursor(0)[1]"), 1, "update: cursor clamped")

  -- a key in the companion runs the action here (the client's send, as the keymap calls it)
  in_companion(h, "require('lib.nvim.companion.client').send('page', { 1 })")
  ok(
    wait_for(function()
      return #got == 1
    end),
    "action: arrived in the main instance"
  )
  eq(got[1][1], "page", "action: name")
  eq(got[1][2], 1, "action: fixed argument")
  -- the prompted key: answer the prompt from inside the companion by feeding the keys
  in_companion(
    h,
    [[vim.schedule(function()
        vim.api.nvim_feedkeys("a0x40\r", "tx", false)
      end)]]
  )
  ok(
    wait_for(function()
      return #got == 2
    end),
    "action: the prompted key sent its text"
  )
  eq(got[2][1], "jump", "action: prompted name")
  eq(got[2][2], "0x40", "action: the text typed")

  -- set_title
  eq(h:set_title("Spec 2"), true, "set_title: ok")
  ok(
    wait_for(function()
      return in_companion(h, "return vim.o.titlestring") == "Spec 2"
    end),
    "set_title: arrived"
  )

  -- close: the companion process ends, on_close once
  local chan = h.chan
  h:close()
  eq(h:is_open(), false, "close: closed")
  eq(closed, 1, "close: on_close once")
  ok(
    wait_for(function()
      return vim.tbl_isempty(vim.api.nvim_get_chan_info(chan))
    end),
    "close: the channel is gone"
  )
  eq(#companion.handles(), 0, "close: no handle left")

  -- a companion that quits by itself: the main is TOLD (`_detach` arrives as a notification, not
  -- found by the liveness check), on_close once. The companion's `vim.rpcrequest` is made to
  -- raise first: a `_detach` sent as a blocking request would never arrive then.
  local closed2 = 0
  local h2 = companion.open({
    title = "Spec quit",
    terminal = false,
    on_close = function()
      closed2 = closed2 + 1
    end,
  })
  ok(h2 ~= nil, "quit: opened")
  ok(
    wait_for(function()
      return h2:is_attached()
    end),
    "quit: attached"
  )
  in_companion(h2, "vim.rpcrequest = function() error('a blocking request to the main') end")
  local detached = 0
  local orig_detach = companion._detach
  H.with_patched(companion, "_detach", function(id)
    detached = detached + 1
    return orig_detach(id)
  end, function()
    in_companion(h2, "vim.schedule(function() vim.cmd('qa!') end)")
    wait_for(function()
      return closed2 == 1
    end)
  end)
  eq(closed2, 1, "quit: the handle is closed")
  eq(detached, 1, "quit: the main was told by a notification (no blocking request)")
  eq(h2:is_open(), false, "quit: closed")
  eq(#companion.handles(), 0, "quit: no handle left")

  -- the deadlock case: the companion leaves while this instance is busy, so its `_detach` waits
  -- in the queue; this instance then closes the handle. With a blocking quit request on one
  -- channel and a blocking `_detach` request on the other, neither side would ever answer.
  local closed4 = 0
  local h4 = companion.open({
    title = "Spec busy",
    terminal = false,
    on_close = function()
      closed4 = closed4 + 1
    end,
  })
  ok(h4 ~= nil, "busy: opened")
  ok(
    wait_for(function()
      return h4:is_attached()
    end),
    "busy: attached"
  )
  in_companion(h4, "vim.defer_fn(function() vim.cmd('qa!') end, 20)")
  busy(300)
  local t0 = vim.uv.hrtime()
  h4:close()
  ok((vim.uv.hrtime() - t0) / 1e6 < 2000, "busy: close returned (no deadlock)")
  eq(h4:is_open(), false, "busy: closed")
  eq(closed4, 1, "busy: on_close once")
  wait_for(function()
    return false
  end, 300)
  eq(closed4, 1, "busy: the late _detach does not call on_close again")
  eq(#companion.handles(), 0, "busy: no handle left")

  -- a terminal that never runs the inner nvim (here: an nvim that runs an empty script and
  -- ignores the rest of its argv): the handle is closed after attach_timeout, on_close once
  local noop = H.tmpfile(".lua")
  local f = assert(io.open(noop, "w"))
  f:write("-- nothing\n")
  f:close()
  local closed5 = 0
  local notes = {}
  local h5
  H.with_patched(vim, "notify", function(msg)
    notes[#notes + 1] = msg
  end, function()
    h5 = companion.open({
      title = "Spec late",
      terminal = { vim.v.progpath, "--headless", "--clean", "-l", noop, "{cmd}" },
      attach_timeout = 500,
      on_close = function()
        closed5 = closed5 + 1
      end,
    })
    ok(h5 ~= nil, "late: opened")
    eq(h5:is_open(), true, "late: pending")
    ok(
      wait_for(function()
        return not h5:is_open()
      end, 5000),
      "late: closed by the attach timeout"
    )
  end)
  os.remove(noop)
  eq(closed5, 1, "late: on_close once")
  ok(notes[1] and notes[1]:find("Spec late", 1, true), "late: the warning names it")
  eq(#companion.handles(), 0, "late: no handle left")

  -- closed before it attached: the companion is told so when it reports in and quits
  local closed3 = 0
  local h3 = companion.open({
    title = "Spec early",
    terminal = false,
    on_close = function()
      closed3 = closed3 + 1
    end,
  })
  ok(h3 ~= nil, "early: opened")
  h3:close()
  eq(closed3, 1, "early: on_close")
  eq(h3:is_open(), false, "early: closed")
  local cfg = companion._attach(h3.id, "whatever")
  eq(cfg.closed, true, "early: a late attach is told to quit")
  eq(#companion.handles(), 0, "early: no handle left")
end
