---@module 'lib.lua.patterns.bridge'
--- Bridge: split an abstraction from its implementation so both vary independently.
---
--- The abstraction is a table of functions `(impl, ...)`; the implementor is any table that provides the
--- primitive operations the abstraction needs. `bridge.new` binds the two and checks the required
--- primitives up front.
---
--- ```lua
--- local bridge = require("lib.lua.patterns.bridge")
--- local report = { -- abstraction: what to say
---   title = function(out, text)
---     out.line(text)
---     out.line(("="):rep(#text))
---   end,
--- }
--- local to_buffer = { line = function(s) vim.api.nvim_buf_set_lines(0, -1, -1, false, { s }) end }
--- local r = bridge.new(report, to_buffer, { "line" })
--- r.title("Hello")
--- ```
---
--- Status: idea pool. It pays off when two axes of variation are real (here: report kinds x outputs).
--- With one axis a plain strategy table is enough.

require("lib.lua.patterns.bridge.@types")

local M = {}

---@param abstraction table<string, function>
---@param impl table
---@param required string[]|nil  # primitives `impl` must provide
---@return table<string, function>
function M.new(abstraction, impl, required)
  for _, name in ipairs(required or {}) do
    if type(impl[name]) ~= "function" then
      error(("bridge.new: implementor lacks %q"):format(name), 2)
    end
  end
  local out = {}
  for name, fn in pairs(abstraction) do
    out[name] = function(...)
      return fn(impl, ...)
    end
  end
  return out
end

return M
