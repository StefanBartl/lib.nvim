---@module 'lib.nvim.deps.health'
--- Generic replacement for the `check_exe`/`probe` pattern hand-rolled in
--- every consuming plugin's own `health.lua` today (`pdfport.nvim`,
--- `images.nvim`, `mdview.nvim`, `migrate.nvim`, …): report executable or
--- Python-module availability via `:checkhealth`, with an optional human
--- install hint. Detection only — nothing here installs anything.

local core = require("lib.nvim.core")

local M = {}

local health = vim.health or require("health")
local h_ok = health.ok or health.report_ok
local h_warn = health.warn or health.report_warn
local h_err = health.error or health.report_error

---@internal
---@param entry Lib.Deps.HealthEntry
local function report_one(entry)
  local label = entry.label or entry.bin or entry.python_module or "?"

  local found
  if entry.bin then
    found = core.has_exec(entry.bin)
  elseif entry.python_module then
    local python = core.first_available({ "python3", "python", "py" })
    if not python then
      found = false
    else
      vim.fn.system({ python, "-c", "import " .. entry.python_module })
      found = vim.v.shell_error == 0
    end
  else
    h_err(label .. ": entry has neither 'bin' nor 'python_module'")
    return
  end

  if found then
    h_ok(label .. " found")
    return
  end

  local suffix = entry.hint and ("  (" .. entry.hint .. ")") or ""
  if entry.required then
    h_err(label .. " NOT found (required)" .. suffix)
  else
    h_warn(label .. " NOT found (optional)" .. suffix)
  end
end

---Report availability for a flat list of health entries. Call from a
---plugin's own `health.lua` `M.check()`, replacing a hand-rolled
---`check_exe`/`probe` loop.
---@param entries Lib.Deps.HealthEntry[]
function M.report(entries)
  for _, entry in ipairs(entries) do
    report_one(entry)
  end
end

---Report availability directly from a parsed spec's `tools` list (see
---`lib.nvim.deps.spec.load`/`parse_markdown`/`parse_json`), reusing each
---tool's declared `why` as the health-report hint.
---@param tools Lib.Deps.Tool[]
function M.from_tools(tools)
  local entries = {} ---@type Lib.Deps.HealthEntry[]
  for _, tool in ipairs(tools) do
    entries[#entries + 1] = {
      bin = tool.bin,
      required = tool.required,
      label = tool.bin,
      hint = tool.why,
    }
  end
  M.report(entries)
end

---@type Lib.Deps.Health
return M
