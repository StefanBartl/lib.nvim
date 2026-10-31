---@module 'lib.lua.patterns.decorator'
--- Decorator: add behaviour around a function without changing its callers.
---
--- A decorator is `function(fn) -> fn`. `wrap(fn, d1, d2, ...)` applies them so that the first listed is
--- the outermost. Ready-made ones: `before`, `after`, `guard`, `timed`.
---
--- ```lua
--- local decorator = require("lib.lua.patterns.decorator")
--- local save = decorator.wrap(write_file,
---   decorator.guard(function(path) return path ~= "" end, function() return nil, "empty path" end),
---   decorator.before(function(path) log("saving " .. path) end)
--- )
--- ```

require("lib.lua.patterns.decorator.@types")

local M = {}

local unpack = table.unpack or unpack

---Pack with an explicit count so trailing nils survive (`table.pack` is missing on plain LuaJIT).
local function pack(...)
  return { n = select("#", ...), ... }
end

---`wrap(fn, d1, d2)` == `d1(d2(fn))`.
---@param fn function
---@param ... fun(fn: function): function
---@return function
function M.wrap(fn, ...)
  local decorators = { ... }
  for i = #decorators, 1, -1 do
    fn = decorators[i](fn)
  end
  return fn
end

---Run `hook(...)` before the call (its return value is ignored).
---@param hook function
---@return fun(fn: function): function
function M.before(hook)
  return function(fn)
    return function(...)
      hook(...)
      return fn(...)
    end
  end
end

---Run `hook(results_table, ...)` after the call; the original results are returned unchanged.
---@param hook function
---@return fun(fn: function): function
function M.after(hook)
  return function(fn)
    return function(...)
      local res = pack(...)
      local out = pack(fn(...))
      hook(out, unpack(res, 1, res.n))
      return unpack(out, 1, out.n)
    end
  end
end

---Only call `fn` when `predicate(...)` is truthy; otherwise return `otherwise(...)` (default: nothing).
---@param predicate function
---@param otherwise function|nil
---@return fun(fn: function): function
function M.guard(predicate, otherwise)
  return function(fn)
    return function(...)
      if predicate(...) then
        return fn(...)
      end
      if otherwise then
        return otherwise(...)
      end
    end
  end
end

---Report the duration of each call in milliseconds to `sink(ms, ...)`. The clock is injectable.
---@param sink function
---@param clock (fun(): number)|nil  # seconds, default `os.clock`
---@return fun(fn: function): function
function M.timed(sink, clock)
  clock = clock or os.clock
  return function(fn)
    return function(...)
      local t0 = clock()
      local out = pack(pcall(fn, ...))
      sink((clock() - t0) * 1000, ...)
      if not out[1] then
        error(out[2], 0)
      end
      return unpack(out, 2, out.n)
    end
  end
end

return M
