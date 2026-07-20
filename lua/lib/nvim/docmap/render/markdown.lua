---@module 'lib.nvim.docmap.render.markdown'
--- Renders the docmap IR as a Markdown overview: a Mermaid namespace graph,
--- a nested module index with README links, and the drift report.
---
--- This is the format that renders on the code host itself, so it is what a
--- reader who never opens the HTML page still sees.

local M = {}

local mermaid = require("lib.nvim.docmap.render.mermaid")

---Escape the characters that break a Markdown table cell.
---@param s string?
---@return string
local function cell(s)
  if not s or s == "" then
    return ""
  end
  return (s:gsub("|", "\\|"):gsub("\n", " "))
end

---Path from the artifact back to a repo-relative target.
---@param out_dir string
---@param target string
---@return string
local function rel(out_dir, target)
  local depth = select(2, out_dir:gsub("[^/]+", "")) or 0
  return string.rep("../", depth) .. target
end

---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
---@return string
function M.render(ir, findings, opts)
  local out_dir = opts.out_dir or "docs/map"
  local o = {}
  local function put(s)
    o[#o + 1] = s
  end

  local c = ir.meta.counts
  put("# " .. ir.meta.title .. " — module map\n")
  put("> **Generated** by `lib.nvim.docmap`. Do not edit by hand — run `:LibMap`\n"
    .. "> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.\n")
  put(("**%d modules** · %d namespaces · %d helper files\n")
    :format(c.module or 0, c.namespace or 0, c.file or 0))
  put("The [interactive map](index.html) has filtering, full descriptions and\n"
    .. "source links; this page is the version the code host renders directly.\n")

  put("\n## Namespaces\n")
  put(mermaid.render(ir, findings, { max_depth = 2 }))

  put("\n\n## Modules\n")
  put("| Module | Description | Docs |")
  put("|---|---|---|")

  for _, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    if n.kind ~= "file" and id ~= ir.root then
      local indent = string.rep("&nbsp;&nbsp;", math.max(0, n.depth - 1))
      local name = n.module and ("`" .. n.module .. "`") or ("`" .. n.name .. "`")
      local links = {}
      if n.readme then
        links[#links + 1] = "[README](" .. rel(out_dir, n.readme) .. ")"
      end
      if n.source then
        links[#links + 1] = "[src](" .. rel(out_dir, n.source) .. ")"
      end
      put(("| %s%s | %s | %s |"):format(indent, name, cell(n.summary), table.concat(links, " · ")))
    end
  end

  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end

  put("\n## Drift\n")
  put(("%d errors · %d warnings · %d info\n"):format(t.error, t.warn, t.info))

  if t.error + t.warn == 0 then
    put("No errors or warnings.\n")
  else
    put("| Severity | Check | Message |")
    put("|---|---|---|")
    for _, f in ipairs(findings) do
      if f.severity ~= "info" then
        put(("| %s | `%s` | %s |"):format(f.severity, f.check, cell(f.message)))
      end
    end
  end

  if t.info > 0 then
    put("\n<details>\n<summary>" .. t.info .. " informational findings</summary>\n")
    put("\n| Check | Message |")
    put("|---|---|")
    for _, f in ipairs(findings) do
      if f.severity == "info" then
        put(("| `%s` | %s |"):format(f.check, cell(f.message)))
      end
    end
    put("\n</details>")
  end

  return table.concat(o, "\n") .. "\n"
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.render(...)
  end,
})
