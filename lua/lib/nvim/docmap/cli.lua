---@module 'lib.nvim.docmap.cli'
--- The `nvim --headless -l ... [--check|--full]` entry point, as a function
--- rather than a script. Extracted out of `scripts/gen_map.lua` so a
--- consuming plugin's own generator script — and its own pre-commit hook —
--- can be the same three lines calling into this, instead of a second copy of
--- the staleness check and the reporting format drifting from this repo's.
---
--- `scripts/gen_map.lua` is the thin, repo-specific wrapper:
---
---   local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
---   vim.opt.runtimepath:prepend(root)
---   local opts = require("lib.nvim.docmap.config")(root)
---   vim.cmd("cq " .. require("lib.nvim.docmap.cli").run(opts, _G.arg or {}))
---
--- Returns an exit code rather than calling `vim.cmd("cq ...")` itself, so it
--- stays a plain function a test can call and assert on, and so the one
--- caller that actually needs the process to exit is the wrapper script, not
--- this module.

local M = {}

---@param path string
---@return string?
local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local s = fd:read("*a")
  fd:close()
  return s
end

---@param findings Lib.Docmap.Finding[]
---@return table<Lib.Docmap.Severity, integer>
local function report(findings)
  local docmap = require("lib.nvim.docmap")
  local tally = docmap.tally(findings)
  for _, f in ipairs(findings) do
    if f.severity ~= "info" then
      io.stderr:write(("  [%s] %-22s %s\n"):format(f.severity, f.check, f.message))
    end
  end
  io.stdout:write(
    ("\n%d errors, %d warnings, %d info\n"):format(tally.error, tally.warn, tally.info)
  )
  return tally
end

---Run the CLI over `opts` with `argv` (`_G.arg`-shaped: `--check`, `--lenient`,
---`--full`). Writes to stdout/stderr as a side effect; returns the process
---exit code rather than calling `os.exit`/`vim.cmd("cq ...")`, so the caller
---decides how to actually exit.
---@param opts Lib.Docmap.Opts
---@param argv string[]
---@return integer exit_code
function M.run(opts, argv)
  local docmap = require("lib.nvim.docmap")
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  local check_only, strict = false, true
  for _, a in ipairs(argv) do
    if a == "--check" then
      check_only = true
    elseif a == "--lenient" then
      strict = false
    elseif a == "--full" then
      opts.luals = true
    end
  end

  if check_only then
    local ir, findings = docmap.scan_full(opts)

    local expected = {
      ["module_map.json"] = docmap.to_json(ir),
      ["index.html"] = docmap.render.html(ir, findings, opts),
      ["overview.md"] = docmap.render.markdown(ir, findings, opts),
    }
    if opts.badge then
      expected["coverage.svg"] = require("lib.nvim.docmap.doccoverage").badge_svg(ir)
    end

    local stale = {}
    for name, content in pairs(expected) do
      local path = root .. "/" .. opts.out_dir .. "/" .. name
      if read(path) ~= content then
        stale[#stale + 1] = opts.out_dir .. "/" .. name
      end
    end
    table.sort(stale)

    if #stale > 0 then
      io.stderr:write("Module map is stale:\n")
      for _, s in ipairs(stale) do
        io.stderr:write("  " .. s .. "\n")
      end
      io.stderr:write(
        "\nRun :LibMap (or nvim --headless -l scripts/gen_map.lua) and commit the result.\n\n"
      )
      report(findings)
      return 1
    end

    local tally = report(findings)

    if tally.error > 0 then
      if strict then
        io.stderr:write("\nModule map has " .. tally.error .. " error-severity drift findings.\n")
        return 1
      end
      io.stdout:write(tally.error .. " error-severity findings (--lenient: not failing).\n")
    end

    io.stdout:write("Module map is up to date.\n")
    return 0
  end

  local ir, findings, written = docmap.generate(opts)
  for _, w in ipairs(written) do
    io.stdout:write("wrote " .. w .. "\n")
  end
  io.stdout:write(
    ("%d modules, %d namespaces, %d files\n"):format(
      ir.meta.counts.module,
      ir.meta.counts.namespace,
      ir.meta.counts.file
    )
  )
  local tested, tested_total = require("lib.nvim.docmap.coverage").summary(ir)
  if tested_total > 0 then
    io.stdout:write(
      ("%d/%d functions found by name in %s (%.0f%%)\n"):format(
        tested,
        tested_total,
        opts.tests_dir or "docs/TESTS",
        100 * tested / tested_total
      )
    )
  end
  local documented, doc_total = require("lib.nvim.docmap.doccoverage").summary(ir)
  if doc_total > 0 then
    io.stdout:write(
      ("%d/%d published functions fully documented (%.0f%%)\n"):format(
        documented,
        doc_total,
        100 * documented / doc_total
      )
    )
  end
  local tally = report(findings)
  return (strict and tally.error > 0) and 1 or 0
end

return M
