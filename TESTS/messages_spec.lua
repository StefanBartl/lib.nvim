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
