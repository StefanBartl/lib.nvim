---@module 'lib.nvim.docmap.render.dot'
--- Renders the require or call graph as Graphviz DOT.
---
--- The third renderer for the same edges, and it exists because the other two
--- cannot do what Graphviz does. The HTML page lays boxes out in BFS layers —
--- deterministic, fast, and unable to route an edge around anything. Mermaid
--- is rendered by the code host, which is worth a lot and costs all control
--- over the result. `dot` gives real edge routing, rank constraints, clusters,
--- and an output that goes in a slide or a paper at any size.
---
--- Deliberately *not* wired to a `dot` binary. Shelling out would mean a new
--- external dependency, a temp file, and a failure mode ("dot not found") for
--- a feature whose whole output is text the caller can pipe wherever they
--- like. `:LibMap dot` opens it in a scratch buffer; what happens next is the
--- user's business.

local M = {}

---Graphviz ids must be quoted or identifier-safe; quoting is simpler than
---mangling and keeps the original path readable in the output.
---@param s string
---@return string
local function q(s)
  return '"' .. tostring(s):gsub('"', '\\"') .. '"'
end

---The top-level grouping a node belongs to, used for `subgraph cluster_*`.
---Nodes are clustered by their ancestor at `depth`, which is what turns a
---flat hairball into something with visible regions.
---@param ir Lib.Docmap.IR
---@param id string
---@param depth integer
---@return string?
local function group_of(ir, id, depth)
  local node = ir.nodes[id]
  while node and node.depth > depth and node.parent do
    node = ir.nodes[node.parent]
  end
  if node and node.depth == depth then
    return node.id
  end
  return nil
end

---@param ir Lib.Docmap.IR
---@param id string
---@return string
local function label_of(ir, id)
  local node = ir.nodes[id]
  return (node and (node.module or node.name)) or id
end

---Render `kind` edges as a DOT digraph.
---
---`opts.scope` restricts the graph to one node and everything reachable from
---it; without it the whole tree is emitted, which is legitimate for `dot`
---(unlike for the HTML layout) because Graphviz is built for graphs this size.
---@param ir Lib.Docmap.IR
---@param opts { kind?: "require"|"call", scope?: string, hops?: integer, cluster_depth?: integer, rankdir?: string }?
---@return string
function M.render(ir, opts)
  opts = opts or {}
  local kind = opts.kind == "call" and "call" or "require"
  local cluster_depth = opts.cluster_depth or 2
  local rankdir = opts.rankdir or "LR"

  -- Node granularity differs by edge kind: a require graph is between
  -- modules, a call graph between functions. Keying on the same string the
  -- rest of docmap uses ("<node id>#<fn>") keeps the two paths identical
  -- below this point.
  local function endpoints(e)
    if kind == "call" then
      return e.from .. "#" .. tostring(e.from_fn), e.to .. "#" .. tostring(e.to_fn)
    end
    return e.from, e.to
  end

  local function owner(key)
    return kind == "call" and (key:match("^(.*)#") or key) or key
  end

  local function display(key)
    if kind == "call" then
      local node_id, fn = key:match("^(.*)#([^#]*)$")
      return ("%s\n%s"):format(label_of(ir, node_id or key), fn or "?")
    end
    return label_of(ir, key)
  end

  local wanted = {}
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == kind then
      local a, b = endpoints(e)
      wanted[a] = true
      wanted[b] = true
    end
  end

  -- Scope: the neighbourhood of `scope` within `hops`, in either direction,
  -- so "the graph around X" is a subgraph rather than a filter that leaves
  -- dangling edges behind.
  --
  -- Bounded on purpose. Unbounded reachability sounds like the right answer
  -- and is not: measured over this tree it kept 750 of 872 lines, because in
  -- a connected dependency graph almost everything reaches almost everything.
  -- A scope that excludes nothing is not a scope.
  if opts.scope then
    local hops = opts.hops or 2
    local adj = {}
    local function link(a, b)
      local list = adj[a]
      if not list then
        list = {}
        adj[a] = list
      end
      list[#list + 1] = b
    end
    for _, e in ipairs(ir.edges or {}) do
      if e.kind == kind then
        local a, b = endpoints(e)
        -- Undirected on purpose: "the graph around X" means both what X
        -- reaches and what reaches X.
        link(a, b)
        link(b, a)
      end
    end
    local seeds = {}
    for key in pairs(wanted) do
      if owner(key) == opts.scope then
        seeds[#seeds + 1] = key
      end
    end
    local seen, queue, qi = {}, {}, 1
    for _, seed in ipairs(seeds) do
      seen[seed] = 0
      queue[#queue + 1] = seed
    end
    while qi <= #queue do
      local cur = queue[qi]
      qi = qi + 1
      if seen[cur] < hops then
        for _, nxt in ipairs(adj[cur] or {}) do
          if seen[nxt] == nil then
            seen[nxt] = seen[cur] + 1
            queue[#queue + 1] = nxt
          end
        end
      end
    end
    wanted = seen
  end

  local keys = {}
  for key in pairs(wanted) do
    keys[#keys + 1] = key
  end
  table.sort(keys)

  local out = {
    ("// %s graph of %s — generated by lib.nvim.docmap"):format(kind, ir.meta.title or "the map"),
    "digraph docmap {",
    ("  rankdir=%s;"):format(rankdir),
    '  graph [fontname="sans-serif", nodesep=0.3, ranksep=0.6];',
    '  node  [fontname="sans-serif", shape=box, style=rounded, fontsize=10];',
    '  edge  [fontname="sans-serif", fontsize=8, color="#888888"];',
    "",
  }

  -- Group the nodes into clusters, and emit the ungrouped ones plainly rather
  -- than inventing a cluster for them.
  local by_group, loose = {}, {}
  for _, key in ipairs(keys) do
    local g = group_of(ir, owner(key), cluster_depth)
    if g then
      by_group[g] = by_group[g] or {}
      table.insert(by_group[g], key)
    else
      loose[#loose + 1] = key
    end
  end

  -- A cluster of one is a box with a second box drawn around it — pure
  -- noise. Those members go loose instead.
  local group_names = {}
  for g, members in pairs(by_group) do
    if #members > 1 then
      group_names[#group_names + 1] = g
    else
      loose[#loose + 1] = members[1]
      by_group[g] = nil
    end
  end
  table.sort(group_names)
  table.sort(loose)

  for i, g in ipairs(group_names) do
    out[#out + 1] = ("  subgraph cluster_%d {"):format(i)
    out[#out + 1] = ("    label=%s;"):format(q(label_of(ir, g)))
    out[#out + 1] = '    style="rounded"; color="#cccccc";'
    for _, key in ipairs(by_group[g]) do
      out[#out + 1] = ("    %s [label=%s];"):format(q(key), q(display(key)))
    end
    out[#out + 1] = "  }"
  end
  for _, key in ipairs(loose) do
    out[#out + 1] = ("  %s [label=%s];"):format(q(key), q(display(key)))
  end

  out[#out + 1] = ""

  -- Edges last, and sorted, so the output is byte-stable for the same IR —
  -- the same discipline the JSON artifact is held to, for the same reason:
  -- a diff should mean something changed.
  local lines = {}
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == kind then
      local a, b = endpoints(e)
      if wanted[a] and wanted[b] and a ~= b then
        local attrs = {}
        if e.deferred then
          attrs[#attrs + 1] = 'style=dashed, label="lazy"'
        end
        if e.confidence == "heuristic" then
          attrs[#attrs + 1] = 'style=dotted, label="guess"'
        end
        lines[#lines + 1] = ("  %s -> %s%s;"):format(
          q(a),
          q(b),
          #attrs > 0 and (" [" .. table.concat(attrs, ", ") .. "]") or ""
        )
      end
    end
  end
  table.sort(lines)
  local seen_line = {}
  for _, l in ipairs(lines) do
    if not seen_line[l] then
      seen_line[l] = true
      out[#out + 1] = l
    end
  end

  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
