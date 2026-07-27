---@module 'lib.nvim.docmap.render.mermaid'
--- Renders the top levels of the docmap IR as a Mermaid flowchart.
---
--- Scoped deliberately: Mermaid is worth having because GitHub renders it
--- natively, so the shape of the project is visible without leaving the code
--- host — but a graph of 250 nodes is unreadable, so this defaults to two
--- levels and treats the HTML page as the real navigator.

local M = {}

---Mermaid node ids must be identifier-safe.
---@param id string
---@return string
local function safe_id(id)
  return "n" .. (id:gsub("[^%w]", "_"))
end

---Mermaid labels break on quotes and brackets.
---@param s string
---@return string
local function label(s)
  return (s:gsub('"', "'"):gsub("[%[%]{}<>|]", ""))
end

---@param ir Lib.Docmap.IR
---@param _findings Lib.Docmap.Finding[]?
---@param opts { max_depth?: integer, direction?: string }?
---@return string
function M.render(ir, _findings, opts)
  opts = opts or {}
  local max_depth = opts.max_depth or 2
  local direction = opts.direction or "LR"

  local out = { "```mermaid", "flowchart " .. direction }

  for _, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    if n.depth <= max_depth and n.kind ~= "file" then
      local text = n.name
      if n.summary ~= "" and n.depth > 0 then
        local short = n.summary:sub(1, 44)
        if #n.summary > 44 then
          short = short:gsub("%s+%S*$", "") .. "…"
        end
        text = text .. "<br/><small>" .. short .. "</small>"
      end
      out[#out + 1] = ('  %s["%s"]'):format(safe_id(id), label(text))
    end
  end

  for _, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    if n.depth <= max_depth and n.kind ~= "file" and n.parent then
      local p = ir.nodes[n.parent]
      if p and p.depth <= max_depth and p.kind ~= "file" then
        out[#out + 1] = ("  %s --> %s"):format(safe_id(n.parent), safe_id(id))
      end
    end
  end

  out[#out + 1] = "```"
  return table.concat(out, "\n")
end

---Render the require graph between top-level module groups as a Mermaid
---flowchart.
---
---Aggregated to `opts.depth` (default 1) rather than drawn per module: the
---full graph is ~390 edges over ~250 nodes, which Mermaid will happily emit
---and nobody can read. Rolled up to the second level it says the thing a
---dependency diagram on a README should say — which parts of the library lean
---on which other parts — and the HTML map stays the place to go finer.
---
---Exists at all because `index.html` needs JavaScript and GitHub does not run
---it: without this, the dependency graph is invisible to anyone reading the
---repo on the code host rather than checking out the artifact.
---@param ir Lib.Docmap.IR
---@param opts { depth?: integer, direction?: string }?
---@return string
function M.render_deps(ir, opts)
  opts = opts or {}
  local depth = opts.depth or 1
  local direction = opts.direction or "LR"

  ---Walk up to the ancestor at `depth`, so `lua/lib/nvim/fs/read` and
  ---`lua/lib/nvim/fs` both collapse onto `lua/lib/nvim`.
  ---@param id string
  ---@return string?
  local function group_of(id)
    local node = ir.nodes[id]
    while node and node.depth > depth and node.parent do
      node = ir.nodes[node.parent]
    end
    if node and node.depth == depth then
      return node.id
    end
    return nil
  end

  local seen, pairs_seen = {}, {}
  local groups, links = {}, {}

  for _, edge in ipairs(ir.edges or {}) do
    if edge.kind == "require" then
      local a, b = group_of(edge.from), group_of(edge.to)
      -- Self-links are what a group's internal wiring collapses to; they say
      -- nothing about the shape between groups, which is the whole question.
      if a and b and a ~= b then
        local key = a .. "|" .. b
        if not pairs_seen[key] then
          pairs_seen[key] = true
          links[#links + 1] = { from = a, to = b }
        end
        for _, g in ipairs({ a, b }) do
          if not seen[g] then
            seen[g] = true
            groups[#groups + 1] = g
          end
        end
      end
    end
  end

  if #links == 0 then
    return ""
  end

  table.sort(groups)
  table.sort(links, function(x, y)
    if x.from ~= y.from then
      return x.from < y.from
    end
    return x.to < y.to
  end)

  local lines = { "```mermaid", "flowchart " .. direction }
  for _, g in ipairs(groups) do
    lines[#lines + 1] = ('  %s["%s"]'):format(
      safe_id(g),
      label(ir.nodes[g].module or ir.nodes[g].name)
    )
  end
  for _, l in ipairs(links) do
    lines[#lines + 1] = ("  %s --> %s"):format(safe_id(l.from), safe_id(l.to))
  end
  lines[#lines + 1] = "```"
  return table.concat(lines, "\n")
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
