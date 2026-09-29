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

  -- :messages: NOT written by default (since 2026-09-29 -- every
  -- popup-delivered message is unconditionally in the popup's own history
  -- regardless, see above; real :messages briefly echoes as it records,
  -- see write_messages()'s own doc comment for why that could not be
  -- avoided, which is exactly why it is opt-in rather than the default).
  -- Written on request, and never blocks on a --More-- prompt even for a
  -- long/multi-line message when it is ('more' is toggled off for the call).
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
    popup.deliver("quiet by default\nline two", vim.log.levels.ERROR, { source = "spec" })
    ok(not hist_has("quiet by default"), "NOT written to :messages by default")
    ok(#popup.history() > 0, "but always in the popup's own history regardless")

    vim.cmd("messages clear")
    popup.deliver("shown here", vim.log.levels.INFO, { source = "spec", messages = true })
    ok(hist_has("shown here"), "per-call messages = true opts into :messages")

    popup.setup({ messages = true })
    popup.deliver("global on", vim.log.levels.INFO)
    ok(hist_has("global on"), "setup({ messages = true }) changes the default")
    popup.deliver("call wins", vim.log.levels.INFO, { messages = false })
    ok(not hist_has("call wins"), "a per-call value beats the module default")
    popup.setup({ messages = false })
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
  popup.setup({ messages = false })

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
      popup.deliver(
        "float open, still delivered",
        vim.log.levels.ERROR,
        { source = "spec", messages = true }
      )
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
      popup.deliver(("line\n"):rep(500), vim.log.levels.INFO, { source = "spec", messages = true })
    end)
    eq(vim.o.more, true, "'more' is restored to what it was, not left toggled off")
    vim.o.more = more_before
  end
  popup.clear()

  -- toast_min_level: below it, the message is recorded but no toast (or
  -- vim.notify fallback) is shown -- only the popup's own history (and
  -- real :messages too, if opted in).
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

  -- Regression: clear(source) used to leave last_entry pointing at an
  -- already-cleared message when the last delivery's source matched the
  -- filter -- expand_last()/`:Lib notify last` would still show something
  -- the caller just asked to forget.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function()
        return {}
      end,
    },
  }, function()
    popup.deliver("hello", vim.log.levels.INFO, { source = "foo", messages = false })
  end)
  popup.clear("foo")
  ok(pcall(popup.expand_last), "expand_last() after clearing its own source does not error")
  local viewer_opened_after_clear
  with_stubs({
    ["lib.nvim.ui.kit.viewer"] = {
      open = function(o)
        viewer_opened_after_clear = o
      end,
    },
  }, function()
    popup.expand_last()
  end)
  eq(
    viewer_opened_after_clear,
    nil,
    "clear(source) forgets last_entry too when it belongs to that source"
  )
  popup.clear()

  -- Regression: wrap() (via deliver()/show_toast()) used to silently lose
  -- the whole message when max_lines was configured down to 0 -- a
  -- 0-length vim.list_slice() left the truncation marker written to
  -- out[0], invisible to ipairs/#. max_lines is now clamped to at least 1.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("hello world", vim.log.levels.INFO, { max_lines = 0, messages = false })
    eq(#opened.message, 1, "max_lines = 0 is clamped to 1, not silently emptied")
    ok(opened.message[1] ~= nil and opened.message[1] ~= "", "and that one line is not blank")
  end)
  popup.clear()

  -- opts.title overrides the default "source level-name" toast title, and
  -- also reaches the plain vim.notify fallback (a rich backend -- ui.notify,
  -- nvim-notify, noice -- can still render it there).
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("hi", vim.log.levels.INFO, { title = "custom title", messages = false })
    eq(opened.title, "custom title", "opts.title overrides the default toast title")
  end)
  local fallback_notify_opts
  local original_notify = vim.notify
  vim.notify = function(_, _, notify_opts)
    fallback_notify_opts = notify_opts
  end
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function()
        error("no ui")
      end,
    },
  }, function()
    popup.deliver("hi", vim.log.levels.INFO, { title = "custom title", messages = false })
  end)
  vim.notify = original_notify
  eq(
    fallback_notify_opts and fallback_notify_opts.title,
    "custom title",
    "opts.title also reaches the plain vim.notify fallback"
  )
  popup.clear()

  -- Without an explicit opts.title, a multi-line message's own first line
  -- becomes the toast title (e.g. a git error's "repo: push failed" summary
  -- instead of it being buried in the body next to git's own hint lines);
  -- the body then starts from line 2.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(
      "docmap-desktop: push failed\n! [rejected] main -> main\nhint: pull first",
      vim.log.levels.ERROR,
      { source = "[gitsuite]", messages = false }
    )
    eq(opened.title, "[gitsuite] docmap-desktop: push failed", "first line becomes the title")
    eq(opened.message[1], "! [rejected] main -> main", "body starts from the second line")
    eq(opened.message[2], "hint: pull first", "and keeps the rest")
  end)
  popup.clear()

  -- A single-line message has nothing to split off: falls back to the
  -- unchanged "source level-name" title, same as before this feature existed.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("just one line", vim.log.levels.INFO, { source = "spec", messages = false })
    eq(opened.title, "spec info", "single-line message keeps the default title")
    eq(opened.message[1], "just one line", "and the body is the whole message")
  end)
  popup.clear()

  -- Regression guard: a message that is one huge unbroken "line" plus
  -- deliver()'s own entry_max_bytes truncation marker ("\n... (truncated)")
  -- technically contains a newline too, but the text before it is nowhere
  -- near title-shaped -- this must NOT be split into a 64KB "title" and a
  -- one-line "... (truncated)" body; the default title stays.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("y"):rep(100000), vim.log.levels.INFO, { source = "spec" })
    eq(opened.title, "spec info", "an oversized single line is not mistaken for a title")
    eq(
      opened.message[#opened.message],
      "... (:Lib notify last)",
      "the body still shows wrap()'s own cut marker, not deliver()'s truncation text as a lone line"
    )
  end)
  popup.clear()

  -- Regression: notify.create(prefix, { source = ... }) bakes `prefix` into
  -- every message BEFORE popup.deliver ever sees it (notifier.notify does
  -- `prefix .. msg`) -- so the first line already carries the tag, and
  -- derive_title used to re-prepend `source` in front of it too, producing
  -- "gitsuite [gitsuite] push failed" instead of the clean title. Exercised
  -- through the real create() -> deliver() path, not a direct popup.deliver
  -- call, since that's what actually reproduced it.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local n = require("lib.nvim.notify").create("[gitsuite]", { popup = true, source = "gitsuite" })
    n.error("push failed\n! [rejected] main -> main\nhint: pull first")
    eq(
      opened.title,
      "[gitsuite] push failed",
      "source is not re-prepended when the message's own first line already carries it"
    )
  end)
  popup.clear()

  -- The un-decorated case still gets its source prepended normally: a
  -- first line that does NOT already carry the tag (e.g. a raw
  -- popup.deliver call, no notify.create() prefix involved).
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("unrelated first line\nmore detail", vim.log.levels.ERROR, {
      source = "gitsuite",
      messages = false,
    })
    eq(
      opened.title,
      "gitsuite unrelated first line",
      "source IS prepended when the first line doesn't already carry it"
    )
  end)
  popup.clear()

  -- Regression: the TITLE_MAX_WIDTH check used to measure only first_line's
  -- own width, then concatenate an unmeasured source prefix in front of the
  -- (already fitted) result -- so the combined title could still overflow
  -- the toast's ~40-column title bar. The budget must cover prefix + line
  -- together, with the prefix kept whole and first_line truncated into
  -- whatever room is left.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local long_source = "lib.nvim.bindings.usercmd.composer" -- 35 display columns
    popup.deliver(
      "a fairly long summary line that fills most of the budget\nmore detail",
      vim.log.levels.ERROR,
      { source = long_source, messages = false }
    )
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      ("combined title %q (%d cols) fits the 40-column toast title bar"):format(
        opened.title,
        vim.fn.strdisplaywidth(opened.title)
      )
    )
    ok(
      vim.startswith(opened.title, long_source .. " "),
      "the source prefix itself is kept whole, not truncated"
    )
  end)
  popup.clear()

  -- Regression: the first "already tagged" check compared a fuzzy
  -- alphanumeric "core" of `source` against the start of `first_line` --
  -- which meant a direct popup.deliver() call (baked_prefix never set,
  -- nothing was ever actually baked in) could still have its LEGITIMATE
  -- source prefix silently stripped, purely because the message's own
  -- wording happened to start with similar-looking text. The exact
  -- baked_prefix match must not misfire here: source is always added
  -- when nothing was actually baked in.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("Gitsuite failed to load\nsee logs for details", vim.log.levels.ERROR, {
      source = "gitsuite",
      messages = false,
    })
    eq(
      opened.title,
      "gitsuite Gitsuite failed to load",
      "source is still prepended even when the message's own wording coincidentally "
        .. "resembles it -- nothing was actually baked in here"
    )
  end)
  popup.clear()

  -- Regression: a `source` whose OWN display width is already at or past
  -- TITLE_MAX_WIDTH used to be kept "whole" unconditionally, so the
  -- combined title could overflow the 40-column budget regardless of
  -- first_line -- the prefix itself must be truncated in that case.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local huge_source = ("very-long-source-tag-"):rep(3) -- 66 display columns
    popup.deliver("first line\nmore detail", vim.log.levels.ERROR, {
      source = huge_source,
      messages = false,
    })
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      ("title %q (%d cols) fits the 40-column budget even when source alone overflows it"):format(
        opened.title,
        vim.fn.strdisplaywidth(opened.title)
      )
    )
  end)
  popup.clear()

  -- Regression: the truncation used to size a plain vim.fn.strcharpart cut
  -- from a display-width budget -- a CHARACTER count standing in for a
  -- COLUMN count. For a source made of double-width characters (CJK,
  -- emoji, ...) that silently let up to 2x the intended budget through.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local cjk_source = ("字"):rep(30) -- 30 chars, 60 display columns
    popup.deliver("first line\nmore detail", vim.log.levels.ERROR, {
      source = cjk_source,
      messages = false,
    })
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      ("title %q (%d cols) fits the 40-column budget for a double-width source too"):format(
        opened.title,
        vim.fn.strdisplaywidth(opened.title)
      )
    )
  end)
  popup.clear()

  -- Regression: the SINGLE-LINE fallback title ("source level-name") had no
  -- width bound at all -- predates every derive_title change this session,
  -- caught only on a third verification pass. A long or wide `source` here
  -- (the most common notify shape: a plain single-line message) must fit
  -- the same 40-column budget the multi-line path already enforces.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local long_source = "a-very-long-plugin-name-that-exceeds-the-forty-column-budget-easily"
    popup.deliver("connection refused", vim.log.levels.ERROR, {
      source = long_source,
      messages = false,
    })
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      ("single-line fallback title %q (%d cols) fits the 40-column budget"):format(
        opened.title,
        vim.fn.strdisplaywidth(opened.title)
      )
    )
    ok(vim.endswith(opened.title, "error"), "the level name itself is kept whole, not truncated")
  end)
  popup.clear()

  -- Same fallback path, a double-width (CJK) source this time.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local cjk_source = ("字"):rep(41) -- 82 display columns
    popup.deliver("connection refused", vim.log.levels.ERROR, {
      source = cjk_source,
      messages = false,
    })
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      (
        "single-line fallback title %q (%d cols) fits the 40-column budget for a "
        .. "double-width source too"
      ):format(opened.title, vim.fn.strdisplaywidth(opened.title))
    )
  end)
  popup.clear()

  -- Regression: truncation used to measure width via vim.fn.strdisplaywidth
  -- (authoritative) but CUT via lib.lua.strings.width.truncate(), whose
  -- hand-maintained Unicode-width table is a deliberate approximation and
  -- disagreed with strdisplaywidth for some double-width codepoints outside
  -- it (newer emoji blocks) -- so a "truncated" title could still overflow
  -- the budget it was measured against. Both measuring and cutting now go
  -- through vim.fn exclusively (same pair wrap() already uses).
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local melting_face = "\u{1FAE0}" -- outside strwidth's WIDE_RANGES table; strdisplaywidth=2
    local emoji_source = melting_face:rep(30)
    popup.deliver("connection refused", vim.log.levels.ERROR, {
      source = emoji_source,
      messages = false,
    })
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      (
        "fallback title %q (%d cols) fits the 40-column budget for an emoji "
        .. "source outside the old approximation table"
      ):format(opened.title, vim.fn.strdisplaywidth(opened.title))
    )
  end)
  popup.clear()

  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local melting_face = "\u{1FAE0}"
    local emoji_source = melting_face:rep(30)
    popup.deliver("first line\nmore detail", vim.log.levels.ERROR, {
      source = emoji_source,
      messages = false,
    })
    ok(
      vim.fn.strdisplaywidth(opened.title) <= 40,
      (
        "multi-line title %q (%d cols) fits the 40-column budget for an emoji "
        .. "source outside the old approximation table"
      ):format(opened.title, vim.fn.strdisplaywidth(opened.title))
    )
  end)
  popup.clear()

  -- Regression: truncate_to_width() used to sum each character's width IN
  -- ISOLATION, which double-counts a combining mark (it has a real width
  -- alone but contributes 0 once attached to its base character) -- both
  -- under-filling the budget by roughly half for NFD-decomposed accented
  -- text, and risking a cut landing between a base character and its own
  -- mark. Measuring the growing prefix's own real width fixes both.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local decomposed_e = "e\u{0301}" -- NFD: "e" + combining acute accent
    local accented_source = decomposed_e:rep(10) -- 10 display columns, NOT 20 -- well
    -- under budget together with "first line" below, so nothing here should
    -- be truncated at all: this test is purely about the accents surviving.
    popup.deliver("first line\nmore detail", vim.log.levels.ERROR, {
      source = accented_source,
      messages = false,
    })
    -- Well under the 40-column budget -- nothing here should be truncated
    -- at all, so every accent must survive intact.
    eq(
      opened.title,
      accented_source .. " first line",
      "a combining-mark sequence within budget is not corrupted or "
        .. "needlessly shortened by the width measurement"
    )
  end)
  popup.clear()

  -- Regression: derive_title()'s argument-table construction (which calls
  -- derive_title itself) runs BEFORE show_toast()'s own pcall(toast.open,
  -- {...}) ever starts -- Lua evaluates table-constructor expressions
  -- first -- so a non-string opts.source used to crash deliver() outright
  -- instead of degrading to the plain level-name title like every other
  -- malformed input in this module already does.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local delivered_ok = pcall(popup.deliver, "first line\nmore detail", vim.log.levels.ERROR, {
      source = true, ---@diagnostic disable-line: assign-type-mismatch
      messages = false,
    })
    ok(delivered_ok, "a non-string opts.source does not crash delivery")
    eq(opened.title, "error", "falls back to the bare level name instead of crashing")
  end)
  popup.clear()

  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local delivered_ok = pcall(popup.deliver, "first line\nmore detail", vim.log.levels.ERROR, {
      source = "gitsuite",
      baked_prefix = 42, ---@diagnostic disable-line: assign-type-mismatch
      messages = false,
    })
    ok(delivered_ok, "a non-string baked_prefix does not crash delivery either")
    ok(opened.title ~= nil, "...and a toast still opens")
  end)
  popup.clear()

  -- Regression: wrap()'s line-splitting used to size its width-budget cut
  -- point in CHARACTERS ("cut = width", then strcharpart(line, 0, width)),
  -- but `width` is a COLUMN budget -- the same confusion truncate_to_width()
  -- (the toast TITLE's own truncation) had five fix rounds ago, just never
  -- applied to wrap()'s BODY text. For double-width text (CJK, many emoji)
  -- that let each wrapped line run up to twice the intended column width.
  -- Default width is 38 columns; a long unbroken run of double-width
  -- characters has no spaces to break on either, so this exercises the raw
  -- column-budget cut path directly.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("字"):rep(120), vim.log.levels.INFO, { messages = false })
    ok(#opened.message > 1, "a long CJK run still wraps into several lines")
    for i, line in ipairs(opened.message) do
      ok(
        vim.fn.strdisplaywidth(line) <= 38,
        ("wrapped CJK line %d %q is %d columns wide, over the 38-column budget"):format(
          i,
          line,
          vim.fn.strdisplaywidth(line)
        )
      )
    end
  end)
  popup.clear()

  -- Regression guard: a single character wider than the entire wrap budget
  -- (an unusually narrow `width`) used to leave `cut` at 0 characters. That
  -- does NOT hang -- the pre-existing `if #out > max_lines then break end`
  -- inside the same while loop already bounds the iteration count on its
  -- own, regardless of this guard -- it silently DROPS the character
  -- instead: `strcharpart(line, 0)` with cut=0 returns `line` unchanged, so
  -- `line` never shrinks and every iteration appends another "" until the
  -- max_lines cap kicks in and overwrites the lot with the truncation
  -- marker, losing the one character that was supposed to be shown. Taking
  -- the character anyway guarantees `line` actually shrinks each iteration,
  -- so it survives into the output instead of being swallowed.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("字", vim.log.levels.INFO, { width = 1, messages = false })
    eq(
      opened.message[1],
      "字",
      "a character wider than the whole wrap width is still shown, not silently dropped"
    )
  end)
  popup.clear()

  -- Regression: entry_max_bytes truncation cut the raw message with a plain
  -- `message:sub(1, entry_max)`, unaware of UTF-8 character boundaries. For
  -- a multibyte character straddling the cut, that left a lone lead byte (or
  -- a lead byte plus a partial run of continuation bytes) trailing the kept
  -- text, which Neovim then renders as a `<xx>` escape for the orphaned
  -- byte(s) instead of just stopping cleanly after the last whole character.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    -- "字" is 3 bytes; a 4-byte cap keeps exactly one whole character (3
    -- bytes) and must not keep a stray leading byte of the second.
    popup.deliver(("字"):rep(5), vim.log.levels.INFO, {
      entry_max_bytes = 4,
      messages = false,
    })
    eq(
      popup.history()[1].message,
      "字\n... (truncated)",
      "the byte cap backs off to the last whole character instead of splitting one in half"
    )
  end)
  popup.clear()

  -- Regression: toast_max_bytes had the identical byte-unaware
  -- `text:sub(1, max_bytes)` cut inside wrap(). Picking a width that forces
  -- a second output line keeps the first line (the one that actually
  -- crosses the byte cap) unmodified by the "... (:Lib notify last)" marker
  -- wrap() always stamps over the LAST line once truncated -- so the first
  -- line's own bytes are directly inspectable here.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    -- 50 bytes backs off to 16 whole "字" (48 bytes); at 20 columns per line
    -- (10 chars of a 2-column character each) that first line is the exact
    -- 30-byte/10-character prefix, with no stray trailing byte.
    popup.deliver(("字"):rep(50), vim.log.levels.INFO, {
      toast_max_bytes = 50,
      width = 20,
      messages = false,
    })
    eq(
      opened.message[1],
      ("字"):rep(10),
      "the toast byte cap backs off to a whole character too, so the surviving first line "
        .. "is not corrupted"
    )
  end)
  popup.clear()

  -- Regression: width_cut_chars() used to be a linear growing-prefix scan
  -- (measure strdisplaywidth of a 1-char prefix, then 2 chars, then 3, ...),
  -- which is O(i) per step and O(n^2) overall. For ordinary text the loop
  -- exits within `width` steps (~38) so this never showed up, but a string
  -- with a long run of ZERO-WIDTH characters (stacked combining marks --
  -- "zalgo text") keeps the running display width under budget for the
  -- whole run, so the fast-path early-return never fires and the scan runs
  -- nearly to the string's full length -- turning one crafted popup.deliver()
  -- call (a git branch name, an LSP diagnostic, ...) into a real multi-second
  -- main-thread stall. The fix binary-searches the cut point instead
  -- (O(log n) probes), which stays fast regardless of how the width is
  -- distributed across the string.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    -- ~40000 bytes of U+0301 COMBINING ACUTE ACCENT (2 bytes each, 0 display
    -- width once attached to a preceding character) followed by one plain
    -- "e" -- display width stays at 1 for nearly the whole 20000-character
    -- run, defeating any fast-path check that looks at the whole string.
    local zalgo = ("\204\129"):rep(20000) .. "e"
    local start = vim.uv.hrtime()
    popup.deliver(zalgo, vim.log.levels.INFO, {
      toast_max_bytes = #zalgo + 10,
      entry_max_bytes = #zalgo + 10,
      messages = false,
    })
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    ok(opened ~= nil, "a long combining-mark run still delivers a toast")
    ok(
      elapsed_ms < 1000,
      (
        "wrapping a %d-character combining-mark run took %.0fms -- width_cut_chars() has "
        .. "regressed back to its old O(n^2) growing-prefix scan"
      ):format(vim.fn.strchars(zalgo), elapsed_ms)
    )
  end)
  popup.clear()

  -- Regression: utf8_safe_cut() used to back off byte-by-byte with no
  -- limit, so a cut point inside a long run of bytes that merely LOOK like
  -- UTF-8 continuation bytes (0x80-0xBF) -- genuinely non-UTF-8 text, e.g.
  -- Latin-1/CP1252 output some Windows tools produce, which this module's
  -- own doc comments cite as a realistic message source -- could walk all
  -- the way back to 0 and silently discard the ENTIRE kept prefix instead
  -- of stopping near the intended byte budget. Bounding the backoff to 3
  -- bytes (the longest a real UTF-8 continuation run can be) and falling
  -- back to the original cut point when no boundary turns up keeps almost
  -- all of the budget instead of losing all of it.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("\128"):rep(70000), vim.log.levels.INFO, {
      entry_max_bytes = 65536,
      messages = false,
    })
    local kept = popup.history()[1].message:gsub("\n%.%.%. %(truncated%)$", "")
    ok(
      #kept >= 65533,
      (
        "non-UTF-8 continuation-byte input kept only %d of the intended 65536 bytes -- "
        .. "the byte cap threw away far more than the 3-byte backoff bound allows"
      ):format(#kept)
    )
  end)
  popup.clear()
end
