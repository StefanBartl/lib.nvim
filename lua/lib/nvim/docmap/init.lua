---@module 'lib.nvim.docmap'
--- Generated module map: scans an annotated Lua tree, builds an intermediate
--- representation, checks it for documentation drift, and renders it.
---
--- Written for `lib.nvim` but not tied to it — `opts.root`/`opts.source` point
--- it at any tree whose files carry `---@module`, so a plugin can generate its
--- own map with the same code. Nothing below hardcodes a module prefix, a
--- directory layout or a repo URL.
---
--- Pipeline:
---   scan   → Lib.Docmap.IR          (filesystem walk + header parse)
---   check  → Lib.Docmap.Finding[]   (drift between docs and reality)
---   render → html / mermaid / markdown / json
---
--- The IR is the contract between the halves: renderers never touch the
--- filesystem, and the scanner never knows what will be drawn.
---
--- Usage:
---   require("lib.nvim.docmap").generate({
---     root = "/path/to/repo",
---     source = "lua/lib",
---     title = "lib.nvim",
---     repo_url = "https://github.com/user/repo",
---   })
---
--- See @types/init.lua for Lib.Docmap.*.

require("lib.nvim.docmap.@types")

local scan = require("lib.nvim.docmap.scan")
local check = require("lib.nvim.docmap.check")
local mkdirp = require("lib.nvim.fs.mkdirp")
local json = require("lib.nvim.docmap.json")

local M = {}

M.scan = scan.scan
M.parse_header = scan.parse_header
M.check = check.run
M.tally = check.tally

M.render = {
  html = function(...)
    return require("lib.nvim.docmap.render.html")(...)
  end,
  mermaid = function(...)
    return require("lib.nvim.docmap.render.mermaid")(...)
  end,
  markdown = function(...)
    return require("lib.nvim.docmap.render.markdown")(...)
  end,
}

---Serialize the IR deterministically: nodes in `ir.order`, object keys in a
---fixed sequence, and every nested value through `docmap.json` rather than
---`vim.json.encode`, whose key order is unspecified.
---@param ir Lib.Docmap.IR
---@return string
function M.to_json(ir)
  local out = {}
  local function put(s)
    out[#out + 1] = s
  end
  local function str(s)
    return json.encode(s or "")
  end

  put('{\n  "meta": ')
  put(json.encode(ir.meta))
  put(',\n  "root": ' .. str(ir.root))
  put(',\n  "nodes": [\n')

  for i, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    local fields = {
      '"id": ' .. str(n.id),
      '"kind": ' .. str(n.kind),
      '"name": ' .. str(n.name),
      '"path": ' .. str(n.path),
      '"source": ' .. (n.source and str(n.source) or "null"),
      '"module": ' .. (n.module and str(n.module) or "null"),
      '"summary": ' .. str(n.summary),
      '"body": ' .. str(n.body),
      '"readme": ' .. (n.readme and str(n.readme) or "null"),
      '"types": ' .. json.encode(n.types),
      '"export": ' .. (n.export and str(n.export) or "null"),
      '"parent": ' .. (n.parent and str(n.parent) or "null"),
      '"depth": ' .. tostring(n.depth),
      '"children": ' .. (#n.children > 0 and json.encode(n.children) or "[]"),
    }
    put("    {" .. table.concat(fields, ", ") .. "}")
    put(i < #ir.order and ",\n" or "\n")
  end

  put("  ]\n}\n")
  return table.concat(out)
end

---Write `content` to `path`, creating parent directories.
---@param path string
---@param content string
---@return boolean ok
---@return string? err
local function write(path, content)
  local ok, err = mkdirp(vim.fs.dirname(path))
  if not ok then
    return false, err
  end
  local fd, ferr = io.open(path, "wb")
  if not fd then
    return false, ferr
  end
  fd:write(content)
  fd:close()
  return true
end

---Scan, check and render everything into `opts.out_dir`.
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.IR
---@return Lib.Docmap.Finding[]
---@return string[] written Repo-relative paths of the files written
function M.generate(opts)
  local ir = M.scan(opts)
  local findings = M.check(ir, opts)

  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local out_dir = opts.out_dir or "docs/map"
  local written = {}

  local artifacts = {
    ["module_map.json"] = M.to_json(ir),
    ["index.html"] = M.render.html(ir, findings, opts),
    ["overview.md"] = M.render.markdown(ir, findings, opts),
  }

  for name, content in pairs(artifacts) do
    local rel = out_dir .. "/" .. name
    local ok, err = write(root .. "/" .. rel, content)
    if not ok then
      error(("docmap: cannot write %s: %s"):format(rel, tostring(err)))
    end
    written[#written + 1] = rel
  end

  table.sort(written)
  return ir, findings, written
end

return M
