---@module 'lib.lua.lazy'
--- Provides reusable helpers for safe and explicit lazy-loading of Lua modules in Neovim.
--
--- Design goals:
---   Avoid eager requires at file scope
---   Load modules exactly once, on first actual use
---   Keep hot-path overhead minimal and predictable
---   Be copyable across personal Neovim plugins without dependencies
--
---      local lazy = require("lib.lua.lazy")
--
---  Usage 'module': Returns the loaded module. Loads it exactly once on first invocation.
---      local mymod = lazy.module("mymodule")
---      mymod.get().do_work()
--
---  Usage 'fn': Creates a lazy function wrapper. The target module is required on first call and the function is rebound.
---      local do_work = lazy.fn("mymodule", "do_work")
---      do_work(42)

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
---Usage:
---```lua
---local mod = lazy.require("my.module", "MyModule.Type")
---```
---
---@generic T
---@param module_name string
---@return T
function LAZY.require(module_name)
  return LAZY.module(module_name).get()
end

---Creates a lazy module wrapper with type casting.
---Use this when you need LSP support for the loaded module.
---
---@generic T
---@param module_name string The module name passed to require()
---@return T
function LAZY.typed(module_name)
  local lazy = LAZY.module(module_name)
  return lazy.get()
end


---@type Lib.Lazy
return LAZY

