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
    eq(seen.message[#seen.message], "... (:Lib notify last)", "and is marked as cut")
  end)
  ok(#popup.history()[1].message <= 64 * 1024 + 32, "history entries are size-capped")
  popup.clear()

  -- Regression: a raw NUL in the message crosses the vim.fn bridge as a
  -- Blob, and wrap()'s vim.fn.strdisplaywidth call then raises E976 --
  -- deliver() must not lose the message (or itself error) over that.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        seen = o
        return {}
      end,
    },
  }, function()
    local delivered_ok =
      pcall(popup.deliver, "foo\0bar", vim.log.levels.ERROR, { messages = false })
    ok(delivered_ok, "a NUL byte in the message does not raise out of deliver()")
    eq(popup.history()[1].message, "foo\\0bar", "the NUL is replaced with a visible placeholder")
    eq(seen.message[1], "foo\\0bar", "and the toast text is unaffected")
  end)
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

  -- toast_min_level: below it, the message is recorded but no toast (or
  -- vim.notify fallback) is shown -- only history/:messages.
  do
    local shown_native = {}
    vim.notify = function(msg, level)
      shown_native[#shown_native + 1] = { msg = msg, level = level }
    end
    popup.setup({ toast_min_level = vim.log.levels.INFO })
    with_stubs({
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function(o)
          opened = o
          return {}
        end,
      },
    }, function()
      opened = nil
      popup.deliver("too quiet", vim.log.levels.DEBUG, { source = "spec" })
      eq(opened, nil, "below toast_min_level: no toast")
      eq(#shown_native, 0, "below toast_min_level: no vim.notify fallback either")
      eq(popup.history("spec")[1].message, "too quiet", "still recorded in history")

      popup.deliver("loud enough", vim.log.levels.INFO, { source = "spec" })
      ok(opened ~= nil, "at/above toast_min_level: toast shown")
    end)
    vim.notify = original
    popup.clear()
  end

  -- Configurable cap: per-call override and global setup() both work.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("line\n"):rep(20), vim.log.levels.INFO, { max_lines = 3, messages = false })
    eq(#opened.message, 3, "opts.max_lines overrides the toast line cap for this call")

    popup.setup({ max_lines = 2 })
    popup.deliver(("line\n"):rep(20), vim.log.levels.INFO, { messages = false })
    eq(#opened.message, 2, "setup({ max_lines = ... }) changes the default")
    popup.setup({ max_lines = 12 })
  end)
  popup.clear()

  -- expand_last(): opens the last delivered message in full, via the viewer.
  do
    local viewer_opened
    with_stubs({
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function()
          return {}
        end,
      },
      ["lib.nvim.ui.kit.viewer"] = {
        open = function(o)
          viewer_opened = o
        end,
      },
    }, function()
      popup.deliver("a\nb\nc", vim.log.levels.INFO, { source = "spec", messages = false })
      popup.expand_last()
    end)
    eq(
      table.concat(viewer_opened.lines, ","),
      "a,b,c",
      "expand_last shows the full, unwrapped message"
    )
    eq(viewer_opened.title, "spec", "titled with the entry's source")
  end
  popup.clear()

  -- expand_last() with nothing delivered yet is a no-op, not an error.
  ok(pcall(popup.expand_last), "expand_last() with no last entry does not error")

  -- history_full / <C-s>: show_history() collapses long entries by default;
  -- toggle_full() (same effect as the buffer-local <C-s> keymap) expands them.
  do
    popup.deliver(("l\n"):rep(20), vim.log.levels.INFO, { source = "spec", messages = false })
    local buf = popup.show_history("spec")
    local collapsed = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ok(collapsed:match("%+%d+ lines, <C%-s>") ~= nil, "collapsed history marks hidden lines")

    local has_cs = false
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs and m.lhs:lower():find("<c%-s>", 1, false) then
        has_cs = true
      end
    end
    ok(has_cs, "history buffer has a buffer-local <C-s> keymap")

    popup.toggle_full()
    local buf2 = popup.show_history("spec")
    local full = table.concat(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), "\n")
    ok(not full:find("<C%-s>", 1, false), "history_full = true shows entries uncollapsed")
    popup.toggle_full() -- reset to the default (false) for later tests
    pcall(vim.api.nvim_buf_delete, buf2, { force = true })
  end
  popup.clear()

  -- require("lib.nvim.notify").setup({ popup = true }): a notifier created
  -- BEFORE the global default is set still resolves it at call time, not at
  -- create() time (the same load-time-binding trap this module's own docs
  -- warn about, one layer up).
  do
    local notify_mod = require("lib.nvim.notify")
    local n = notify_mod.create("[spec-global]", { source = "spec" }) -- popup left unset
    notify_mod.setup({ popup = true })
    with_stubs({
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function()
          return {}
        end,
      },
    }, function()
      n.info("via global default")
    end)
    eq(
      popup.history("spec")[1].message,
      "[spec-global] via global default",
      "create() resolves the popup default at call time, not at create time"
    )
    notify_mod.setup({ popup = false })
  end
  popup.clear()
end
