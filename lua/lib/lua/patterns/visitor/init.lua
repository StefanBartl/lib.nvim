---@module 'lib.lua.patterns.visitor'
--- Visitor: add operations to a node structure from outside, with one handler per node kind.
---
--- `visitor.new(handlers, opts)` returns `visit(node, ...)` that dispatches on `node.type` (or
--- `opts.kind(node)`); `opts.default` handles kinds without a handler. `visitor.walk(root, children,
--- fn)` visits a tree depth first; `fn` may return `false` to skip the children of that node.
---
--- ```lua
--- local visitor = require("lib.lua.patterns.visitor")
--- local count = {}
--- visitor.walk(tree, function(n) return n.children end, function(n)
---   count[n.type] = (count[n.type] or 0) + 1
--- end)
---
--- local describe = visitor.new({
---   heading = function(n) return "# " .. n.text end,
---   para = function(n) return n.text end,
--- }, { default = function(n) return "<" .. n.type .. ">" end })
--- ```
---
--- Status: idea pool. Lua tables are open: `handlers[node.type](node)` already is the visitor, and tree
--- walks are short. This module may bring no benefit beyond naming the idea.

require("lib.lua.patterns.visitor.@types")

local M = {}

---@param handlers table<string, function>
---@param opts { kind: (fun(node: any): string)|nil, default: function|nil }|nil
---@return fun(node: any, ...): any
function M.new(handlers, opts)
  opts = opts or {}
  local kind_of = opts.kind or function(node)
    return node.type
  end
  return function(node, ...)
    local fn = handlers[kind_of(node)] or opts.default
    if not fn then
      error(("visitor: no handler for kind %q"):format(tostring(kind_of(node))), 2)
    end
    return fn(node, ...)
  end
end

---Depth-first, pre-order walk. `fn(node, depth)` returning exactly `false` skips that node's children.
---@param root any
---@param children fun(node: any): any[]|nil
---@param fn fun(node: any, depth: integer): boolean|nil
function M.walk(root, children, fn)
  local function go(node, depth)
    if fn(node, depth) == false then
      return
    end
    for _, child in ipairs(children(node) or {}) do
      go(child, depth + 1)
    end
  end
  go(root, 0)
end

return M
