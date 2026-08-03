---@module 'lib.strategies.telemetry_wrap'
--- Thin caller instrumenting the `require("lib")` aggregate specifically —
--- the one piece `runtime-analysis.telemetry` (where the general-purpose
--- wrap/wrap_loaded machinery now lives, moved there from this repo) cannot
--- do on its own, because the aggregate's key set is metatable-hidden and
--- only `lib.strategies.control` knows how to enumerate and invalidate it.
---
---   local t = require("runtime-analysis.telemetry").new({ namespace = "lib.nvim" })
---   require("lib.strategies.telemetry_wrap").wrap(t)
---   t.start()
---   -- ... later ...
---   require("lib.strategies.telemetry_wrap").unwrap()
---   t.unwrap()
---
--- Built entirely on `inst.wrap()`, already public — no export from
--- runtime-analysis.telemetry exists (or needs to exist) just for this.
--- Soft dependency throughout (`pcall(require, "runtime-analysis.telemetry")`
--- would be the caller's job, not this module's — this module only ever
--- touches `require("lib")`, which is always present here): a caller without
--- runtime-analysis.nvim installed simply never reaches this file.
---
--- WHY THE MATERIALIZE STEP
--- The aggregate is empty to `pairs()` until a key is touched (see
--- `lib.strategies.control`'s own doc-comment) -- `rawset` shadows `__index`
--- so `inst.wrap()`'s `pairs()` walk actually sees the fields, and so the
--- resolved-key cache cannot hand out the pre-wrap value for a key this
--- module just wrapped.

local M = {}

---@type string[]
local lib_keys = {}

---Wrap the `require("lib")` aggregate into `inst`.
---@param inst RA.Telemetry.Instance
---@param wrap_opts? RA.Telemetry.WrapOpts
---@return integer registered
function M.wrap(inst, wrap_opts)
  local ok_lib, lib = pcall(require, "lib")
  if not ok_lib then
    return 0
  end
  local control = require("lib.strategies.control")

  local n = 0
  for _, key in ipairs(control.keys(lib)) do
    local ok_value, value = pcall(function()
      return lib[key]
    end)
    if ok_value and type(value) == "function" then
      rawset(lib, key, value)
      lib_keys[#lib_keys + 1] = key
    end
  end
  n = n + inst.wrap(lib, nil, wrap_opts)
  for _, key in ipairs(control.keys(lib)) do
    local ok_value, value = pcall(function()
      return lib[key]
    end)
    if ok_value and type(value) == "table" then
      n = n + inst.wrap(value, key, wrap_opts)
    end
  end

  return n
end

---Undo the materialize step above -- the wrapping itself is `inst.unwrap()`'s
---job, called separately; this only removes the `rawset` fields this module
---added, so the aggregate returns to being empty-until-touched again.
function M.unwrap()
  if #lib_keys == 0 then
    return
  end
  local ok_lib, lib = pcall(require, "lib")
  if ok_lib then
    for _, key in ipairs(lib_keys) do
      rawset(lib, key, nil)
    end
    require("lib.strategies.control").reset_cache()
  end
  lib_keys = {}
end

return M
