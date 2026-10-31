-- TESTS/patterns_reducer_spec.lua — lib.lua.patterns.reducer
return function(H)
  local eq, ok = H.eq, H.ok
  local reducer = require("lib.lua.patterns.reducer")

  local function list_reducer(state, action)
    if action.type == "add" then
      local out = {}
      for i, v in ipairs(state) do
        out[i] = v
      end
      out[#out + 1] = action.item
      return out
    elseif action.type == "boom" then
      error("reducer failed", 0)
    end
    return state
  end

  local store = reducer.store(list_reducer, {})
  local events = {}
  local off = store:subscribe(function(new, old, action)
    events[#events + 1] = #old .. ">" .. #new .. ":" .. action.type
  end)

  local good, st = store:dispatch({ type = "add", item = "a" })
  ok(good and #st == 1, "dispatch returns ok and the new state")
  store:dispatch({ type = "add", item = "b" })
  eq(#store:state(), 2, "state accumulates")
  eq(table.concat(events, ","), "0>1:add,1>2:add", "subscriber gets new, old and action")

  store:dispatch({ type = "other" })
  eq(#events, 2, "no notification when the reducer returns the same state")

  local bad, err = store:dispatch({ type = "boom" })
  ok(not bad and err == "reducer failed", "a raising reducer returns false, err")
  eq(#store:state(), 2, "and leaves the state unchanged")

  off()
  store:dispatch({ type = "add", item = "c" })
  eq(#events, 2, "unsubscribed")

  store:subscribe(function()
    error("listener broke", 0)
  end)
  local still = store:dispatch({ type = "add", item = "d" })
  ok(still and #store:state() == 4, "a raising subscriber does not break dispatch")

  -- combine
  local counter = function(s, a)
    s = s or 0
    if a.type == "inc" then
      return s + 1
    end
    return s
  end
  local names = function(s, a)
    s = s or "none"
    if a.type == "name" then
      return a.value
    end
    return s
  end
  local root = reducer.combine({ count = counter, name = names })
  local s0 = root(nil, { type = "init" })
  ok(s0.count == 0 and s0.name == "none", "combine builds the initial state from the slices")
  local s1 = root(s0, { type = "inc" })
  ok(s1.count == 1 and s1.name == "none" and s1 ~= s0, "one slice changed: new state table")
  ok(root(s1, { type = "nothing" }) == s1, "no slice changed: same state table")
  ok(not pcall(reducer.store, nil, {}), "reduce must be a function")
end
