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
      out[#out + 1] = ("  %s[\"%s\"]"):format(safe_id(id), label(text))
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

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
