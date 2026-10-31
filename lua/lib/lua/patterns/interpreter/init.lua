---@module 'lib.lua.patterns.interpreter'
--- Interpreter: evaluate a small grammar by walking its tree with one evaluator per node type.
---
--- `interpreter.new(rules)` returns `eval(node, env)`. Each rule is `fn(node, eval, env)`; it calls
--- `eval(child, env)` for sub-nodes. A node is a table with a `type` field. Parsing is not part of this
--- module: the tree comes from wherever you build it.
---
--- ```lua
--- local interpreter = require("lib.lua.patterns.interpreter")
--- local eval = interpreter.new({
---   num = function(n) return n.value end,
---   add = function(n, ev, env) return ev(n.left, env) + ev(n.right, env) end,
---   var = function(n, _, env) return env[n.name] end,
--- })
--- eval({ type = "add", left = { type = "num", value = 1 }, right = { type = "var", name = "x" } }, { x = 41 })
--- --> 42
--- ```
---
--- Status: idea pool. Worth it only for a real mini-language (filters, query expressions) with several
--- node types; a single `load()`ed Lua expression or a pattern match usually does the job.

require("lib.lua.patterns.interpreter.@types")

local M = {}

---@param rules table<string, fun(node: table, eval: function, env: any): any>
---@return fun(node: table, env: any): any
function M.new(rules)
  local function eval(node, env)
    if type(node) ~= "table" or node.type == nil then
      error("interpreter: node must be a table with a 'type' field", 2)
    end
    local rule = rules[node.type]
    if not rule then
      error(("interpreter: no rule for node type %q"):format(tostring(node.type)), 2)
    end
    return rule(node, eval, env)
  end
  return eval
end

return M
