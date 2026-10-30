-- TESTS/companion_protocol_spec.lua — lib.nvim.companion.protocol against a fake transport that
-- records every message: validation, attach -> connect -> render, update / set_title pushes,
-- actions with fixed and prompted arguments, close (the quit as a NOTIFICATION, on_close once;
-- also from state "attaching", where the channel back is opened first), detach, a dead channel
-- and an attach timeout found by the liveness check (fake clock), close_all. No process is
-- spawned here. The fake transport has no `request` on purpose: a blocking request across the
-- two channels can deadlock the main and the companion, so the protocol must never make one.

return function(H)
  local eq, ok = H.eq, H.ok
  local protocol = require("lib.nvim.companion.protocol")

  ---@return Lib.Companion.Transport, table
  local function fake_transport()
    local log = { sent = {}, closed = {}, dead = {}, next_chan = 100 }
    local t = {
      connect = function(servername)
        if servername == "unreachable" then
          return nil, "no such server"
        end
        log.next_chan = log.next_chan + 1
        log.connected = servername
        return log.next_chan
      end,
      notify = function(chan, msg)
        if log.dead[chan] then
          return false
        end
        log.sent[#log.sent + 1] = { chan = chan, msg = msg }
        return true
      end,
      alive = function(chan)
        return not log.dead[chan]
      end,
      close = function(chan)
        log.closed[#log.closed + 1] = chan
      end,
    }
    return t, log
  end

  local function last_sent(log)
    return log.sent[#log.sent]
  end

  ---How many quit notifications went out.
  local function quits(log)
    local n = 0
    for _, s in ipairs(log.sent) do
      if s.msg.code:find("quit", 1, true) then
        n = n + 1
      end
    end
    return n
  end

  -- messages
  local m = protocol.messages.render({ lines = { "a" }, highlights = {}, title = "T" })
  ok(m.code:find("companion.client').render", 1, true), "messages: render goes to the client")
  eq(m.args[1].lines[1], "a", "messages: render carries the payload")
  eq(protocol.messages.set_title("x").args[1], "x", "messages: set_title")
  eq(#protocol.messages.quit().args, 0, "messages: quit has no argument")

  -- validation on create
  local t, log = fake_transport()
  local reg = protocol.new(t)
  eq(select(2, reg:create({ lines = { 1 } })), "line 1 is not a string", "create: lines")
  eq(select(2, reg:create({ lines = { "a\nb" } })), "line 1 holds a newline", "create: newline")
  eq(select(2, reg:create({ highlights = { {} } })) ~= nil, true, "create: highlights")
  eq(
    select(2, reg:create({ keys = { a = "jump" } })),
    'key a: no action "jump"',
    "create: key without action"
  )
  eq(
    select(2, reg:create({ actions = { jump = function() end }, keys = { a = { 1 } } })),
    "key a: expected an action name or { name, args... }",
    "create: malformed key spec"
  )
  eq(
    select(2, reg:create({ actions = { x = 1 } })),
    "actions must map names to functions",
    "create: actions"
  )
  eq(select(2, reg:create({ on_close = 1 })), "on_close must be a function", "create: on_close")
  eq(select(2, reg:create({ title = 1 })), "title must be a string", "create: title")
  eq(
    select(2, reg:create({ attach_timeout = 0 })),
    "attach_timeout must be a positive number of milliseconds or false",
    "create: attach_timeout"
  )
  eq(select(2, reg:create({ attach_timeout = "5" })) ~= nil, true, "create: attach_timeout type")
  eq(reg:count(), 0, "create: nothing registered after refusals")

  -- the happy path: create -> attach -> connect -> render
  local got = {}
  local closed = 0
  local h = reg:create({
    title = "Memory",
    lines = { "00: ab", "01: cd" },
    highlights = { { line = 0, col_start = 0, col_end = 2, group = "Title" } },
    filetype = "hex",
    actions = {
      jump = function(addr)
        got[#got + 1] = { "jump", addr }
      end,
      page = function(delta)
        got[#got + 1] = { "page", delta }
      end,
      boom = function()
        error("no")
      end,
    },
    keys = {
      a = { "jump", prompt = "Address: " },
      n = { "page", 1 },
      p = { "page", -1 },
      b = "boom",
    },
    on_close = function()
      closed = closed + 1
    end,
  })
  ok(h ~= nil, "create: handle")
  eq(h.id, 1, "create: ids start at 1")
  eq(h.state, "pending", "create: pending")
  eq(h:is_open(), true, "create: open")
  eq(h:is_attached(), false, "create: not attached")
  eq(reg:count(), 1, "create: registered")

  -- an update before the companion attached waits in the handle
  eq(
    h:update({ "00: ef" }, { { line = 0, col_start = 0, col_end = 2, group = "Title" } }),
    true,
    "update: accepted while pending"
  )
  eq(#log.sent, 0, "update: nothing sent before attach")
  eq(h.lines[1], "00: ef", "update: kept")

  local cfg = reg:attach(1, "pipe-of-companion")
  eq(cfg.title, "Memory", "attach: title")
  eq(cfg.filetype, "hex", "attach: filetype")
  eq(cfg.keys.n.name, "page", "attach: keys travel as { name, args, prompt }")
  eq(cfg.keys.n.args[1], 1, "attach: fixed argument")
  eq(cfg.keys.p.args[1], -1, "attach: negative fixed argument")
  eq(cfg.keys.a.prompt, "Address: ", "attach: prompt")
  eq(#cfg.keys.a.args, 0, "attach: no fixed argument with a prompt")
  eq(cfg.keys.b.name, "boom", "attach: a bare name")
  eq(cfg.keys.b.prompt, nil, "attach: no prompt by default")
  for _, spec in pairs(cfg.keys) do
    local next_key = next(spec.args)
    ok(next_key == nil or type(next_key) == "number", "attach: args is a pure list")
  end
  eq(cfg.closed, nil, "attach: not closed")
  eq(h.state, "attaching", "attach: attaching, channel not yet open")
  eq(log.connected, nil, "attach: does not connect (the companion is blocked in the request)")

  eq(reg:connect(1), true, "connect: connected")
  eq(log.connected, "pipe-of-companion", "connect: to the companion's server")
  eq(h:is_attached(), true, "connect: attached")
  eq(#log.sent, 1, "connect: the first render goes out")
  local first = last_sent(log)
  eq(first.chan, 101, "connect: on the new channel")
  eq(first.msg.args[1].lines[1], "00: ef", "connect: with the current content")
  eq(first.msg.args[1].highlights[1].group, "Title", "connect: and the highlights")
  eq(first.msg.args[1].title, "Memory", "connect: and the title")

  -- unknown / closed ids
  local none = reg:attach(99, "x")
  eq(none.closed, true, "attach: unknown id is told to quit")
  eq(reg:attach(1, "").closed, true, "attach: an empty servername is refused")
  eq(h:is_attached(), true, "attach: a refused attach does not touch the handle")
  eq(reg:connect(99), false, "connect: unknown id")

  -- updates and titles reach the companion
  eq(
    h:update({ "x", "y" }, { { line = 1, col_start = 0, col_end = 1, group = "Error" } }),
    true,
    "update: ok"
  )
  eq(#log.sent, 2, "update: one message")
  eq(last_sent(log).msg.args[1].lines[2], "y", "update: lines")
  eq(last_sent(log).msg.args[1].highlights[1].line, 1, "update: highlights")
  eq(select(2, h:update({ 1 })), "line 1 is not a string", "update: validated")
  eq(#log.sent, 2, "update: an invalid update sends nothing")
  eq(h:update(nil), true, "update: nil is empty")
  eq(#last_sent(log).msg.args[1].lines, 0, "update: nil -> no lines")
  eq(h:set_title("Memory 0x10"), true, "set_title: ok")
  eq(last_sent(log).msg.args[1], "Memory 0x10", "set_title: sent")
  eq(h.title, "Memory 0x10", "set_title: kept")
  eq(h:set_title(1), false, "set_title: must be a string")

  -- actions
  eq(reg:action(1, "page", { 1 }), true, "action: fixed argument")
  eq(got[1][1], "page", "action: ran")
  eq(got[1][2], 1, "action: argument")
  eq(reg:action(1, "jump", { "0x40" }), true, "action: prompted text as the argument")
  eq(got[2][2], "0x40", "action: text")
  eq(reg:action(1, "jump"), true, "action: no args")
  eq(got[3][2], nil, "action: nil argument")
  local aok, aerr = reg:action(1, "nope")
  eq(aok, false, "action: unknown name")
  ok(aerr:find('no action "nope"', 1, true), "action: message names it")
  aok, aerr = reg:action(1, "boom")
  eq(aok, false, "action: a throwing action is reported")
  ok(aerr:find("no", 1, true), "action: with the error")
  eq(select(2, reg:action(7, "page")), "no companion 7", "action: unknown id")

  -- close: the quit goes out as a NOTIFICATION (never a request: a companion blocked in its own
  -- request to the main would deadlock both), channel closed, on_close once, idempotent
  local sent_before = #log.sent
  h:close()
  eq(h:is_open(), false, "close: closed")
  eq(#log.sent, sent_before + 1, "close: one message")
  ok(last_sent(log).msg.code:find("quit", 1, true), "close: the quit, as a notification")
  eq(last_sent(log).chan, 101, "close: on the companion's channel")
  eq(log.closed[1], 101, "close: channel closed")
  eq(closed, 1, "close: on_close once")
  eq(reg:count(), 0, "close: forgotten")
  h:close()
  eq(closed, 1, "close: idempotent")
  eq(#log.sent, sent_before + 1, "close: nothing sent twice")
  eq(h:update({ "z" }), false, "close: update after close is refused")
  eq(h:set_title("z"), false, "close: set_title after close is refused")
  eq(reg:connect(1), false, "close: a late connect does nothing")

  -- a failed send (dead channel) ends in a detach with on_close
  local c2 = 0
  local h2 = reg:create({
    on_close = function()
      c2 = c2 + 1
    end,
  })
  reg:attach(h2.id, "s2")
  reg:connect(h2.id)
  eq(h2:is_attached(), true, "dead: attached")
  log.dead[h2.chan] = true
  eq(h2:update({ "a" }), true, "dead: update returns true (the content is kept)")
  eq(h2:is_open(), false, "dead: a failed push closes the handle")
  eq(c2, 1, "dead: on_close once")
  eq(log.closed[#log.closed], 102, "dead: channel closed")

  -- an unreachable companion: connect fails -> detached
  local c3 = 0
  local h3 = reg:create({
    on_close = function()
      c3 = c3 + 1
    end,
  })
  reg:attach(h3.id, "unreachable")
  eq(reg:connect(h3.id), false, "unreachable: not connected")
  eq(h3:is_open(), false, "unreachable: closed")
  eq(c3, 1, "unreachable: on_close")

  -- detach (the companion said goodbye) and drop (a failed spawn)
  local c4 = 0
  local h4 = reg:create({
    on_close = function()
      c4 = c4 + 1
    end,
  })
  reg:attach(h4.id, "s4")
  reg:connect(h4.id)
  local quits_before = quits(log)
  reg:detach(h4.id)
  eq(h4:is_open(), false, "detach: closed")
  eq(c4, 1, "detach: on_close once")
  eq(quits(log), quits_before, "detach: no quit sent to a companion that is gone")
  reg:detach(h4.id)
  eq(c4, 1, "detach: idempotent")
  local c5 = 0
  local h5 = reg:create({
    on_close = function()
      c5 = c5 + 1
    end,
  })
  reg:drop(h5.id)
  eq(h5:is_open(), false, "drop: closed")
  eq(c5, 0, "drop: no on_close")
  eq(reg:count(), 0, "drop: forgotten")

  -- liveness check: a channel that vanished
  local h6 = reg:create({})
  local h7 = reg:create({})
  reg:attach(h6.id, "s6")
  reg:connect(h6.id)
  reg:attach(h7.id, "s7")
  reg:connect(h7.id)
  eq(reg:check(), 0, "check: all alive")
  log.dead[h6.chan] = true
  eq(reg:check(), 1, "check: one gone")
  eq(h6:is_open(), false, "check: the dead one is closed")
  eq(h7:is_open(), true, "check: the other stays")

  -- a throwing on_close is reported, not raised, and the handle is still closed
  local notes = {}
  local h8 = reg:create({
    on_close = function()
      error("bad close")
    end,
  })
  H.with_patched(vim, "notify", function(msg)
    notes[#notes + 1] = msg
  end, function()
    h8:close()
  end)
  eq(h8:is_open(), false, "on_close throws: closed anyway")
  ok(notes[1] and notes[1]:find("bad close", 1, true), "on_close throws: reported")

  -- close_all: every open handle, a direct companion gets its stop
  local stopped = false
  local h9 = reg:create({})
  h9.stop = function()
    stopped = true
  end
  reg:attach(h9.id, "s9")
  reg:connect(h9.id)
  local before = quits(log)
  reg:close_all()
  eq(reg:count(), 0, "close_all: none left")
  eq(h7:is_open(), false, "close_all: the attached one is closed")
  eq(h9:is_open(), false, "close_all: the direct one too")
  eq(stopped, true, "close_all: its process is stopped")
  eq(quits(log), before + 2, "close_all: a quit per attached companion")

  -- close while "attaching" (the companion reported in, the scheduled connect has not run):
  -- the channel back is opened here and the quit goes out, so the companion does not stay
  -- open until the main exits
  local c10 = 0
  local h10 = reg:create({
    on_close = function()
      c10 = c10 + 1
    end,
  })
  reg:attach(h10.id, "s10")
  eq(h10.state, "attaching", "attaching: state")
  log.connected = nil
  before = quits(log)
  h10:close()
  eq(log.connected, "s10", "attaching: close connects to the companion first")
  eq(quits(log), before + 1, "attaching: and sends the quit")
  eq(last_sent(log).chan, log.closed[#log.closed], "attaching: on the channel it then closes")
  eq(h10:is_open(), false, "attaching: closed")
  eq(c10, 1, "attaching: on_close once")
  eq(reg:connect(h10.id), false, "attaching: the late connect does nothing")
  -- an unreachable one is closed all the same (nothing to tell)
  local h11 = reg:create({})
  reg:attach(h11.id, "unreachable")
  before = quits(log)
  h11:close()
  eq(h11:is_open(), false, "attaching: unreachable is closed")
  eq(quits(log), before, "attaching: unreachable gets no quit")

  -- attach timeout: a companion that never reports in is closed by the liveness check
  local now = 0
  local t2, log2 = fake_transport()
  local reg2 = protocol.new(t2, function()
    return now
  end)
  eq(type(protocol.ATTACH_TIMEOUT_MS), "number", "timeout: a default exists")
  local c12, stopped12 = 0, false
  local h12 = reg2:create({
    title = "Late",
    attach_timeout = 5000,
    on_close = function()
      c12 = c12 + 1
    end,
  })
  h12.stop = function()
    stopped12 = true
  end
  local h13 = reg2:create({ attach_timeout = false })
  local h14 = reg2:create({})
  eq(h14.attach_timeout, protocol.ATTACH_TIMEOUT_MS, "timeout: the default applies")
  local h15 = reg2:create({ attach_timeout = 5000 })
  reg2:attach(h15.id, "s15")
  reg2:connect(h15.id)
  eq(reg2:check(), 0, "timeout: nothing at 0 ms")
  now = 4999
  eq(reg2:check(), 0, "timeout: nothing just before")
  eq(h12:is_open(), true, "timeout: still pending")
  now = 5000
  notes = {}
  local n
  H.with_patched(vim, "notify", function(msg)
    notes[#notes + 1] = msg
  end, function()
    n = reg2:check()
  end)
  eq(n, 1, "timeout: one closed")
  eq(h12:is_open(), false, "timeout: the pending one is closed")
  eq(c12, 1, "timeout: on_close once")
  eq(stopped12, true, "timeout: its process is stopped")
  eq(#log2.sent, 1, "timeout: nothing was sent to it (no channel); only h15's render")
  ok(notes[1] and notes[1]:find("Late", 1, true), "timeout: the warning names the companion")
  eq(h13:is_open(), true, "timeout: false means wait forever")
  eq(h14:is_open(), true, "timeout: the default has not passed")
  eq(h15:is_open(), true, "timeout: an attached one is not affected")
  reg2:attach(h13.id, "s13")
  eq(reg2:check(), 0, "timeout: attaching without a limit stays")
  now = protocol.ATTACH_TIMEOUT_MS
  H.with_patched(vim, "notify", function() end, function()
    n = reg2:check()
  end)
  eq(n, 1, "timeout: the default passed")
  eq(h14:is_open(), false, "timeout: closed at the default")
  eq(h13:is_open(), true, "timeout: the unlimited one stays")
end
