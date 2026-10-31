-- TESTS/patterns_saga_spec.lua — lib.lua.patterns.saga
return function(H)
  local eq, ok = H.eq, H.ok
  local saga = require("lib.lua.patterns.saga")

  local log = {}
  local function step(name, fail, comp_fail)
    return {
      name = name,
      run = function(ctx)
        log[#log + 1] = "run " .. name
        if fail then
          error(name .. " failed", 0)
        end
        ctx[name] = true
      end,
      compensate = function(ctx)
        log[#log + 1] = "undo " .. name
        ctx[name] = nil
        if comp_fail then
          error("undo " .. name .. " failed", 0)
        end
      end,
    }
  end

  local ctx = {}
  local good, res = saga.run({ step("a"), step("b") }, ctx)
  ok(good and res == ctx and ctx.a and ctx.b, "all steps run and the context is returned")
  eq(table.concat(log, ","), "run a,run b", "no compensation on success")

  log, ctx = {}, {}
  local ok2, err, report = saga.run({ step("a"), step("b"), step("c", true), step("d") }, ctx)
  ok(not ok2 and err == "c failed", "failure returns false and the error")
  eq(
    table.concat(log, ","),
    "run a,run b,run c,undo b,undo a",
    "completed steps are compensated in reverse"
  )
  eq(report[1].status, "compensated", "report: a")
  eq(report[3].status, "failed", "report: failing step")
  eq(report[4].status, "skipped", "report: step after the failure")
  ok(ctx.a == nil and ctx.b == nil, "compensations undid the context changes")

  log = {}
  local _, _, rep2 = saga.run({ step("a"), step("b", false, true), step("c", true) }, {})
  eq(
    table.concat(log, ","),
    "run a,run b,run c,undo b,undo a",
    "a failing compensation does not stop the others"
  )
  eq(rep2[2].status, "compensation_failed", "and is reported")
  eq(rep2[2].err, "undo b failed", "with its error")
  eq(rep2[1].status, "compensated", "earlier steps are still compensated")

  local no_comp = {
    { name = "x", run = function() end },
    {
      name = "y",
      run = function()
        error("no", 0)
      end,
    },
  }
  local ok3, _, rep3 = saga.run(no_comp)
  ok(not ok3 and rep3[1].status == "done", "a step without compensate is left as done")
  ok(saga.run({}), "an empty saga succeeds")
end
