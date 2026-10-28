-- TESTS/terminal_ask_spec.lua — lib.nvim.terminal.ask and its client bin/nvim-ask: a program in a
-- Neovim terminal (a git hook above all) asks that Neovim.
--
-- Two halves:
--   * the Neovim side against a recording `lib.nvim.ui.dialog` double: spec validation, start ->
--     poll -> answer, dismissed and timed-out questions, cancel, a question whose asker stopped
--     polling, the question/choices handed over as data;
--   * a real round trip: `bash bin/nvim-ask` against a separate `nvim --listen` server whose dialog
--     answers by itself (choices with quotes, `$(...)`, backticks and a backslash must come back
--     unchanged; a dismissed question exits 1; no server exits 3; a mute server times out with 2).

return function(H)
  local eq, ok = H.eq, H.ok
  local ask = require("lib.nvim.terminal.ask")

  -- ── Neovim side ──────────────────────────────────────────────────────────────

  local asked = {}
  local fake_dialog = {
    ask = function(opts)
      asked[#asked + 1] = opts
    end,
  }
  local function with_dialog(fn)
    H.with_patched(package.loaded, "lib.nvim.ui.dialog", fake_dialog, fn)
  end
  local function settle()
    vim.wait(50, function()
      return false
    end)
  end

  with_dialog(function()
    local bad = {
      { nil, "spec must be a table" },
      { { question = "", choices = { "a" } }, "non-empty" },
      { { question = "q", choices = {} }, "1 to 9" },
      { { question = "q", choices = { "a", "" } }, "non-empty strings" },
      { { question = { "l1", 2 }, choices = { "a" } }, "lines must be strings" },
    }
    for _, case in ipairs(bad) do
      local raised, err = pcall(ask.start, case[1])
      ok(not raised, "bad spec raises: " .. case[2])
      ok(tostring(err):find(case[2], 1, true), "the message says why: " .. case[2])
    end

    local before = ask.count()
    local id = ask.start({
      question = { "Line one", 'it\'s "two"' },
      choices = { "Commit anyway", "Compress $(x) `y` \\z" },
      title = " pre-commit ",
      default = 2,
      timeout_ms = 5000,
    })
    eq(type(id), "string", "start returns an id")
    eq(ask.poll(id), "", "pending until the dialog has answered")
    settle()
    local o = asked[#asked]
    ok(o, "the question reaches dialog.ask (scheduled)")
    eq(o.question, 'Line one\nit\'s "two"', "question lines joined with newlines, quotes kept")
    eq(o.choices[2], "Compress $(x) `y` \\z", "choices passed as data")
    eq(o.title, " pre-commit ", "title passed")
    eq(o.default, 2, "default passed")
    eq(o.max_wait_ms, 5000, "timeout_ms becomes max_wait_ms")
    eq(o.abandoned(), false, "an asker that polls is not abandoned")
    o.on_answer("Compress $(x) `y` \\z")
    eq(ask.poll(id), "=Compress $(x) `y` \\z", "the answer, prefixed with =")
    eq(ask.poll(id), "!gone", "a fetched answer is forgotten")
    eq(ask.count(), before, "nothing left behind")

    -- dismissed / timed out in Neovim: the dialog answers nil or false
    for _, answer in ipairs({ vim.NIL, false }) do
      local id2 = ask.start({ question = "q", choices = { "a", "b" } })
      settle()
      asked[#asked].on_answer(answer ~= vim.NIL and answer or nil)
      eq(ask.poll(id2), "!cancel", "dismissed answers !cancel (" .. tostring(answer) .. ")")
    end

    -- cancel: the asker gave up
    local id3 = ask.start({ question = "q", choices = { "a" } })
    settle()
    local o3 = asked[#asked]
    eq(ask.cancel(id3), true, "cancel knows the id")
    eq(o3.abandoned(), true, "a cancelled question is abandoned (dropped if still queued)")
    o3.on_answer("a")
    eq(ask.poll(id3), "!gone", "a late answer to a cancelled question goes nowhere")
    eq(ask.cancel("nope"), false, "cancel of an unknown id")

    -- an asker that stopped polling
    local id4 = ask.start({ question = "q", choices = { "a" } })
    settle()
    local o4 = asked[#asked]
    H.with_patched(ask, "STALE_MS", -1, function()
      eq(o4.abandoned(), true, "a question nobody polls is abandoned")
    end)
    ask.cancel(id4)
  end)

  ok(ask.script():match("/bin/nvim%-ask$"), "script() points at bin/nvim-ask")
  eq(vim.fn.filereadable(ask.script()), 1, "script() exists")

  -- ── real round trip ──────────────────────────────────────────────────────────

  local bash = require("lib.nvim.cross.bash").find()
  if not bash then
    H.skipped("terminal_ask: real round trip", "no bash")
    return
  end
  local root = ask.script():gsub("/bin/nvim%-ask$", "")
  local nvim = vim.v.progpath
  local is_win = vim.fn.has("win32") == 1
  local function address(tag)
    local name = ("lib-ask-%s-%d-%d"):format(tag, vim.fn.getpid(), vim.uv.hrtime() % 1000000)
    if is_win then
      return [[\\.\pipe\]] .. name
    end
    return vim.fn.tempname() .. "-" .. name
  end

  -- A server whose dialog answers by itself: choice `pick` after 300 ms (0 = dismiss, -1 = never).
  local function server(pick)
    local addr = address("srv")
    local init = H.tmpfile(".lua")
    vim.fn.writefile({
      ("vim.opt.rtp:prepend(%q)"):format(root),
      "package.loaded['lib.nvim.ui.dialog'] = { ask = function(o)",
      ("  local pick = %d"):format(pick),
      "  if pick < 0 then return end",
      "  vim.defer_fn(function() o.on_answer(pick > 0 and o.choices[pick] or nil) end, 300)",
      "end }",
    }, init)
    local job = vim.system({ nvim, "--clean", "--headless", "--listen", addr, "-u", init })
    local up = vim.wait(15000, function()
      local r =
        vim.system({ nvim, "--clean", "--headless", "--server", addr, "--remote-expr", "1" }):wait()
      return r.code == 0 and vim.trim(r.stdout or "") == "1"
    end, 200)
    ok(up, "the test server comes up")
    return addr, job
  end

  local function client(addr, args)
    local cmd = { bash, root .. "/bin/nvim-ask" }
    vim.list_extend(cmd, args)
    local env = { NVIM_ASK_SERVER = addr or "", NVIM = "", NVIM_ASK_BIN = nvim }
    return vim.system(cmd, { env = env, text = true }):wait(60000)
  end

  local tricky = [[Compress 'it' "now" $(x) `y` \z]]
  local addr, job = server(2)
  local r =
    client(addr, { "--title", " pre-commit ", "Two files\nabove 5 MB", "Commit anyway", tricky })
  eq(r.code, 0, "answered: exit 0 (stderr: " .. tostring(r.stderr) .. ")")
  eq(r.stdout, tricky .. "\n", "the chosen label comes back unchanged")
  job:kill(9)

  addr, job = server(0)
  r = client(addr, { "Question?", "Yes", "No" })
  eq(r.code, 1, "dismissed in Neovim: exit 1")
  job:kill(9)

  addr, job = server(-1)
  r = client(addr, { "--timeout", "1", "Question?", "Yes" })
  eq(r.code, 2, "no answer in time: exit 2")
  job:kill(9)

  r = client(address("none"), { "Question?", "Yes" })
  eq(r.code, 3, "no server there: exit 3")
  r = client(nil, { "Question?", "Yes" })
  eq(r.code, 3, "no address at all: exit 3")
  r = client(nil, { "only a question" })
  eq(r.code, 64, "a question without choices: usage, 64")
  r = client(nil, { "--timeout", "0", "Question?", "Yes" })
  eq(r.code, 64, "--timeout 0 is rejected (would auto-cancel the dialog at once)")
end
