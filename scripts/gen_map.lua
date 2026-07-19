---@module 'scripts.gen_map'
--- CLI entry point for the lib.nvim module map.
---
---   nvim --headless -l scripts/gen_map.lua           # regenerate artifacts
---   nvim --headless -l scripts/gen_map.lua --check    # verify, write nothing
---
---   nvim --headless -l scripts/gen_map.lua --check --strict
---
--- `--check` is what hooks and CI run: it regenerates in memory, compares
--- against what is committed, and exits non-zero if the artifacts are stale.
--- It deliberately does *not* rewrite files — a hook that regenerates and
--- stages output produces diffs the author never intended and interacts badly
--- with amend and rebase.
---
--- `--strict` additionally fails on error-severity drift findings. It is kept
--- separate because the tree already carries pre-existing drift (stale
--- `@module` headers, `Lib` fields whose handlers point at keys that no longer
--- exist); wiring the hook to fail on those from day one would mean the hook
--- is red before anyone has touched anything, and a check that is always red
--- gets disabled. Turn it on once the backlog is cleared.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

local docmap = require("lib.nvim.docmap")
local opts = require("lib.nvim.docmap.config")(root)

local check_only, strict = false, false
for _, a in ipairs(_G.arg or {}) do
  if a == "--check" then
    check_only = true
  elseif a == "--strict" then
    strict = true
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

  local tally = report(findings)

  if #stale > 0 then
    io.stderr:write("\nModule map is stale:\n")
    for _, s in ipairs(stale) do
      io.stderr:write("  " .. s .. "\n")
    end
    io.stderr:write("\nRun :LibMap (or nvim --headless -l scripts/gen_map.lua) and commit the result.\n")
    vim.cmd("cq 1")
  end

  if tally.error > 0 then
    if strict then
      io.stderr:write("\nModule map has " .. tally.error .. " error-severity findings (--strict).\n")
      vim.cmd("cq 1")
    end
    io.stdout:write(tally.error .. " error-severity findings (not failing; pass --strict to enforce).\n")
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
