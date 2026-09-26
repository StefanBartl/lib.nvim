-- TESTS/notify_popup_spec.lua — lib.nvim.notify.popup: toast delivery, history,
-- vim.notify fallback, and the `popup` option of notify.create.

return function(H)
  local eq, ok = H.eq, H.ok
  local popup = require("lib.nvim.notify.popup")
  popup.clear()

  local function with_stubs(stubs, fn)
    local saved = {}
    for name, mod in pairs(stubs) do
      saved[name] = package.loaded[name]
      package.loaded[name] = mod
    end
    local good, err = pcall(fn)
    for name in pairs(stubs) do
      package.loaded[name] = saved[name]
    end
    if not good then
      error(err, 0)
    end
  end

  -- No toast available: falls back to vim.notify, still records history.
  local native = {}
  local original = vim.notify
  vim.notify = function(msg, level)
    native[#native + 1] = { msg = msg, level = level }
  end
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function()
        error("no ui")
      end,
    },
  }, function()
    popup.deliver("first\nsecond", vim.log.levels.ERROR, { source = "spec" })
  end)
  vim.notify = original
  eq(#popup.history(), 1, "recorded in the history")
  eq(popup.history()[1].message, "first\nsecond", "verbatim")
  eq(#native, 1, "falls back to vim.notify when no toast can be shown")

  -- Toast path: wrapped, capped, titled with source and level.
  local opened
  with_stubs({
    ["ui.notify"] = {
      is_enabled = function()
        return false
      end,
    },
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("word "):rep(60), vim.log.levels.WARN, { source = "spec" })
    ok(opened, "toast is used")
    ok(#opened.message > 1, "long text is wrapped")
    for _, line in ipairs(opened.message) do
      ok(vim.fn.strdisplaywidth(line) <= 38, "wrapped lines fit")
    end
    eq(opened.title, "spec warn", "title carries source and level")

    popup.deliver(("x\n"):rep(40), vim.log.levels.ERROR)
    eq(#opened.message, 12, "very long text is capped")
  end)

  -- ui.notify active: no second popup, vim.notify handles it.
  native = {}
  opened = nil
  vim.notify = function(msg)
    native[#native + 1] = msg
  end
  with_stubs({
    ["ui.notify"] = {
      is_enabled = function()
        return true
      end,
    },
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("via ui.notify", vim.log.levels.INFO)
  end)
  vim.notify = original
  eq(opened, nil, "no toast when ui.notify already handles vim.notify")
  eq(native[1], "via ui.notify", "handed to vim.notify")

  -- Source filtering.
  eq(#popup.history("spec"), 2, "history filters by source")
  popup.clear("spec")
  eq(#popup.history(), 2, "clear(source) keeps other sources")
  popup.clear()
  eq(#popup.history(), 0, "clear() forgets everything")

  -- notify.create({ popup = true }) routes through deliver with the prefix.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local n = require("lib.nvim.notify").create("[spec]", { popup = true, source = "spec" })
    n.error("boom")
    eq(popup.history("spec")[1].message, "[spec] boom", "prefixed message recorded")
    eq(opened.title, "spec error", "level reflected")
  end)
  popup.clear()

  -- :messages: written by default, off by option, and never blocks on a
  -- --More-- prompt even for a long/multi-line message ('more' is toggled
  -- off for the call) -- see write_messages()'s own doc comment for why it
  -- no longer tries to hide the echo entirely (Neovim has no API for that).
  local function hist_has(text)
    return vim.api.nvim_exec2("messages", { output = true }).output:find(text, 1, true) ~= nil
  end
  vim.cmd("messages clear")
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function()
        return {}
      end,
    },
  }, function()
    popup.deliver("history line one\nline two", vim.log.levels.ERROR, { source = "spec" })
    ok(hist_has("history line one"), "written to :messages by default")

    vim.cmd("messages clear")
    popup.deliver("quiet message", vim.log.levels.INFO, { source = "spec", messages = false })
    ok(not hist_has("quiet message"), "per-call messages = false skips :messages")

    popup.setup({ messages = false })
    popup.deliver("global off", vim.log.levels.INFO)
    ok(not hist_has("global off"), "setup({ messages = false }) changes the default")
    popup.deliver("call wins", vim.log.levels.INFO, { messages = true })
    ok(hist_has("call wins"), "a per-call value beats the module default")
    popup.setup({ messages = true })
  end)
  popup.clear()

  -- deliver must not write its resolved default into the caller's opts table.
  local shared = { source = "spec" }
  popup.setup({ messages = false })
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function()
        return {}
      end,
    },
  }, function()
    popup.deliver("first use", vim.log.levels.INFO, shared)
    eq(shared.messages, nil, "the caller's opts table is left untouched")
  end)
  popup.setup({ messages = true })

  -- A message far larger than a toast: the toast input stays bounded and the
  -- history entry is capped.
  local seen
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        seen = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("y"):rep(200000), vim.log.levels.INFO, { messages = false })
    ok(#seen.message <= 12, "a huge message still fits the line cap")
    eq(seen.message[#seen.message], "... (full text: the popup history)", "and is marked as cut")
  end)
  ok(#popup.history()[1].message <= 64 * 1024 + 32, "history entries are size-capped")
  popup.clear()

  -- Multibyte text is wrapped on characters, not bytes.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        seen = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("äöü "):rep(30), vim.log.levels.INFO, { messages = false })
    for _, line in ipairs(seen.message) do
      ok(vim.fn.strdisplaywidth(line) <= 38, "multibyte lines fit the toast")
    end
  end)
  popup.clear()

  -- Reopening the history must not fail on the buffer name.
  popup.deliver("for the buffer", vim.log.levels.INFO, { messages = false, source = "spec" })
  local first = popup.show_history("spec")
  local second = popup.show_history("spec")
  ok(vim.api.nvim_buf_is_valid(second), "history opens twice in a row")
  ok(not vim.api.nvim_buf_is_valid(first), "the previous history buffer is retired")
  pcall(vim.api.nvim_buf_delete, second, { force = true })
  popup.clear()

  -- Called from a fast event: rescheduled instead of erroring.
  local before = #popup.history()
  vim.uv.new_timer():start(0, 0, function()
    popup.deliver("from a timer", vim.log.levels.INFO, { messages = false })
  end)
  vim.wait(200, function()
    return #popup.history() > before
  end)
  eq(#popup.history(), before + 1, "a delivery from a fast event lands on the main loop")
  popup.clear()

  -- Regression: an earlier `write_messages` attached a throwaway
  -- `vim.ui_attach` to swallow the on-screen echo, which hung indefinitely
  -- once any floating window was already open (vim.ui_attach is documented
  -- experimental/unstable; a `pcall` around it catches errors, not a call
  -- that never returns). A floating window here must not stop delivery from
  -- completing, and the message must still land in `:messages`.
  do
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 10,
      height = 1,
      style = "minimal",
    })
    vim.cmd("messages clear")
    with_stubs({
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function()
          return {}
        end,
      },
    }, function()
      popup.deliver("float open, still delivered", vim.log.levels.ERROR, { source = "spec" })
    end)
    ok(
      hist_has("float open, still delivered"),
      "delivery completes and reaches :messages with a float open"
    )
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  popup.clear()

  -- Regression: write_messages() used to run a hand-built
  -- `:silent! echohl X | echomsg "..." | echohl None` Ex command. `:silent`
  -- only scopes to the FIRST bar-separated command, so `echomsg` ran fully
  -- unsilenced -- every delivery was, in practice, a plain visible echo,
  -- length notwithstanding. A long/multi-line message through that path
  -- (or through a naive nvim_echo call with 'more' left on) would block on
  -- a --More-- prompt. Delivery must never do that, and 'more' must come
  -- back exactly as it was found.
  do
    local more_before = vim.o.more
    vim.o.more = true
    with_stubs({
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function()
          return {}
        end,
      },
    }, function()
      popup.deliver(("line\n"):rep(500), vim.log.levels.INFO, { source = "spec" })
    end)
    eq(vim.o.more, true, "'more' is restored to what it was, not left toggled off")
    vim.o.more = more_before
  end
  popup.clear()
end
