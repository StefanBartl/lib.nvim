---@module 'lib.nvim.deps.detect'
--- Is a declared tool present on this host, under any of the names it goes by?
---
--- One tool does not always have one binary name. Ghostscript is `gs` on
--- Linux and macOS and `gswin64c` (or `gswin32c`) on Windows; the same
--- program, the same package, the same reason to want it. A spec that can
--- only name one of them reports the tool as missing on the platform where
--- it is spelled differently — and does it *next to* a capability check that
--- found it, so the same `:checkhealth` run says both.
---
--- `bin` stays canonical for everything except detection: it is the tool's
--- identity, its display label, the key its install state is stored under,
--- and what `pkg` maps from. `bin_alternatives` only widens the question
--- "is it here".
---
--- This is its own module rather than a function on `deps` or `deps.spec`
--- because three modules need it (`health`, `install`, `view`) and `deps`
--- requires all three -- putting it there would be a cycle. `spec` is the
--- other candidate and rules itself out: it documents that it touches
--- nothing but the one file handed to it, and this probes `PATH`.

local core = require("lib.nvim.core")

local M = {}

---Every binary name a tool may be found under, canonical name first.
---
---Order matters: the canonical `bin` is checked before any alternative, so a
---host that has both reports the name the spec calls it.
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return string[]
function M.names(tool)
  local names = {}
  if type(tool.bin) == "string" and tool.bin ~= "" then
    names[#names + 1] = tool.bin
  end
  for _, alt in ipairs(tool.bin_alternatives or {}) do
    if type(alt) == "string" and alt ~= "" then
      names[#names + 1] = alt
    end
  end
  return names
end

---The name `tool` was actually found under, or nil when none of them is on
---PATH.
---
---Returns the name rather than a boolean so a report can say *which* one
---answered: "gs found (as gswin64c)" is the line that stops the next person
---from looking for a `gs` that was never going to be there.
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return string|nil
function M.found_as(tool)
  return core.first_available(M.names(tool))
end

---Whether `tool` is present under any of its names.
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return boolean
function M.found(tool)
  return M.found_as(tool) ~= nil
end

---Drop the memoized PATH result for every name `tool` goes by.
---
---After an install, the canonical name is not necessarily the one that
---appeared: forgetting only `bin` would leave a freshly installed
---`gswin64c` reported as missing until the next session.
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return nil
function M.forget(tool)
  for _, name in ipairs(M.names(tool)) do
    core.forget_exec(name)
  end
end

---@type Lib.Deps.Detect
return M
