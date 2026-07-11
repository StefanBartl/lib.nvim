---@module 'lib.nvim.logger'
--- Structured logging, diagnostics and crash dumps for lib.nvim plugins.
---
--- A logger is a richer sibling of `lib.nvim.notify`: next to a normal notify
--- it records a message plus structured context into a bounded in-memory ring,
--- optionally streams JSONL to a file, and can dump that ring when a guarded
--- entrypoint fails. Level/enabled/tag switches make it possible to turn all
--- logging — or just parts of it — off, with de-facto zero runtime cost.
---
---   local log = require("lib.nvim.logger").new({ name = "myplugin" })
---   log.info("cache warm", { entries = 128 })
---   log.error("write failed", { path = p, err = err })
---
--- Global kill switch (no impact once off):
---   require("lib.nvim.logger").set_enabled(false)

require("lib.nvim.logger.@types")

local resolve_log_level = require("lib.nvim.notify.resolve_log_level")
local config = require("lib.nvim.logger.config")
local Ring = require("lib.nvim.logger.ring")
local Record = require("lib.nvim.logger.record")
local sinks = require("lib.nvim.logger.sinks")

local unpack = table.unpack or unpack

local M = {}

-- ---------------------------------------------------------------------------
-- Global state (shared across every logger via the cached module table)
-- ---------------------------------------------------------------------------

local G = {
  enabled = true, -- master switch; checked first in the hot path
  min_level = nil, -- global min-level override (nil = per-logger)
  disabled_tags = {}, -- set: records carrying any of these are dropped
  only_tags = nil, -- set|nil: when set, only records with a listed tag pass
  registry = {}, -- all live loggers (for inspector / checkhealth)
  defaults = vim.deepcopy(config.defaults),
  command_installed = false,
}

-- ---------------------------------------------------------------------------
-- Gating — the hot path. Must stay cheap so a disabled logger is ~free.
-- ---------------------------------------------------------------------------

---@param inst table
---@param level integer
---@param opts Lib.Logger.CallOpts|nil
---@return boolean
local function passes(inst, level, opts)
  if not G.enabled then
    return false
  end
  if not inst.enabled then
    return false
  end
  if level < (G.min_level or inst.level) then
    return false
  end

  local tags = opts and opts.tags

  if G.only_tags then
    if not tags then
      return false
    end
    local hit = false
    for i = 1, #tags do
      if G.only_tags[tags[i]] then
        hit = true
        break
      end
    end
    if not hit then
      return false
    end
  end

  if tags and next(G.disabled_tags) ~= nil then
    for i = 1, #tags do
      if G.disabled_tags[tags[i]] then
        return false
      end
    end
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Logger factory
-- ---------------------------------------------------------------------------

---Resolve the file path for a logger. `false` disables the file sink; `nil`
---uses the per-name default under stdpath("log").
---@param name string
---@param file string|false|nil
---@return string|nil
local function resolve_file(name, file)
  if file == false then
    return nil
  end
  if type(file) == "string" and file ~= "" then
    return file
  end
  return sinks.default_path(name)
end

---Create a new logger.
---@param opts? Lib.Logger.Options
---@return Lib.Logger.Instance
function M.new(opts)
  opts = vim.tbl_extend("force", G.defaults, opts or {})

  local name = type(opts.name) == "string" and opts.name or "lib"

  local inst = {
    name = name,
    enabled = true,
    level = resolve_log_level(opts.level, vim.log.levels.DEBUG),
    notify_level = resolve_log_level(opts.notify_level, vim.log.levels.WARN),
    file = resolve_file(name, opts.file),
    src = opts.src == true,
    redact = opts.redact,
    ring = Ring.new(opts.history),
    _notify_sink = sinks.notifier(name),
    _once = {},
  }

  -- Core dispatch. `src_level = 4`: getinfo(4) from here lands on the user's
  -- call site (do_log -> level closure -> user).
  local function do_log(level, msg, ctx, call_opts)
    if not passes(inst, level, call_opts) then
      return
    end

    local record = Record.build(name, level, msg, ctx, call_opts, inst.src, inst.redact, 4)
    inst.ring:push(record)

    -- notify sink
    local want_notify
    if call_opts and call_opts.notify ~= nil then
      want_notify = call_opts.notify
    else
      want_notify = level >= inst.notify_level
    end
    if want_notify then
      pcall(inst._notify_sink, record)
    end

    -- file sink (synchronous append == durable immediately, incl. on error)
    local target = (call_opts and call_opts.to) or inst.file
    if target then
      pcall(sinks.write_record, target, record)
    end
  end

  inst.log = function(level, msg, ctx, call_opts)
    do_log(resolve_log_level(level, vim.log.levels.INFO), msg, ctx, call_opts)
  end
  inst.trace = function(msg, ctx, call_opts)
    do_log(vim.log.levels.TRACE, msg, ctx, call_opts)
  end
  inst.debug = function(msg, ctx, call_opts)
    do_log(vim.log.levels.DEBUG, msg, ctx, call_opts)
  end
  inst.info = function(msg, ctx, call_opts)
    do_log(vim.log.levels.INFO, msg, ctx, call_opts)
  end
  inst.warn = function(msg, ctx, call_opts)
    do_log(vim.log.levels.WARN, msg, ctx, call_opts)
  end
  inst.error = function(msg, ctx, call_opts)
    do_log(vim.log.levels.ERROR, msg, ctx, call_opts)
  end

  inst.set_enabled = function(on)
    inst.enabled = on ~= false
  end
  inst.is_enabled = function()
    return inst.enabled
  end
  inst.set_level = function(level)
    inst.level = resolve_log_level(level, inst.level)
  end

  ---Write the whole in-memory ring to the file sink now. Used by crash capture,
  ---VimLeavePre and `:LibLogger dump`.
  inst.flush = function()
    if not inst.file then
      return false
    end
    local ok = sinks.write_records(inst.file, inst.ring:snapshot())
    return ok == true
  end

  inst.snapshot = function()
    return inst.ring:snapshot()
  end
  inst.clear = function()
    inst.ring:clear()
  end

  ---Log `msg` at `level` at most once per `key` for this logger.
  inst.once = function(key, level, msg, ctx)
    if inst._once[key] then
      return false
    end
    inst._once[key] = true
    do_log(resolve_log_level(level, vim.log.levels.INFO), msg, ctx, nil)
    return true
  end

  ---Start a timer; the returned function logs the elapsed milliseconds.
  inst.timer = function(label, level)
    local lvl = resolve_log_level(level, vim.log.levels.DEBUG)
    local t0 = vim.uv and vim.uv.hrtime() or 0
    return function(ctx)
      local t1 = vim.uv and vim.uv.hrtime() or 0
      local ms = (t1 - t0) / 1e6
      local merged = ctx or {}
      merged.ms = tonumber(string.format("%.3f", ms))
      do_log(lvl, label, merged, nil)
    end
  end

  -- xpcall wrapper. rethrow=true -> re-raise after logging (guard);
  -- rethrow=false -> swallow and return nil (wrap).
  local function make_guard(fn, fname, rethrow)
    fname = fname or "<anonymous>"
    return function(...)
      local rets = {
        xpcall(fn, function(e)
          return debug.traceback(tostring(e), 2)
        end, ...),
      }
      if rets[1] then
        return unpack(rets, 2, #rets)
      end
      local tb = rets[2]
      inst.error("guard caught error in " .. fname, { traceback = tb })
      inst.flush()
      if rethrow then
        error(tb, 0)
      end
      return nil
    end
  end

  inst.guard = function(fn, fname)
    return make_guard(fn, fname, true)
  end
  inst.wrap = function(fn, fname)
    return make_guard(fn, fname, false)
  end

  inst.assert = function(cond, msg, ctx)
    if not cond then
      inst.error("assertion failed: " .. tostring(msg), ctx)
      inst.flush()
      error("lib.nvim.logger assertion failed: " .. tostring(msg), 2)
    end
    return cond
  end

  -- Crash-capture safety net: flush the ring on editor exit.
  if opts.capture ~= false and inst.file then
    local group = vim.api.nvim_create_augroup("lib_logger_" .. name, { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        pcall(inst.flush)
      end,
      desc = "lib.nvim.logger: flush ring buffer on exit",
    })
  end

  G.registry[#G.registry + 1] = inst

  -- Installing the control command the first time any logger is created.
  if not G.command_installed then
    G.command_installed = true
    pcall(function()
      require("lib.nvim.logger.command").install(M)
    end)
  end

  ---@type Lib.Logger.Instance
  return inst
end

-- ---------------------------------------------------------------------------
-- Global switches
-- ---------------------------------------------------------------------------

---Merge global defaults / apply global switches.
---@param opts? table  # any Lib.Logger.Options keys become new defaults; plus `enabled`, `min_level`
function M.setup(opts)
  opts = opts or {}
  if opts.enabled ~= nil then
    G.enabled = opts.enabled ~= false
    opts.enabled = nil
  end
  if opts.min_level ~= nil then
    G.min_level = resolve_log_level(opts.min_level, nil)
    opts.min_level = nil
  end
  G.defaults = vim.tbl_extend("force", G.defaults, opts)
end

---GLOBAL master switch. When off, every log call returns after one comparison.
---@param on boolean
function M.set_enabled(on)
  G.enabled = on ~= false
end
function M.is_enabled()
  return G.enabled
end

---Global minimum-level override across all loggers. `nil` clears it.
---@param level? Lib.Logger.LevelInput
function M.set_level(level)
  if level == nil then
    G.min_level = nil
  else
    G.min_level = resolve_log_level(level, vim.log.levels.WARN)
  end
end

---@param tag string
function M.disable_tag(tag)
  G.disabled_tags[tag] = true
end
---@param tag string
function M.enable_tag(tag)
  G.disabled_tags[tag] = nil
end

---Whitelist mode: only records carrying a listed tag pass. `nil` clears it.
---@param tags? string[]
function M.only_tags(tags)
  if tags == nil or #tags == 0 then
    G.only_tags = nil
    return
  end
  local set = {}
  for _, t in ipairs(tags) do
    set[t] = true
  end
  G.only_tags = set
end

---@return { disabled: string[], only: string[]|nil }
function M.tags()
  local disabled = {}
  for t in pairs(G.disabled_tags) do
    disabled[#disabled + 1] = t
  end
  local only
  if G.only_tags then
    only = {}
    for t in pairs(G.only_tags) do
      only[#only + 1] = t
    end
  end
  return { disabled = disabled, only = only }
end

---@return Lib.Logger.Instance[]
function M.loggers()
  return G.registry
end

---@type Lib.Logger
return M
