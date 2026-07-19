---@module 'lib.nvim.docmap.check'
--- Drift checks over a docmap IR.
---
--- This is the half of docmap that earns its keep. A rendered map is a nice
--- artifact; a map that *fails* when documentation and reality diverge is a
--- test. Every check here corresponds to a defect class actually observed in
--- the tree it was written against — most sharply `lib.find_root`, which was
--- declared on the aggregate `Lib` class but wired into none of the export
--- strategies, so the published type was simply false and stayed that way
--- until it was found by accident.
---
--- Checks are pluggable: the generic ones below make no assumption beyond
--- "annotated Lua tree", and anything repo-specific (aggregator wiring, for
--- instance) is passed in through `opts.extra_checks` so another plugin can
--- reuse this file without inheriting lib.nvim's conventions.

local M = {}

local uv = vim.uv or vim.loop

---@alias Lib.Docmap.Severity "error"|"warn"|"info"

---@param list Lib.Docmap.Finding[]
---@param severity Lib.Docmap.Severity
---@param check string
---@param node_id string?
---@param message string
local function add(list, severity, check, node_id, message)
  list[#list + 1] = { severity = severity, check = check, node = node_id, message = message }
end

---Derive the module path a file *should* declare from where it lives.
---@param path string Repo-relative, forward slashes
---@param lua_root string
---@return string|nil
local function expected_module(path, lua_root)
  local prefix = lua_root .. "/"
  if path:sub(1, #prefix) ~= prefix then
    return nil
  end
  local rest = path:sub(#prefix + 1)
  rest = rest:gsub("%.lua$", ""):gsub("/init$", "")
  return (rest:gsub("/", "."))
end

--- Every module and helper file should say what it is in one sentence — that
--- sentence is what the map, the README tables and the vimdoc all render.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_summaries(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind ~= "namespace" then
      if not node.module then
        add(findings, "error", "missing-module-tag", id, ("%s has no ---@module annotation"):format(node.source or id))
      elseif node.summary == "" then
        add(findings, "warn", "missing-summary", id, ("%s has ---@module but no description line"):format(node.source or id))
      end
    end
  end
end

--- A copy-pasted module header that still names its origin is invisible in
--- review and actively misleading in the map.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_module_paths(ir, findings, opts)
  local lua_root = opts.lua_root or "lua"
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.source then
      local want = expected_module(node.source, lua_root)
      if want and want ~= node.module then
        add(findings, "error", "module-path-mismatch", id,
          ("%s declares @module '%s' but lives at '%s'"):format(node.source, node.module, want))
      end
    end
  end
end

--- Not every module needs a README, but the absence should be a decision
--- rather than an oversight, so this is reported at `info`.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_readmes(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind == "module" and not node.readme then
      add(findings, "info", "missing-readme", id, ("%s has no README.md"):format(node.path))
    end
  end
end

--- README module tables in this repo carry deep relative links that nothing
--- validates today; a moved module silently leaves 404s behind.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_readme_links(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.readme then
      local abs = root .. "/" .. node.readme
      local fd = io.open(abs, "r")
      if fd then
        local content = fd:read("*a")
        fd:close()
        local base = node.path
        local seen = {}
        for target in content:gmatch("%]%(([^)#]+)%)") do
          if not target:match("^%a+://") and not target:match("^#") and not seen[target] then
            seen[target] = true
            -- Resolve relative to the README's own directory.
            local joined = base .. "/" .. target
            local parts, stack = {}, {}
            for seg in joined:gmatch("[^/]+") do
              parts[#parts + 1] = seg
            end
            for _, seg in ipairs(parts) do
              if seg == ".." then
                table.remove(stack)
              elseif seg ~= "." then
                stack[#stack + 1] = seg
              end
            end
            local resolved = table.concat(stack, "/")
            if not uv.fs_stat(root .. "/" .. resolved) then
              add(findings, "warn", "dead-readme-link", id,
                ("%s links to '%s' which does not exist"):format(node.readme, target))
            end
          end
        end
      end
    end
  end
end

--- A module that exists on disk but is required by nothing above it was
--- either written and never wired up, or orphaned by a refactor.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_orphans(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  -- Collect every `require("...")` string anywhere in the tree once.
  local required = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.source then
      local fd = io.open(root .. "/" .. node.source, "r")
      if fd then
        for line in fd:lines() do
          for mod in line:gmatch("require%s*%(?%s*['\"]([%w%._%-]+)['\"]") do
            required[mod] = true
          end
        end
        fd:close()
      end
    end
  end

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.kind ~= "namespace" and id ~= ir.root then
      -- A module may legitimately be reached only through the aggregator's
      -- string map rather than a literal require, so this stays at `info`.
      if not required[node.module] then
        add(findings, "info", "unreferenced-module", id,
          ("%s is required by no other file in the tree"):format(node.module))
      end
    end
  end
end

---Run every check and return findings sorted by severity.
---@param ir Lib.Docmap.IR
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.Finding[]
function M.run(ir, opts)
  local findings = {}

  check_summaries(ir, findings)
  check_module_paths(ir, findings, opts)
  check_readmes(ir, findings)
  check_readme_links(ir, findings, opts)
  check_orphans(ir, findings, opts)

  for _, extra in ipairs(opts.extra_checks or {}) do
    for _, f in ipairs(extra(ir, opts) or {}) do
      findings[#findings + 1] = f
    end
  end

  local rank = { error = 1, warn = 2, info = 3 }
  table.sort(findings, function(a, b)
    if rank[a.severity] ~= rank[b.severity] then
      return rank[a.severity] < rank[b.severity]
    end
    if a.check ~= b.check then
      return a.check < b.check
    end
    return (a.node or "") < (b.node or "")
  end)

  return findings
end

---Group findings by severity for reporting.
---@param findings Lib.Docmap.Finding[]
---@return table<Lib.Docmap.Severity, integer>
function M.tally(findings)
  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end
  return t
end

return M
