---@meta
---@module 'lib.nvim.neotree.node.@types'

---A neo-tree tree node (NuiTree node). Only the fields these helpers read are
---described here; neo-tree attaches many more at runtime.
---@class Lib.Neotree.RawNode
---@field path? string           Absolute filesystem path (canonical field).
---@field name? string           Display name.
---@field type? string           "file" | "directory" | "message" | …
---@field id? string             Node id (for the filesystem source, the path).
---@field get_id? fun(self):string
---@field line? integer
---@field row? integer

---Reusable helpers for extracting paths and nodes from neo-tree state.
---Neo-tree-specific (they read a neo-tree `state`/node), so they live here rather
---than in a generic namespace; multiple plugins wrapping neo-tree can share them.
---@class Lib.Neotree.Node
---@field get_current fun(state: table): Lib.Neotree.RawNode|nil
---@field get_path fun(node: Lib.Neotree.RawNode|nil): (string, boolean)
---@field collect_nodes fun(state: table): Lib.Neotree.RawNode[]
---@field extract_paths fun(nodes: Lib.Neotree.RawNode[]): (string[], string[])
---@field get_line_number fun(state: table, node_id: string): integer|nil

return {}
