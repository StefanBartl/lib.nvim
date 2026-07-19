---@module 'lib.nvim.usercmd.composer.tree'
--- The route tree: the single source of truth read by dispatch, completion, and
--- docgen. A node has literal `children` and an optional terminal `route`.

---@class Lib.UserCmd.Composer.Node
---@field children table<string, Lib.UserCmd.Composer.Node>
---@field route?   Lib.UserCmd.Composer.Route
---@field token?   string   # the literal token that reaches this node (nil at root)

local M = {}

---@return Lib.UserCmd.Composer.Node
local function new_node(token)
  return { children = {}, token = token }
end

--- Build a tree from a list of routes.
---@param routes Lib.UserCmd.Composer.Route[]|nil
---@return Lib.UserCmd.Composer.Node root
function M.build(routes)
  local root = new_node(nil)
  for _, route in ipairs(routes or {}) do
    assert(type(route.path) == "table", "composer: every route needs a `path` array")
    assert(route.run ~= nil, "composer: route " .. table.concat(route.path, " ") .. " needs a `run` handler")
    local node = root
    for _, tok in ipairs(route.path) do
      node.children[tok] = node.children[tok] or new_node(tok)
      node = node.children[tok]
    end
    if node.route then
      error("composer: duplicate route for path '" .. table.concat(route.path, " ") .. "'")
    end
    node.route = route
  end
  return root
end

--- Walk `tokens` down the tree, consuming literal children greedily.
---@param root Lib.UserCmd.Composer.Node
---@param tokens string[]
---@return Lib.UserCmd.Composer.Node node   # deepest node reached
---@return integer consumed                 # number of tokens matched as literals
function M.walk(root, tokens)
  local node = root
  local i = 1
  while i <= #tokens do
    local child = node.children[tokens[i]]
    if not child then
      break
    end
    node = child
    i = i + 1
  end
  return node, i - 1
end

--- Sorted list of child literal tokens at a node.
---@param node Lib.UserCmd.Composer.Node
---@return string[]
function M.child_keys(node)
  local keys = {}
  for k in pairs(node.children) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- Depth-first walk yielding every terminal route with its full path, in a
--- stable (sorted) order. Used by docgen.
---@param root Lib.UserCmd.Composer.Node
---@param cb fun(route: Lib.UserCmd.Composer.Route)
function M.each_route(root, cb)
  local function rec(node)
    if node.route then
      cb(node.route)
    end
    for _, k in ipairs(M.child_keys(node)) do
      rec(node.children[k])
    end
  end
  rec(root)
end

return M
