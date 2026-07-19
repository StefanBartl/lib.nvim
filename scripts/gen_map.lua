---@module 'scripts.gen_map'
--- CLI entry point for the lib.nvim module map.
---
---   nvim --headless -l scripts/gen_map.lua           # regenerate artifacts
---   nvim --headless -l scripts/gen_map.lua --check    # verify, write nothing
---
---   nvim --headless -l scripts/gen_map.lua --check --lenient
---
--- `--check` is what hooks and CI run: it regenerates in memory, compares
--- against what is committed, and exits non-zero if the artifacts are stale or
--- if any error-severity drift finding exists. It deliberately does *not*
--- rewrite files — a hook that regenerates and stages output produces diffs
--- the author never intended and interacts badly with amend and rebase.
---
--- Enforcing drift was originally opt-in, because the tree carried a backlog
--- of it and a check that is red before anyone touches anything gets disabled.
--- That backlog is now cleared (0 errors), so enforcement is the default and
--- `--lenient` is the escape hatch — report findings, fail only on staleness.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

local docmap = require("lib.nvim.docmap")
local opts = require("lib.nvim.docmap.config")(root)

local check_only, strict = false, true
for _, a in ipairs(_G.arg or {}) do
  if a == "--check" then
    check_only = true
  elseif a == "--lenient" then
    strict = false
  end
end

local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local s = fd:read("*a")
  fd:close()
  return s
end

local function report(findings)
  local tally = docmap.tally(findings)
  for _, f in ipairs(findings) do
    if f.severity ~= "info" then
      io.stderr:write(("  [%s] %-22s %s\n"):format(f.severity, f.check, f.message))
    end
  end
  io.stdout:write(("\n%d errors, %d warnings, %d info\n"):format(tally.error, tally.warn, tally.info))
  return tally
end

if check_only then
  local ir = docmap.scan(opts)
  local findings = docmap.check(ir, opts)

  local expected = {
    ["module_map.json"] = docmap.to_json(ir),
    ["index.html"] = docmap.render.html(ir, findings, opts),
    ["overview.md"] = docmap.render.markdown(ir, findings, opts),
  }

  local stale = {}
  for name, content in pairs(expected) do
    local path = root .. "/" .. opts.out_dir .. "/" .. name
    if read(path) ~= content then
      stale[#stale + 1] = opts.out_dir .. "/" .. name
    end
  end
  table.sort(stale)

  -- Verdict before detail: when this runs from a hook, the first lines are what
  -- the author actually reads, and "which files are stale" beats a wall of
  -- informational findings scrolling past.
  if #stale > 0 then
    io.stderr:write("Module map is stale:\n")
    for _, s in ipairs(stale) do
      io.stderr:write("  " .. s .. "\n")
    end
    io.stderr:write("\nRun :LibMap (or nvim --headless -l scripts/gen_map.lua) and commit the result.\n\n")
    report(findings)
    vim.cmd("cq 1")
  end

  local tally = report(findings)

  if tally.error > 0 then
    if strict then
      io.stderr:write("\nModule map has " .. tally.error .. " error-severity drift findings.\n")
      vim.cmd("cq 1")
    end
    io.stdout:write(tally.error .. " error-severity findings (--lenient: not failing).\n")
  end

  io.stdout:write("Module map is up to date.\n")
  vim.cmd("cq 0")
end

local ir, findings, written = docmap.generate(opts)
for _, w in ipairs(written) do
  io.stdout:write("wrote " .. w .. "\n")
end
io.stdout:write(("%d modules, %d namespaces, %d files\n")
  :format(ir.meta.counts.module, ir.meta.counts.namespace, ir.meta.counts.file))
local tally = report(findings)
vim.cmd((strict and tally.error > 0) and "cq 1" or "cq 0")
