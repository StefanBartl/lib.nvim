---@module 'lib.nvim.telemetry.config'
--- Module-level defaults, separate from a per-instance `telemetry.new(opts)`.
---
--- `report_style` has no natural per-instance owner: `:LibTelemetry open`
--- with no namespace spans every live instance at once, so there has to be
--- one resolved answer to "how should `open` render", not one per instance.
--- Everything else about telemetry stays instance-scoped on purpose (see
--- `init.lua`'s own doc-comment); this is the one deliberate exception.

local M = {}

require("lib.nvim.telemetry.@types")

---@type { report_style: Lib.Telemetry.ReportStyle }
local G = {
  report_style = "auto",
}

---@param opts? { report_style?: Lib.Telemetry.ReportStyle }
function M.setup(opts)
  opts = opts or {}
  if opts.report_style ~= nil then
    G.report_style = opts.report_style
  end
end

---@return Lib.Telemetry.ReportStyle
function M.report_style()
  return G.report_style
end

return M
