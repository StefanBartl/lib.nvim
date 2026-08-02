---@module 'lib.nvim.telemetry.report_style'
--- Resolve a `report_style` request ("auto" | "kit" | "mdview" | "file") to
--- a concrete destination `:LibTelemetry open` can act on.
---
--- Mirrors `lib.nvim.progress.resolve_style`: prefer the richer external
--- integration when it is actually loadable, degrade silently rather than
--- erroring the caller — an external plugin's presence is never
--- stability-guaranteed, and that includes an explicit request for it, not
--- only "auto" (the same choice `progress.resolve_style` makes for an
--- explicit `"fidget"` request).

require("lib.nvim.telemetry.@types")

local mdview = require("lib.nvim.telemetry.renderers.mdview")

---@param want Lib.Telemetry.ReportStyle|nil
---@return "kit"|"mdview"|"file"
local function resolve(want)
  if want == "kit" then
    return "kit"
  end
  if want == "file" then
    return "file"
  end

  -- "mdview" explicitly, or "auto" (default), or unrecognized: prefer
  -- mdview when it is actually loadable, else the kit float — which is
  -- always available and is what `:LibTelemetry` already renders today, so
  -- "nothing regresses when mdview is absent" holds without a special case.
  if mdview.available() then
    return "mdview"
  end
  return "kit"
end

return resolve
