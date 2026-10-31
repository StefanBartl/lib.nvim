-- TESTS/patterns_unit_of_work_spec.lua — lib.lua.patterns.unit_of_work
return function(H)
  local eq, ok = H.eq, H.ok
  local repository = require("lib.lua.patterns.repository")
  local unit_of_work = require("lib.lua.patterns.unit_of_work")

  local store = repository.memory()
  store.put("keep", "k0")
  store.put("c", "c0")

  local uow = unit_of_work.new(store)
  uow:add("a", 1):change("keep", "k1"):remove("c")
  eq(uow:pending(), 3, "changes are queued")
  eq(store.get("a"), nil, "nothing applied before commit")

  local committed = uow:commit()
  ok(committed, "commit succeeds")
  ok(
    store.get("a") == 1 and store.get("keep") == "k1" and store.get("c") == nil,
    "all changes applied"
  )
  eq(uow:pending(), 0, "queue cleared")

  uow:add("z", 9)
  uow:rollback()
  eq(uow:pending(), 0, "rollback drops the queue")
  uow:commit()
  eq(store.get("z"), nil, "rolled back changes are never applied")

  -- failure in the middle: applied steps are reverted
  local failing = {
    get = store.get,
    delete = store.delete,
    put = function(id, v)
      if id == "bad" then
        error("disk full", 0)
      end
      store.put(id, v)
    end,
  }
  local u2 = unit_of_work.new(failing)
  u2:add("n1", "new"):change("keep", "k2"):remove("a"):add("bad", 1):add("never", 1)
  local ok2, err, step = u2:commit()
  ok(not ok2 and err == "disk full" and step == 4, "commit reports the error and the failing step")
  eq(store.get("n1"), nil, "a newly added entry was removed again")
  eq(store.get("keep"), "k1", "a changed entry got its old value back")
  eq(store.get("a"), 1, "a removed entry was restored")
  eq(store.get("never"), nil, "steps after the failure never ran")
  eq(u2:pending(), 0, "the queue is cleared after a failed commit")

  ok(not pcall(unit_of_work.new, { get = function() end }), "store needs get/put/delete")
end
