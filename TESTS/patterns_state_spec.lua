-- TESTS/patterns_state_spec.lua — lib.lua.patterns.state
return function(H)
  local eq, ok = H.eq, H.ok
  local state = require("lib.lua.patterns.state")

  local log = {}
  local door = state.new({
    initial = "closed",
    fields = { opened = 0 },
    states = {
      closed = {
        open = function(self)
          self.opened = self.opened + 1
          self:set_state("open")
          return "opening"
        end,
        exit = function(_, to)
          log[#log + 1] = "exit closed>" .. to
        end,
        enter = function(_, from)
          log[#log + 1] = "enter closed<" .. tostring(from)
        end,
      },
      open = {
        close = function(self)
          self:set_state("closed")
        end,
        enter = function(_, from)
          log[#log + 1] = "enter open<" .. from
        end,
        default = function(_, ...)
          return "default", ...
        end,
      },
    },
  })

  eq(door:current_state(), "closed", "initial state")
  eq(log[1], "enter closed<nil", "initial enter runs once with no origin")
  ok(door:is_state("closed") and not door:is_state("open"), "is_state")

  eq(door:open(), "opening", "method of the current state runs with the object")
  eq(door.opened, 1, "state methods see the object's fields")
  eq(door:current_state(), "open", "state switched")
  eq(table.concat(log, "|"), "enter closed<nil|exit closed>open|enter open<closed", "hook order")

  local d, a = door:anything("x")
  ok(d == "default" and a == "x", "default handles methods the state lacks")
  door:close()
  eq(door:current_state(), "closed", "back to closed")

  local good, err = pcall(function()
    return door:close()
  end)
  ok(
    not good and tostring(err):find("closed", 1, true),
    "a method missing in the state raises naming the state"
  )
  ok(not pcall(door.set_state, door, "nope"), "unknown state raises")
  ok(not pcall(state.new, { states = {}, initial = "x" }), "unknown initial raises")
end
