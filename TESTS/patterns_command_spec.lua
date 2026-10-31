-- TESTS/patterns_command_spec.lua — lib.lua.patterns.command
return function(H)
  local eq, ok = H.eq, H.ok
  local command = require("lib.lua.patterns.command")

  local doc = { title = "old" }
  local set_title = {
    name = "set title",
    run = function(d, title)
      local old = d.title
      d.title = title
      return old
    end,
    undo = function(old, d)
      d.title = old
    end,
  }

  local h = command.history({ limit = 3 })
  ok(not h:can_undo() and not h:can_redo(), "empty history")
  eq(h:undo(), nil, "undo on empty returns nil")

  eq(h:run(set_title, doc, "a"), "old", "run returns the undo state")
  h:run(set_title, doc, "b")
  eq(doc.title, "b", "commands ran")
  eq(h:undo(), "set title", "undo returns the command name")
  eq(doc.title, "a", "undo restored the previous value")
  ok(h:can_redo(), "redo available")
  eq(h:redo(), "set title", "redo returns the name")
  eq(doc.title, "b", "redo ran the command again")

  h:undo()
  h:run(set_title, doc, "c")
  ok(not h:can_redo(), "a new command clears the redo stack")

  h:run(set_title, doc, "d")
  h:run(set_title, doc, "e")
  eq(#h:names(), 3, "limit drops the oldest entry")
  h:undo()
  h:undo()
  h:undo()
  eq(doc.title, "a", "only the last 3 commands can be undone")
  ok(not h:can_undo(), "stack is empty after undoing everything")

  local failing = {
    name = "boom",
    run = function()
      error("nope", 0)
    end,
  }
  local hh = command.history()
  ok(not pcall(hh.run, hh, failing), "a failing command raises")
  ok(not hh:can_undo(), "and records nothing")

  local nil_arg = {
    name = "nil arg",
    run = function(a, b, c)
      return select("#", a, b, c)
    end,
    undo = function(_, a, b, c)
      doc.seen = { a, b, c }
    end,
  }
  hh:run(nil_arg, 1, nil, 3)
  hh:undo()
  ok(
    doc.seen[1] == 1 and doc.seen[2] == nil and doc.seen[3] == 3,
    "arguments (with nil holes) reach undo"
  )

  -- a raising undo / redo must not lose the command from the history
  local flaky_undo = true
  local fragile = {
    name = "fragile",
    run = function() end,
    undo = function()
      if flaky_undo then
        error("undo broke", 0)
      end
    end,
  }
  local fh = command.history()
  fh:run(fragile)
  ok(not pcall(fh.undo, fh), "a raising undo raises")
  ok(fh:can_undo() and not fh:can_redo(), "and the entry stays on the undo stack")
  flaky_undo = false
  eq(fh:undo(), "fragile", "a later undo works")

  local flaky_run = false
  local fragile_run = {
    name = "fragile-run",
    run = function()
      if flaky_run then
        error("run broke", 0)
      end
    end,
    undo = function() end,
  }
  local rh = command.history()
  rh:run(fragile_run)
  rh:undo()
  flaky_run = true
  ok(not pcall(rh.redo, rh), "a raising redo raises")
  ok(rh:can_redo() and not rh:can_undo(), "and the entry stays on the redo stack")
  flaky_run = false
  eq(rh:redo(), "fragile-run", "a later redo works")

  hh:run({ run = function() end }, 1)
  eq(hh:undo(), nil, "a command without name and undo can be undone without error")
  hh:clear()
  ok(not hh:can_undo(), "clear")
end
