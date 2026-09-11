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
--- A THIRD way a tool goes unfound on PATH: several GUI installers (Chrome,
--- LibreOffice, …) never extend PATH at all on Windows, which is the normal
--- case there rather than the exception (measured, `docs/install.json` in
--- hover.nvim). `paths` widens the search past PATH itself: a platform-keyed
--- list of literal install locations (`$ENVVAR`-expandable), tried only after
--- every name in `names()` has already missed. Before this existed, a plugin
--- with the same problem had to hand-roll its own resolver and keep it in
--- sync with the spec's `why` text by hand — see hover.nvim's `preview/shot
--- .lua`, whose `install_paths()` is the reason this exists at all.
---
--- This is its own module rather than a function on `deps` or `deps.spec`
--- because three modules need it (`health`, `install`, `view`) and `deps`
--- requires all three -- putting it there would be a cycle. `spec` is the
--- other candidate and rules itself out: it documents that it touches
--- nothing but the one file handed to it, and this probes `PATH`.

local core = require("lib.nvim.core")

local M = {}

---@internal
--- This host's key into a tool's `paths` map.
---@return "win"|"mac"|"linux"
local function platform_key()
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    return "win"
  end
  if vim.fn.has("mac") == 1 then
    return "mac"
  end
  return "linux"
end

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

---This host's declared fallback install locations for `tool` (`tool.paths`
---for `platform_key()`'s platform), each `vim.fn.expand()`-ed so `$ENVVAR`
---tokens (`$PROGRAMFILES`, `$LOCALAPPDATA`, …) resolve before the
---filesystem check. Empty when the tool declares none, or none for this
---platform.
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return string[]
function M.candidate_paths(tool)
  local by_platform = tool.paths
  if type(by_platform) ~= "table" then
    return {}
  end
  local list = by_platform[platform_key()]
  if not vim.islist(list) then
    return {}
  end
  local out = {}
  for _, path in ipairs(list) do
    out[#out + 1] = vim.fn.expand(path)
  end
  return out
end

---The name `tool` was actually found under, or nil when it is on neither
---PATH nor any of its declared fallback `paths`.
---
---Returns the name (or, for a `paths` hit, the full resolved path) rather
---than a boolean so a report can say *which* one answered: "gs found (as
---gswin64c)" is the line that stops the next person from looking for a `gs`
---that was never going to be there — and a `paths` hit says exactly where
---the tool was found instead of just "yes".
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return string|nil
function M.found_as(tool)
  local found = core.first_available(M.names(tool))
  if found then
    return found
  end
  for _, path in ipairs(M.candidate_paths(tool)) do
    if core.has_exec(path) then
      return path
    end
  end
  return nil
end

---Whether `tool` is present under any of its names or declared `paths`.
---@param tool Lib.Deps.Tool|Lib.Deps.HealthEntry
---@return boolean
function M.found(tool)
  return M.found_as(tool) ~= nil
end

---Drop the memoized PATH result for every name `tool` goes by, and for every
---resolved candidate path.
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
  for _, path in ipairs(M.candidate_paths(tool)) do
    core.forget_exec(path)
  end
end

---@type Lib.Deps.Detect
return M
