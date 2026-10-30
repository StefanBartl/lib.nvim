-- TESTS/ui_kit_history_spec.lua -- lib.nvim.ui.kit.history: the back/forward trail generalised from
-- documentation.nvim's browser (go / CLEAR / history_step). Pure data, so every case runs on plain tables.

return function(H)
  local eq, ok = H.eq, H.ok
  local history = require("lib.nvim.ui.kit.history")
  local CLEAR = history.CLEAR
  local KEYS = { "mode", "id", "fn", "cursor" }

  local function fresh(max, dedupe)
    local st = { mode = "structure", id = "root", cursor = 1, other = "not tracked" }
    return st, history.new({ state = st, keys = KEYS, max = max, dedupe = dedupe })
  end

  -- the kit exposes it as a lazy field, the same table
  eq(require("lib.nvim.ui.kit").history, history, "kit.history is lib.nvim.ui.kit.history")

  -- the trail starts with where we are: one entry, the index on it, no step possible
  do
    local st, h = fresh()
    eq(h:len(), 1, "a new history holds the current position")
    eq(h:index(), 1, "...and points at it")
    eq(h:current().id, "root", "the first entry is the state as it was")
    eq(h:current().other, nil, "an untracked field is not snapshotted")
    eq(h:can_back(), false, "nothing to go back to")
    eq(h:can_forward(), false, "nothing to go forward to")
    eq(h:back(st), false, "back at the start does not move")
    eq(h:forward(st), false, "forward at the end does not move")
    eq(h:step(st, 0), false, "a zero step is no move")
    eq(st.id, "root", "a refused step leaves the state alone")
  end

  -- go: record, apply, push; back and forward restore exactly
  do
    local st, h = fresh()
    eq(h:go(st, { id = "a", fn = "f" }), true, "a move makes a stop")
    eq(st.id, "a", "the move is applied to the state")
    eq(h:len(), 2, "two entries")
    eq(
      h:index(),
      2,
      "the index is on the new position, not the one before (the off-by-one the source fixed)"
    )
    eq(h:back(st), true, "back moves")
    eq(st.id, "root", "back restores the previous position")
    eq(st.fn, nil, "...and a key that position did not have is nil again")
    eq(st.other, "not tracked", "an untracked field is left alone")
    eq(h:forward(st), true, "forward moves")
    eq(st.id, "a", "forward restores the later position")
    eq(st.fn, "f", "...with its fields")
  end

  -- CLEAR: a patch that names nil cannot clear a field (pairs skips it); the sentinel does
  do
    local st, h = fresh()
    h:go(st, { id = "a", fn = "f" })
    h:go(st, { fn = nil })
    eq(st.fn, "f", "a nil in the patch keeps the old value (the bug the sentinel exists for)")
    eq(h:len(), 2, "...and, changing nothing, makes no stop")
    eq(h:go(st, { fn = CLEAR }), true, "CLEAR is a change")
    eq(st.fn, nil, "CLEAR removes the field")
    eq(h:current().fn, nil, "...in the new entry too")
    eq(tostring(CLEAR), "<clear>", "CLEAR prints as <clear>")
    ok(not pcall(function()
      CLEAR.x = 1
    end), "CLEAR is read-only")
    local t = history.apply({ a = 1, b = 2 }, { a = CLEAR, c = 3 })
    eq(t.a, nil, "apply: CLEAR removes")
    eq(t.b, 2, "apply: an unnamed field stays")
    eq(t.c, 3, "apply: a value is set")
  end

  -- a new move truncates forward history, like a browser
  do
    local st, h = fresh()
    h:go(st, { id = "a" })
    h:go(st, { id = "b" })
    h:back(st, 2)
    eq(st.id, "root", "back with a count goes that far")
    h:go(st, { id = "c" })
    eq(h:len(), 2, "the forward entries are gone")
    eq(h:can_forward(), false, "nothing ahead after a new move")
    h:back(st)
    eq(st.id, "root", "and back lands where the move started")
  end

  -- a step beyond the trail does not move (not clamped), as history_step's bounds check
  do
    local st, h = fresh()
    h:go(st, { id = "a" })
    eq(h:back(st, 5), false, "a count past the start is refused")
    eq(st.id, "a", "...and the state is unchanged")
    eq(h:index(), 2, "...and the index too")
  end

  -- a fractional count is an argument error raised before anything moves, not a broken index
  do
    local st, h = fresh()
    h:go(st, { id = "a" })
    local good, err = pcall(h.back, h, st, 0.5)
    ok(
      not good and tostring(err):find("must be an integer", 1, true),
      "a fractional count is rejected"
    )
    eq(h:index(), 2, "...the index is unchanged")
    eq(h:current().id, "a", "...the current entry too")
    ok(not pcall(h.step, h, st, "1"), "a non-number delta is rejected")
    eq(h:back(st), true, "the history still works afterwards")
    eq(st.id, "root", "...and restores the first entry")
  end

  -- dedupe: a move that changes no tracked key makes no stop and keeps forward history
  do
    local st, h = fresh()
    h:go(st, { id = "a" })
    h:back(st)
    eq(h:go(st, { id = "root" }), false, "a move to where we are makes no stop")
    eq(h:len(), 2, "...the forward entry is kept")
    eq(h:go(st, { other = "x" }), false, "a change to an untracked field is no stop")
    eq(st.other, "x", "...but it is applied")
    local st2, h2 = fresh(nil, false)
    eq(h2:go(st2, {}), true, "dedupe = false: every move is a stop")
    eq(h2:len(), 2, "...even an empty one")
  end

  -- record before leaving: coming back restores the row the user was on, not the one they arrived at
  do
    local st, h = fresh()
    h:go(st, { id = "a", cursor = 1 })
    st.cursor = 7 -- the user moved inside the list
    h:back(st)
    eq(st.cursor, 1, "back restores the old position's cursor")
    h:forward(st)
    eq(st.cursor, 7, "forward returns to the row the user had moved to")
    st.cursor = 9
    h:go(st, { id = "b", cursor = 1 })
    h:back(st)
    eq(st.cursor, 9, "go records the position being left as well")
  end

  -- patch: state that travels with a position without being a stop (the source's filter)
  do
    local st, h = fresh()
    h:go(st, { id = "a" })
    h:patch(st, { cursor = 4, other = "x", fn = "g" })
    eq(h:len(), 2, "patch makes no stop")
    eq(st.cursor, 4, "patch changes the state")
    eq(h:current().cursor, 4, "...and the current entry")
    eq(h:current().other, nil, "an untracked field is not snapshotted")
    h:patch(st, { fn = CLEAR })
    eq(st.fn, nil, "CLEAR removes a field from the state")
    eq(h:current().fn, nil, "...and from the entry")
    h:back(st)
    eq(st.cursor, 1, "back leaves the patched position")
    h:forward(st)
    eq(st.cursor, 4, "the patched value comes back")
    eq(st.fn, nil, "...and the cleared one stays cleared")
  end

  -- max: the oldest entry goes, the index follows
  do
    local st, h = fresh(3)
    for _, id in ipairs({ "a", "b", "c", "d" }) do
      h:go(st, { id = id })
    end
    eq(h:len(), 3, "capped at max")
    eq(h:index(), 3, "index on the newest")
    eq(h:entries()[1].id, "b", "the oldest entries were dropped")
    h:back(st, 2)
    eq(st.id, "b", "back reaches the oldest kept entry")
    eq(h:can_back(), false, "and no further")
  end

  -- reset and entries
  do
    local st, h = fresh()
    h:go(st, { id = "a" })
    local list = h:entries()
    list[#list + 1] = {}
    eq(h:len(), 2, "entries() returns a copy of the list")
    st.id = "z"
    h:reset(st)
    eq(h:len(), 1, "reset leaves one entry")
    eq(h:current().id, "z", "...the state as it is")
    eq(h:can_back(), false, "nothing behind it")
  end

  -- argument errors name the problem
  do
    ok(not pcall(history.new, { state = {}, keys = {} }), "empty keys are rejected")
    ok(not pcall(history.new, { state = {}, keys = { 1 } }), "a non-string key is rejected")
    ok(not pcall(history.new, { keys = { "a" } }), "a missing state is rejected")
    ok(not pcall(history.new, { state = {}, keys = { "a" }, max = 0 }), "max = 0 is rejected")
    ok(
      not pcall(history.new, { state = {}, keys = { "a" }, max = 1.5 }),
      "a fractional max is rejected"
    )
    local _, h = fresh()
    local good, err = pcall(h.go, h, nil, {})
    ok(
      not good and tostring(err):find("state must be a table", 1, true),
      "go without a state says so"
    )
    -- the keys list is copied: changing the caller's table later does not change what is tracked
    local keys = { "a" }
    local h2 = history.new({ state = { a = 1, b = 1 }, keys = keys })
    keys[2] = "b"
    local s2 = { a = 1, b = 2 }
    eq(h2:push(s2), false, "a key added to the caller's list afterwards is not tracked")
  end
end
