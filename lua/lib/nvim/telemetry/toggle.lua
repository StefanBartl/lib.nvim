---@module 'lib.nvim.telemetry.toggle'
--- Persistent per-namespace enable/disable, independent of any instance's own
--- collected data.
---
--- WHY THIS IS SEPARATE FROM start()/stop()
--- `inst.stop()` only affects the current process; the next `require(...).new()`
--- + `t.start()` in tomorrow's session installs the wrapper again exactly as
--- before. That is correct for "pause it for a minute" but wrong for "I looked
--- at markdown.nvim's numbers, I'm done, stop wrapping it" — the caller that
--- calls `t.start()` (a config, wired once at startup) has no idea a user
--- decided that mid-session, and re-editing that caller's source every time is
--- exactly the friction a `:LibTelemetry disable <ns>` command should remove.
---
--- So the "disabled" flag lives on disk (same `cache.disk` backend the counts
--- themselves use, but its own file — a namespace's toggle state is not part
--- of that namespace's data, and clearing counts with `:LibTelemetry reset`
--- must not also silently re-enable it). `inst.start()` checks it and is a
--- no-op while disabled; the CALLER's `t.start()` call does not need to
--- change at all, which is the point — the toggle takes effect without
--- touching whoever wired the instance up in the first place.
---
--- This is deliberately GLOBAL, not per-namespace-dir: unlike an instance's
--- own counts (which follow that instance's `opts.dir`), "should this even
--- run" is a cross-session user decision that has to be readable before any
--- particular instance's options are known — a namespace can be disabled
--- before it has ever loaded. The optional `opts.dir` on every function below
--- exists only so tests do not read/write the real `stdpath("cache")`; real
--- callers never pass it.

local disk = require("lib.nvim.cache.disk")

local M = {}

local CACHE_KEY = "telemetry/_control"

---@type table<string, boolean>|nil
local disabled = nil

---@param opts? Lib.Cache.Opts
---@return table<string, boolean>
local function load(opts)
  -- An explicit `dir` (tests only) always bypasses the module-level cache —
  -- otherwise the first test to run would pin `disabled` to its own tmp dir's
  -- contents for every test after it in the same process.
  if opts and opts.dir then
    local ok, data = pcall(disk.load, CACHE_KEY, opts)
    return (ok and type(data) == "table" and type(data.disabled) == "table") and data.disabled or {}
  end

  if disabled then
    return disabled
  end
  local ok, data = pcall(disk.load, CACHE_KEY)
  if ok and type(data) == "table" and type(data.disabled) == "table" then
    disabled = data.disabled
  else
    disabled = {}
  end
  return disabled
end

---@param d table<string, boolean>
---@param opts? Lib.Cache.Opts
local function persist(d, opts)
  pcall(disk.save, CACHE_KEY, { disabled = d }, opts)
end

---@param namespace string
---@param opts? Lib.Cache.Opts
---@return boolean
function M.is_disabled(namespace, opts)
  return load(opts)[namespace] == true
end

---@param namespace string
---@param opts? Lib.Cache.Opts
function M.disable(namespace, opts)
  local d = load(opts)
  d[namespace] = true
  persist(d, opts)
end

---@param namespace string
---@param opts? Lib.Cache.Opts
function M.enable(namespace, opts)
  local d = load(opts)
  if d[namespace] then
    d[namespace] = nil
    persist(d, opts)
  end
end

---Every namespace currently marked disabled, sorted.
---@param opts? Lib.Cache.Opts
---@return string[]
function M.disabled_list(opts)
  local out = {}
  for ns in pairs(load(opts)) do
    out[#out + 1] = ns
  end
  table.sort(out)
  return out
end

return M
