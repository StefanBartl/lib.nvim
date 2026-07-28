# `lib.nvim.neotree.node`

Neo-tree node extraction utilities.

Pure, side-effect-free helpers for pulling paths and nodes out of a Neo-tree
`state`. They read a node's canonical `path` field (falling back to the
node's id, which for the filesystem source *is* the path) and never mutate
anything. Neo-tree-specific by design: any plugin that wraps Neo-tree (file
trees, pickers, git bridges) tends to need the same "which node is under the
cursor, what is its path, which nodes are marked" logic, so it's shared here.

## Usage

```lua
local node = require("lib.nvim.neotree.node")

local current = node.get_current(state)          --> Neo-tree node under the cursor, or nil
local path, is_dir = node.get_path(current)       --> "" , false if unresolvable
local nodes = node.collect_nodes(state)            --> marked nodes, or [cursor node], never nil
local paths, names = node.extract_paths(nodes)      --> index-aligned string[] pairs
local line = node.get_line_number(state, node_id)   --> 1-based line, or nil
```

### `get_current(state)`

The node under the cursor (`state.tree:get_node()`), or `nil` if `state` or
`state.tree` is missing, or the lookup errors.

### `get_path(node)`

Resolves `node.path`, falling back to `node:get_id()` when `path` is missing
or empty. Returns `"", false` for nodes without a real path (message /
loading / virtual nodes) — never `nil`. The second return is whether
`vim.fn.isdirectory(path) == 1`.

### `collect_nodes(state)`

The nodes an action should operate on: the explicitly marked nodes
(`state.explicitly_marked_node_ids`) if any exist, otherwise a single-element
list with the node under the cursor. Returns `{}` (never `nil`) if there's
nothing to act on.

### `extract_paths(nodes)`

Two index-aligned arrays — `paths` and display `names` (`node.name`, falling
back to the path's basename) — built from `nodes`. Nodes without a resolvable
path are skipped, so the two arrays stay the same length as each other but
may be shorter than `nodes`.

### `get_line_number(state, node_id)`

Best-effort 1-based line number for `node_id` in the *current* buffer. Uses
the node's own `line`/`row` field if present; otherwise searches the current
buffer's lines for the node's `name`/`path`/`id` as a plain substring.
Returns `nil` if the node can't be found, or no line matches.
