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
