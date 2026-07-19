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
---   scan       → Lib.Docmap.IR          (filesystem walk + header parse)
---   luals      → merges into the IR     (opt-in: @class/@alias detail, type edges)
---   check      → Lib.Docmap.Finding[]   (drift between docs and reality)
---   render     → html / mermaid / markdown / json
---
--- The IR is the contract between the halves: renderers never touch the
--- filesystem, and the scanner never knows what will be drawn.
---
--- Two ways to drive the pipeline:
---   generate(opts)  — one-shot: scan, check, render, write to opts.out_dir.
---                      What :LibMap and the CI/hook CLI use.
---   install(opts)   — live: keeps a scanned IR in memory, optionally
---                      rescanning on save, with subscribers. What another
---                      plugin's source code reaches for instead of parsing
---                      module_map.json off disk.
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

---`scan()` + optional LuaLS merge (`opts.luals`) + `check()`, in one call.
---The shared step `generate()` and `install()`'s rescan both build on, so the
---enrichment wiring exists in exactly one place rather than being repeated at
---every entry point that needs a fully-formed IR.
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.IR
---@return Lib.Docmap.Finding[]
function M.scan_full(opts)
  local ir = M.scan(opts)
  ir.edges = ir.edges or {}

  local luals_err
  if opts.luals then
    local luals = require("lib.nvim.docmap.luals")
    local doc_json, err = luals.run(opts.root, opts.source or "lua", { timeout_ms = opts.luals_timeout_ms })
    if doc_json then
      luals.merge(ir, doc_json, opts.source or "lua")
    else
      -- Enrichment failing is not a reason to fail the whole scan — everything
      -- scan() produced is still valid. Surface it as a finding instead of
      -- letting it vanish silently.
      luals_err = err
    end
  end

  local findings = M.check(ir, opts)
  if luals_err then
    table.insert(findings, 1, {
      severity = "info",
      check = "luals-unavailable",
      node = nil,
      message = "opts.luals was set but enrichment did not run: " .. tostring(luals_err),
    })
  end
  return ir, findings
end

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
      '"types_detail": ' .. (n.types_detail and json.encode(n.types_detail) or "null"),
      '"export": ' .. (n.export and str(n.export) or "null"),
      '"parent": ' .. (n.parent and str(n.parent) or "null"),
      '"depth": ' .. tostring(n.depth),
      '"children": ' .. (#n.children > 0 and json.encode(n.children) or "[]"),
    }
    put("    {" .. table.concat(fields, ", ") .. "}")
    put(i < #ir.order and ",\n" or "\n")
  end

  put("  ],\n  \"edges\": ")
  put(json.encode(ir.edges or {}))
  put("\n}\n")
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

---Render and write `module_map.json`/`index.html`/`overview.md` into
---`opts.out_dir` for an already-scanned `ir`/`findings` pair. Split out of
---`generate()` so a caller that already has a fresh IR (e.g. `:LibMap full`,
---which scans through a registry handle to also update its cached IR) does
---not have to scan a second time just to get the artifacts written.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
---@return string[] written Repo-relative paths of the files written
function M.write_artifacts(ir, findings, opts)
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
  return written
end

---Scan, check and render everything into `opts.out_dir`.
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.IR
---@return Lib.Docmap.Finding[]
---@return string[] written Repo-relative paths of the files written
function M.generate(opts)
  local ir, findings = M.scan_full(opts)
  local written = M.write_artifacts(ir, findings, opts)
  return ir, findings, written
end

---Install a live handle: a scanned IR kept in memory, optionally rescanned on
---save, with `on_change` subscribers. See `lua/lib/nvim/docmap/registry.lua`
---for the collision reason this is a separate module from `command.lua`
---rather than `install()` auto-registering a usercmd itself.
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.Handle
function M.install(opts)
  return require("lib.nvim.docmap.registry").install(opts)
end

---Tear down a handle from `install()`. Accepts the handle itself or its root
---path. Idempotent: uninstalling twice is a no-op, not an error.
---@param handle_or_root Lib.Docmap.Handle|string
---@return boolean uninstalled
function M.uninstall(handle_or_root)
  return require("lib.nvim.docmap.registry").uninstall(handle_or_root)
end

return M
