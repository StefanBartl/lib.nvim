---@module 'lib.nvim.neotree.node'
---Neo-tree node extraction utilities.
---
---Pure, side-effect-free helpers for pulling paths and nodes out of a neo-tree
---`state`. They read the node's canonical `path` field (falling back to the node
---id, which for the filesystem source *is* the path) and never mutate anything.
---
---Neo-tree-specific by design: any plugin that wraps neo-tree (file trees,
---pickers, git bridges) tends to need the same "which node is under the cursor,
---what is its path, which nodes are marked" logic, so it is shared from here.

require("lib.nvim.neotree.node.@types")

local M = {}

---Return the node under the cursor from a neo-tree state, or nil.
---@param state table Neo-tree state (`state.tree` is the NuiTree).
---@return Lib.Neotree.RawNode|nil
function M.get_current(state)
  local tree = state and state.tree
  if not tree then
    return nil
  end
  local ok, node = pcall(tree.get_node, tree)
  if not ok then
    return nil
  end
  return node
end

---Resolve a node's filesystem path and whether it is a directory.
---Prefers `node.path`, falls back to the node id. Returns `("", false)` for
---nodes without a real path (message / loading / virtual nodes).
---@param node Lib.Neotree.RawNode|nil
---@return string path, boolean is_dir
function M.get_path(node)
  if not node then
    return "", false
  end
  local path = node.path
  if (type(path) ~= "string" or path == "") and node.get_id then
    local ok, id = pcall(node.get_id, node)
    if ok then
      path = id
    end
  end
  if type(path) ~= "string" or path == "" then
    return "", false
  end
  return path, vim.fn.isdirectory(path) == 1
end

---Collect the nodes an action should operate on: the explicitly marked nodes if
---any, otherwise the single node under the cursor. Never returns nil.
---@param state table Neo-tree state.
---@return Lib.Neotree.RawNode[]
function M.collect_nodes(state)
  local tree = state and state.tree
  if not tree then
    return {}
  end

  -- 1) Explicitly marked nodes (neo-tree stores their ids).
  local marks = state.explicitly_marked_node_ids or {}
  local marked = {}
  for node_id in pairs(marks) do
    local ok, node = pcall(tree.get_node, tree, node_id)
    if ok and node then
      marked[#marked + 1] = node
    end
  end
  if #marked > 0 then
    return marked
  end

  -- 2) Fallback: the node under the cursor.
  local node = M.get_current(state)
  if node then
    return { node }
  end
  return {}
end

---Extract filesystem paths and display names from a list of nodes. Nodes without
---a real path are skipped, so the two returned arrays stay index-aligned.
---@param nodes Lib.Neotree.RawNode[]
---@return string[] paths, string[] names
function M.extract_paths(nodes)
  local paths, names = {}, {}
  for i = 1, #(nodes or {}) do
    local node = nodes[i]
    local path = M.get_path(node)
    if path ~= "" then
      paths[#paths + 1] = path
      names[#names + 1] = node.name or vim.fn.fnamemodify(path, ":t")
    end
  end
  return paths, names
end

---Best-effort 1-based buffer line number for a node id. Uses the node's own
---line/row fields when present, otherwise searches the current buffer for the
---node's name. Returns nil when it cannot be determined.
---@param state table Neo-tree state.
---@param node_id string
---@return integer|nil
function M.get_line_number(state, node_id)
  local tree = state and state.tree
  if not tree then
    return nil
  end
  local ok, node = pcall(tree.get_node, tree, node_id)
  if not ok or not node then
    return nil
  end

  if type(node.line) == "number" then
    return node.line
  end
  if type(node.row) == "number" then
    return node.row
  end

  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local name = node.name or node.path or node.id
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for idx, line in ipairs(lines) do
    if line:find(name, 1, true) then
      return idx
    end
  end
  return nil
end

return M
