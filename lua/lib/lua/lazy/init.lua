---@module 'lib.lua.lazy'
--- Reusable helpers for explicit lazy-`require` of Lua modules: defer the
--- `require` to first use, load exactly once, keep hot-path overhead minimal.
--- Pure Lua, no dependencies. See README for the full rationale.
---
---   local lazy = require("lib.lua.lazy")
---   local mymod = lazy.module("mymodule")   -- wrapper; call .get() for the module
---   local other = lazy.require("othermod")  -- the module itself, cached (recommended)
---   local do_work = lazy.fn("mymodule", "do_work")  -- rebinds after first call

local LAZY = {}

---Creates a lazy module wrapper.
---The wrapped module is required only on first access and then cached.
---
---@param module_name string
---The module name passed to require(), e.g. "vim.loop" or "my.plugin.core".
---
---@return Lib.Lazy
---A lazy module object exposing a get() method.
function LAZY.module(module_name)
  ---@type Lib.Lazy
  local lazy = {
    _value = nil,
    _loader = function()
      return (require(module_name))
    end,
  }

  ---Returns the loaded module.
  ---Loads it exactly once on first invocation.
  ---
  ---@return table
  function lazy.get()
    if not lazy._value then
      -- The require call is executed once.
      -- Subsequent calls return the cached value.
      lazy._value = lazy._loader()
    end
    return lazy._value
  end

  return lazy
end

---Creates a lazy function wrapper.
---The target module is required on first call and the function is rebound.
---
---This removes the lazy-check from the hot path after the first call.
---
---@param module_name string
---@param fn_name string
---@return fun(...): any
function LAZY.fn(module_name, fn_name)
  ---@type fun(...): any
  local wrapped

  wrapped = function(...)
    local mod = require(module_name)
    local real_fn = mod[fn_name]

    -- Rebind the wrapper to the real function
    wrapped = real_fn

    return real_fn(...)
  end

  return function(...)
    return wrapped(...)
  end
end

---Creates a lazy module with type casting for LSP support.
---Returns the actual module (not the wrapper) for better type inference.
---
---Usage: put a `---@type MyModule.Type` annotation on the call site so the
---language server treats the result as that module.
---
---@generic T
---@param module_name string
---@return T
function LAZY.require(module_name)
  return LAZY.module(module_name).get()
end

--- CDX: `LAZY.typed` is byte-equivalent to `LAZY.require`, has no callers in
--- CDX: this repo, and is absent from README / docs/API / doc. Candidate for
--- CDX: removal; kept pending an external-consumer check.
---Resolve `module_name` lazily and return the module itself (not the wrapper).
---Equivalent to `LAZY.require`.
---@generic T
---@param module_name string The module name passed to require()
---@return T
function LAZY.typed(module_name)
  return LAZY.module(module_name).get()
end

---@type Lib.Lazy
return LAZY
