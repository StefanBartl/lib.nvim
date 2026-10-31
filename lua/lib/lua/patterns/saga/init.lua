---@module 'lib.lua.patterns.saga'
--- Saga: a multi-step process where every step has a compensating step; if a step fails, the completed
--- steps are compensated in reverse order.
---
--- A step is `{ name, run = fn(ctx), compensate = fn(ctx) }`. `ctx` is one shared table the steps read and
--- write. `saga.run(steps, ctx)` returns `true, ctx` or `false, err, report` where `report` lists, per
--- step, what happened: `"done"`, `"failed"`, `"compensated"`, `"compensation_failed"` or `"skipped"`.
---
--- ```lua
--- local saga = require("lib.lua.patterns.saga")
--- local ok, err, report = saga.run({
---   { name = "reserve", run = function(c) c.id = reserve() end, compensate = function(c) release(c.id) end },
---   { name = "charge", run = function(c) charge(c.id) end, compensate = function(c) refund(c.id) end },
--- }, {})
--- ```
---
--- Status: idea pool. Compensation is the answer to a failure across systems that cannot share a
--- transaction (remote calls, several files). Inside one editor session a `try/finally`
--- (`lib.lua.context_manager`) or `lib.lua.patterns.unit_of_work` is usually enough.

require("lib.lua.patterns.saga.@types")

local M = {}

---@param steps Lib.Patterns.SagaStep[]
---@param ctx table|nil
---@return boolean ok
---@return any ctx_or_err
---@return table[]|nil report
function M.run(steps, ctx)
  ctx = ctx or {}
  local report = {}
  for i, step in ipairs(steps) do
    report[i] = { name = step.name or tostring(i), status = "skipped" }
  end
  for i, step in ipairs(steps) do
    local ok, err = pcall(step.run, ctx)
    if ok then
      report[i].status = "done"
    else
      report[i].status = "failed"
      report[i].err = err
      for j = i - 1, 1, -1 do
        local prev = steps[j]
        if prev.compensate then
          local cok, cerr = pcall(prev.compensate, ctx)
          report[j].status = cok and "compensated" or "compensation_failed"
          if not cok then
            report[j].err = cerr
          end
        end
      end
      return false, err, report
    end
  end
  return true, ctx
end

return M
