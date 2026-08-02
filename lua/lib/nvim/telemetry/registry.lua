---@module 'lib.nvim.telemetry.registry'
--- Module-level bookkeeping for every installed wrapper, shared by all
--- telemetry instances.
---
--- WHY THIS IS SHARED RATHER THAN PER-INSTANCE
--- If two instances (say lib.nvim's and lsp.nvim's) both wrapped the same
--- function, the naive design nests wrappers: both count the call, and the
--- inner one restoring first leaves the outer holding a wrapper it will later
--- reinstall as "the original" — instrumentation stuck on with nothing to
--- notice it. So a function is wrapped at most ONCE, here, and instances
--- subscribe to it. Restore happens when the last subscriber detaches, and
--- double counting is structurally impossible rather than merely unlikely.
---
--- Everything in this file is on the hot path when telemetry is running. It
--- does exactly two things per call in the cheapest mode: index a table and
--- add one integer. No clock reads, no `vim.*`, nothing that would make a
--- wrapper unsafe in a fast event context.

local uv = vim.uv or vim.loop

local fingerprint = require("lib.nvim.telemetry.fingerprint")

local M = {}

local unpack_ = table.unpack or unpack

--- `{ original(...) }` loses everything after a nil, and a wrapped function
--- returning `1, nil, 3` must still return `1, nil, 3`. Capture the arity.
local pack = table.pack or function(...)
  return { n = select("#", ...), ... }
end

--- container table -> field name -> site
---@type table<table, table<string, table>>
local sites = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Flags
-- ---------------------------------------------------------------------------

---Recompute the per-site "does anyone want this?" flags. Called whenever the
---subscriber set or an instance's mode changes — never per call.
---@param site table
local function refresh(site)
  local args, time, errors, outermost = false, false, false, false
  local subs = site.subs
  for i = 1, #subs do
    local s = subs[i]
    args = args or s.args
    time = time or s.time
    errors = errors or s.errors
    outermost = outermost or s.outermost_only
  end
  site.needs_args = args
  site.needs_time = time
  site.needs_errors = errors
  site.needs_depth = outermost
end

---@param site table
---@param fp string|nil
---@param dur number|nil
---@param errored boolean
local function dispatch(site, fp, dur, errored)
  local subs = site.subs
  for i = 1, #subs do
    local s = subs[i]
    s.inst._record(s.key, s.args and fp or nil, s.time and dur or nil, errored)
  end
end

-- ---------------------------------------------------------------------------
-- The wrapper
-- ---------------------------------------------------------------------------

---@param site table
---@return function
local function make_wrapper(site)
  return function(...)
    local original = site.original

    -- Cheapest path, and the one that must stay cheap: counting only.
    -- Tail-called, so the wrapper adds no frame to the callee's stack and
    -- multiple return values pass through untouched.
    if not (site.needs_args or site.needs_time or site.needs_errors or site.needs_depth) then
      dispatch(site, nil, nil, false)
      return original(...)
    end

    local fp
    if site.needs_args then
      fp = fingerprint.of(select("#", ...), ...)
    end

    -- Depth tracking and error counting both need the call to return through
    -- us even when it raises, which means pcall — hence both are opt-in.
    if site.needs_depth or site.needs_errors then
      site.depth = site.depth + 1
      local outermost = site.depth == 1

      local t0 = site.needs_time and uv.hrtime() or nil
      local res = pack(pcall(original, ...))
      local dur = t0 and (uv.hrtime() - t0) / 1e6 or nil

      site.depth = site.depth - 1

      if outermost or not site.needs_depth then
        dispatch(site, fp, dur, not res[1])
      end

      if not res[1] then
        error(res[2], 0)
      end
      return unpack_(res, 2, res.n)
    end

    if site.needs_time then
      local t0 = uv.hrtime()
      local res = pack(original(...))
      dispatch(site, fp, (uv.hrtime() - t0) / 1e6, false)
      return unpack_(res, 1, res.n)
    end

    dispatch(site, fp, nil, false)
    return original(...)
  end
end

-- ---------------------------------------------------------------------------
-- Attach / detach
-- ---------------------------------------------------------------------------

---Subscribe `inst` to calls of `container[field]`, installing the wrapper if
---this is the first subscriber.
---@param container table
---@param field string
---@param key string            # the label reported for this instance
---@param inst table            # must expose `_record(key, fp, dur_ms, errored)`
---@param wants table           # { args, time, errors, outermost_only }
---@return boolean ok
function M.attach(container, field, key, inst, wants)
  local original = rawget(container, field)
  if type(original) ~= "function" then
    return false
  end

  local by_field = sites[container]
  if not by_field then
    by_field = {}
    sites[container] = by_field
  end

  local site = by_field[field]
  if not site then
    site = { container = container, field = field, original = original, subs = {}, depth = 0 }
    site.wrapper = make_wrapper(site)
    by_field[field] = site
    container[field] = site.wrapper
  elseif container[field] ~= site.wrapper then
    -- Someone replaced the field after we wrapped it (hot reload, a plugin
    -- monkey-patching the same function). Their value is the one callers
    -- should reach, so adopt it as the new original instead of silently
    -- shadowing it — and re-install so we still see the calls.
    site.original = container[field]
    container[field] = site.wrapper
  end

  for i = 1, #site.subs do
    if site.subs[i].inst == inst then
      local s = site.subs[i]
      s.key, s.args, s.time = key, wants.args, wants.time
      s.errors, s.outermost_only = wants.errors, wants.outermost_only
      refresh(site)
      return true
    end
  end

  site.subs[#site.subs + 1] = {
    inst = inst,
    key = key,
    args = wants.args or false,
    time = wants.time or false,
    errors = wants.errors or false,
    outermost_only = wants.outermost_only or false,
  }
  refresh(site)
  return true
end

---Unsubscribe `inst`; restores the original once nobody is left.
---@param container table
---@param field string
---@param inst table
function M.detach(container, field, inst)
  local by_field = sites[container]
  local site = by_field and by_field[field]
  if not site then
    return
  end

  for i = #site.subs, 1, -1 do
    if site.subs[i].inst == inst then
      table.remove(site.subs, i)
    end
  end

  if #site.subs > 0 then
    refresh(site)
    return
  end

  -- Last one out restores. Only if the field is still *our* wrapper — if
  -- something replaced it since, overwriting would undo their change.
  if container[field] == site.wrapper then
    container[field] = site.original
  end
  by_field[field] = nil
  if next(by_field) == nil then
    sites[container] = nil
  end
end

---True while `container[field]` is an installed wrapper.
---@param container table
---@param field string
---@return boolean
function M.is_wrapped(container, field)
  local by_field = sites[container]
  local site = by_field and by_field[field]
  return site ~= nil and container[field] == site.wrapper
end

return M
