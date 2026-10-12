-- TESTS/messages_spec.lua — lib.nvim.messages: push/snapshot ordering,
-- replace_last, the ring cap, since_ms/until_ms/kinds/levels filtering,
-- on_message/off_message, and notify.popup's push-on-deliver hook. The
-- ext_messages attach/detach policy itself needs a real TUI (the spike this
-- module is built from found headless tests unreliable for it) -- not
-- covered here.

return function(H)
  local eq, ok = H.eq, H.ok

  local function fresh_messages()
    package.loaded["lib.nvim.messages"] = nil
    local messages = require("lib.nvim.messages")
    messages.setup({ ring_size = 1000 })
    return messages
  end

  -- push/snapshot: basic ordering, oldest first.
  do
    local messages = fresh_messages()
    messages.push({ content = "first" })
    messages.push({ content = "second" })
    local snap = messages.snapshot()
    eq(#snap, 2, "both entries present")
    eq(snap[1].content, "first", "oldest first")
    eq(snap[2].content, "second", "newest last")
    eq(snap[1].kind, "notify", "default kind is notify")
    eq(snap[1].level, vim.log.levels.INFO, "default level is INFO")
  end

  -- replace_last: overwrites instead of appending.
  do
    local messages = fresh_messages()
    messages.push({ content = "search: foo" })
    messages.push({ content = "3 matches", replace_last = true })
    local snap = messages.snapshot()
    eq(#snap, 1, "replace_last overwrote, did not append")
    eq(snap[1].content, "3 matches", "the replacement content won")
  end

  -- replace_last with nothing to replace: behaves like a normal push.
  do
    local messages = fresh_messages()
    messages.push({ content = "only", replace_last = true })
    eq(#messages.snapshot(), 1, "replace_last on an empty ring just appends")
  end

  -- Ring cap: oldest entries drop once ring_size is exceeded.
  do
    local messages = fresh_messages()
    messages.setup({ ring_size = 3 })
    for i = 1, 5 do
      messages.push({ content = "m" .. i })
    end
    local snap = messages.snapshot()
    eq(#snap, 3, "capped at ring_size")
    eq(snap[1].content, "m3", "oldest two were dropped")
    eq(snap[3].content, "m5", "newest kept")
  end

  -- The ring is a true circular buffer: it keeps working correctly across
  -- many wraps, not just the first eviction.
  do
    local messages = fresh_messages()
    messages.setup({ ring_size = 3 })
    for i = 1, 10 do
      messages.push({ content = "m" .. i })
    end
    local snap = messages.snapshot()
    eq(#snap, 3, "still capped at ring_size after many wraps")
    eq(snap[1].content, "m8", "oldest surviving entry")
    eq(snap[2].content, "m9", "middle entry")
    eq(snap[3].content, "m10", "newest kept")
  end

  -- replace_last still replaces the newest slot correctly after the ring
  -- has wrapped around at least once.
  do
    local messages = fresh_messages()
    messages.setup({ ring_size = 3 })
    for i = 1, 4 do
      messages.push({ content = "m" .. i }) -- m1 evicted; ring holds m2,m3,m4
    end
    messages.push({ content = "m4-replaced", replace_last = true })
    local snap = messages.snapshot()
    eq(#snap, 3, "replace_last does not grow the ring")
    eq(snap[1].content, "m2", "oldest unaffected")
    eq(snap[2].content, "m3", "middle unaffected")
    eq(snap[3].content, "m4-replaced", "newest slot was replaced, not appended")
  end

  -- Changing ring_size via setup() resets the ring instead of leaving
  -- indices computed for the old size.
  do
    local messages = fresh_messages()
    messages.setup({ ring_size = 2 })
    messages.push({ content = "a" })
    messages.push({ content = "b" })
    messages.setup({ ring_size = 5 })
    eq(#messages.snapshot(), 0, "ring_size change resets the buffer")
    messages.push({ content = "c" })
    eq(#messages.snapshot(), 1, "works correctly after a ring_size change")
  end

  -- A fractional ring_size is floored, not left to corrupt the circular
  -- buffer's modulo indexing.
  do
    local messages = fresh_messages()
    messages.setup({ ring_size = 2.9 })
    for i = 1, 6 do
      messages.push({ content = "m" .. i })
    end
    local snap = messages.snapshot()
    eq(#snap, 2, "a fractional ring_size is floored to 2, not left fractional")
    eq(snap[1].content, "m5", "oldest surviving entry")
    eq(snap[2].content, "m6", "newest kept")
  end

  -- since_ms/until_ms filtering.
  do
    local messages = fresh_messages()
    messages.push({ content = "old", time_ms = 1000 })
    messages.push({ content = "mid", time_ms = 2000 })
    messages.push({ content = "new", time_ms = 3000 })
    local snap = messages.snapshot({ since_ms = 1500, until_ms = 2500 })
    eq(#snap, 1, "only the entry inside the window survives")
    eq(snap[1].content, "mid", "the middle entry")
  end

  -- kinds/levels filtering.
  do
    local messages = fresh_messages()
    messages.push({ content = "a", kind = "lua_error", level = vim.log.levels.ERROR })
    messages.push({ content = "b", kind = "undo", level = vim.log.levels.INFO })
    messages.push({ content = "c", kind = "notify", level = vim.log.levels.WARN })

    local only_errors = messages.snapshot({ levels = { vim.log.levels.ERROR } })
    eq(#only_errors, 1, "levels filter narrows to ERROR")
    eq(only_errors[1].content, "a", "the error entry")

    local only_undo = messages.snapshot({ kinds = { "undo" } })
    eq(#only_undo, 1, "kinds filter narrows to undo")
    eq(only_undo[1].content, "b", "the undo entry")
  end

  -- snapshot() returns a copy, not a live reference into the ring.
  do
    local messages = fresh_messages()
    messages.push({ content = "a" })
    local snap = messages.snapshot()
    snap[1].content = "mutated"
    eq(messages.snapshot()[1].content, "a", "mutating the snapshot did not touch the store")
  end

  -- on_message/off_message.
  do
    local messages = fresh_messages()
    local seen = {}
    local handle = messages.on_message(function(entry)
      seen[#seen + 1] = entry.content
    end)
    messages.push({ content = "one" })
    eq(#seen, 1, "listener fired on push")
    messages.off_message(handle)
    messages.push({ content = "two" })
    eq(#seen, 1, "listener did not fire after off_message")
  end

  -- A listener unsubscribing (itself or another) mid-dispatch does not
  -- perturb the in-progress listener loop -- every listener subscribed at
  -- the start of the push still gets this entry.
  do
    local messages = fresh_messages()
    local seen_a, seen_b, seen_c = {}, {}, {}
    local handle_a
    handle_a = messages.on_message(function(entry)
      seen_a[#seen_a + 1] = entry.content
      messages.off_message(handle_a)
    end)
    messages.on_message(function(entry)
      seen_b[#seen_b + 1] = entry.content
    end)
    messages.on_message(function(entry)
      seen_c[#seen_c + 1] = entry.content
    end)

    messages.push({ content = "x" })
    eq(#seen_a, 1, "A fired once, then unsubscribed itself")
    eq(#seen_b, 1, "B still fired despite A's mid-dispatch unsubscribe")
    eq(#seen_c, 1, "C still fired too")

    messages.push({ content = "y" })
    eq(#seen_a, 1, "A did not fire again (unsubscribed)")
    eq(#seen_b, 2, "B keeps receiving")
    eq(#seen_c, 2, "C keeps receiving")
  end

  -- A throwing listener does not break push() or the other listeners.
  do
    local messages = fresh_messages()
    local good_seen = {}
    messages.on_message(function()
      error("boom")
    end)
    messages.on_message(function(entry)
      good_seen[#good_seen + 1] = entry.content
    end)
    ok(pcall(messages.push, { content = "x" }), "push() itself does not raise")
    eq(#good_seen, 1, "the other listener still ran")
    eq(#messages.snapshot(), 1, "the entry was still stored")
  end

  -- wrap_noice(): a safe no-op when noice isn't installed.
  do
    local messages = fresh_messages()
    package.loaded["noice"] = nil
    ok(pcall(messages.wrap_noice), "wrap_noice() does not raise without noice")
    ok(pcall(messages.notify_renderer_changed), "notify_renderer_changed() does not raise")
  end

  -- has_renderer(): tracks noice's actual running state, not just whether
  -- the module was ever require()d -- package.loaded["noice"] stays non-nil
  -- for the rest of the session even after `:Noice disable`.
  do
    local messages = fresh_messages()
    local running = true
    package.loaded["noice"] = {}
    package.loaded["noice.config"] = {
      is_running = function()
        return running
      end,
    }

    local attach_calls, detach_calls = 0, 0
    H.with_patched(vim, "ui_attach", function()
      attach_calls = attach_calls + 1
      return 1
    end, function()
      H.with_patched(vim, "ui_detach", function()
        detach_calls = detach_calls + 1
      end, function()
        messages.notify_renderer_changed()
        vim.wait(50)
        eq(attach_calls, 1, "attached while noice reports running")

        running = false
        messages.notify_renderer_changed()
        eq(
          detach_calls,
          1,
          "detached once noice reports not running, even though the module stays loaded"
        )
      end)
    end)

    package.loaded["noice"] = nil
    package.loaded["noice.config"] = nil
  end

  -- The ext_messages feed: kind -> level mapping, the history=false kinds kept by default,
  -- shell-chunk merging and the replace_last guard. The callback is captured from a patched
  -- vim.ui_attach and fed by hand, with the argument shape Neovim really sends
  -- (kind, content, replace_last, history, append, id).
  do
    local messages = fresh_messages()
    package.loaded["noice"] = {}
    package.loaded["noice.config"] = {
      is_running = function()
        return true
      end,
    }
    local cb
    H.with_patched(vim, "ui_attach", function(_, _, fn)
      cb = fn
      return 1
    end, function()
      messages.notify_renderer_changed()
      vim.wait(50)
    end)
    ok(cb ~= nil, "feed: the ui_attach callback was captured")

    ---@param kind string
    ---@param text string
    ---@param history boolean
    ---@param append? boolean
    ---@param replace_last? boolean
    local function show(kind, text, history, append, replace_last)
      cb("msg_show", kind, { { 0, text } }, replace_last == true, history, append == true, 0)
    end

    show("emsg", "E518: Unknown option: x", true)
    show("rpc_error", "Invalid method: nosuchmethod", true)
    show("wmsg", "W10: Warning: Changing a readonly file", true)
    show("wmsg", "search hit BOTTOM, continuing at TOP", false)
    show("echomsg", "plain", true)
    show("shell_out", "file1\nfile2\n", false, true)
    show("shell_err", "oops", false, true)
    show("shell_ret", "shell returned 3", false)
    show("echo", "ephemeral", false)
    show("shell_cmd", ":!ls", false)

    local by_kind = {}
    for _, e in ipairs(messages.snapshot()) do
      by_kind[e.kind] = e
    end
    eq(by_kind.emsg.level, vim.log.levels.ERROR, "emsg is an error, not INFO")
    eq(by_kind.rpc_error.level, vim.log.levels.ERROR, "rpc_error is an error")
    eq(by_kind.wmsg.level, vim.log.levels.WARN, "wmsg is a warning")
    eq(by_kind.echomsg.level, vim.log.levels.INFO, "an ordinary message stays INFO")
    eq(by_kind.shell_out.level, vim.log.levels.INFO, "shell output is kept (history=false) as INFO")
    eq(by_kind.shell_err.level, vim.log.levels.WARN, "shell stderr is a warning")
    eq(by_kind.shell_ret.level, vim.log.levels.WARN, "a failing exit code is kept as a warning")
    ok(by_kind.echo == nil, "plain :echo stays out (history=false, not opted in)")
    ok(by_kind.shell_cmd == nil, "the echoed shell command line stays out")
    local wmsgs = 0
    for _, e in ipairs(messages.snapshot()) do
      wmsgs = wmsgs + (e.kind == "wmsg" and 1 or 0)
    end
    eq(wmsgs, 1, "the history=false wmsg (search wrap) is not stored")

    -- A caller's own kinds add to the defaults; `false` opts a default one back out.
    messages.setup({ kinds = { echo = true } })
    local n = #messages.snapshot()
    show("echo", "now kept", false)
    show("shell_err", "still kept", false, true)
    eq(#messages.snapshot(), n + 2, "setup({kinds}) extends the default kinds")
    messages.setup({ kinds = { shell_out = false } })
    n = #messages.snapshot()
    show("shell_out", "dropped", false, true)
    show("shell_err", "kept", false, true)
    eq(#messages.snapshot(), n + 1, "kinds = { shell_out = false } opts a default kind out")

    -- Shell output arrives in pipe-read chunks (all append=true, the first one too): one
    -- command is one entry, the next command a new one, anything in between closes the stream.
    messages = fresh_messages()
    cb = nil
    H.with_patched(vim, "ui_attach", function(_, _, fn)
      cb = fn
      return 1
    end, function()
      messages.notify_renderer_changed()
      vim.wait(50)
    end)
    show("shell_out", "name_cut_ac", false, true)
    show("shell_out", "ross.lua\r\nsecond\r\n", false, true)
    local snap = messages.snapshot()
    eq(#snap, 1, "chunks of one run merge into one entry")
    eq(
      snap[1].content,
      "name_cut_across.lua\r\nsecond\r\n",
      "a name split across chunks is whole again"
    )
    show("shell_cmd", ":!echo B", false)
    show("shell_out", "B\r\n", false, true)
    eq(#messages.snapshot(), 2, "the next command (shell_cmd in between) is a new entry")
    show("shell_out", "tail of B", false, true)
    eq(#messages.snapshot(), 2, "its further chunks still merge")
    messages.push({ content = "interleaved" })
    show("shell_out", "after push", false, true)
    eq(#messages.snapshot(), 4, "an entry from another source closes the stream")
    local big = string.rep("x", 40000)
    show("shell_out", big, false, true)
    show("shell_out", big, false, true)
    show("shell_out", big, false, true)
    local biggest = 0
    for _, e in ipairs(messages.snapshot()) do
      biggest = math.max(biggest, #e.content)
    end
    ok(biggest <= 65536 + 40000, "a stream entry stops growing at the cap")

    -- replace_last may only overwrite what the previous event put in the ring: `:w` sends a
    -- dropped bufwrite (history=false) and then a replace_last one.
    messages = fresh_messages()
    cb = nil
    H.with_patched(vim, "ui_attach", function(_, _, fn)
      cb = fn
      return 1
    end, function()
      messages.notify_renderer_changed()
      vim.wait(50)
    end)
    show("echomsg", "AAA", true)
    show("shell_out", "SHELL", false, true)
    show("bufwrite", "f.txt [New] written", false)
    show("bufwrite", "f.txt 1L, 3B written", true, false, true)
    local contents = {}
    for _, e in ipairs(messages.snapshot()) do
      contents[#contents + 1] = e.content
    end
    eq(
      table.concat(contents, "|"),
      "AAA|SHELL|f.txt 1L, 3B written",
      "the :w message is appended, nothing erased"
    )
    show("echomsg", "first", true)
    show("echomsg", "second", true, false, true)
    local last = messages.snapshot()
    eq(
      last[#last].content,
      "second",
      "replace_last still replaces when the previous event was stored"
    )
    eq(last[#last - 1].content, "f.txt 1L, 3B written", "and only that one")

    package.loaded["noice"] = nil
    package.loaded["noice.config"] = nil
  end

  -- maybe_attach(): attaches once a renderer exists, even with floating
  -- windows already open. A prior version additionally refused to attach
  -- while ANY float was open (a documented, but here unreproduced, hang
  -- hazard) -- live-tested against the real config on 2026-10-01
  -- (WKDBooks/.../TOOLS/scripts/tui-spike/s7.lua): that guard made the
  -- logger never attach at all, since ui.nvim's own statusline chips are
  -- themselves persistent floats open for the whole session. Two direct
  -- `vim.ui_attach` probes in that same live session -- with those chip
  -- floats open, and with this module's own entered/focused popup open --
  -- both attached in under 2ms, no hang. Removed; see this function's own
  -- doc comment for the full writeup.
  do
    local messages = fresh_messages()
    package.loaded["noice"] = {}
    package.loaded["noice.config"] = {
      is_running = function()
        return true
      end,
    }

    local attach_calls = 0
    H.with_patched(vim, "ui_attach", function()
      attach_calls = attach_calls + 1
      return 1
    end, function()
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 10,
        height = 1,
        row = 0,
        col = 0,
      })

      messages.notify_renderer_changed()
      vim.wait(50)
      eq(attach_calls, 1, "attaches even with a floating window already open")

      pcall(vim.api.nvim_win_close, win, true)
    end)

    package.loaded["noice"] = nil
    package.loaded["noice.config"] = nil
  end

  -- notify.popup's M.deliver pushes into the store directly (not through
  -- ext_messages), regardless of toast_min_level.
  do
    local messages = fresh_messages()
    local popup = require("lib.nvim.notify.popup")
    -- Below any realistic toast_min_level, and headless (no UI to toast to
    -- anyway) -- this still has to land in the store.
    popup.deliver("quiet one", vim.log.levels.TRACE, { messages = false })
    local snap = messages.snapshot()
    local found = false
    for _, entry in ipairs(snap) do
      if entry.content == "quiet one" then
        found = true
      end
    end
    ok(found, "popup.deliver() pushed into lib.nvim.messages even below toast_min_level")
  end
end
