---@module 'lib.nvim.telemetry'
--- Opt-in call counting and usage statistics for lib.nvim — and for any other
--- plugin that points an instance at its own modules.
---
--- Answers "how often was `lib.strings.trim` called in the last 7 days, and
--- with what?" without leaving a permanent cost behind when the answer is not
--- wanted. Counts survive restarts (`lib.nvim.cache.disk`, namespaced), so the
--- data is readable a week later, which is the whole point.
---
---   local telemetry = require("lib.nvim.telemetry")
---   local t = telemetry.new({ namespace = "lib.nvim" })
---
---   t.wrap_lib()            -- or t.wrap(require("my.module"), "module")
---   t.start()               -- counting only: the leave-it-on-for-a-week mode
---   -- ... days later ...
---   vim.print(t.report({ since = "7d", top = 20 }))
---
---   telemetry.disable("lib.nvim")   -- persists across restarts, stops it now;
---   telemetry.enable("lib.nvim")    -- the caller of t.start() above never changes
---
--- OFF COSTS NOTHING, LITERALLY
--- Instrumentation is *installed*, not compiled in: until `start()` runs, the
--- shipped functions are the original functions — the same objects, not a
--- nearly-free branch — and `stop()` puts them back. That is why there is no
--- `if enabled then count() end` in ~250 files, and why `debug.sethook` (which
--- fires on every Lua call in the process) was not an option. The same pattern
--- `lib.nvim.system.proc_trace` already uses for `vim.fn.system`.
---
--- HONEST LIMITS (read before trusting a number)
--- - Only calls that go THROUGH the wrapped table are seen. A consumer that
---   did `local trim = lib.strings.trim` before `start()` holds the raw
---   function and is invisible. Start as early as possible.
--- - `t.wrap_lib()` instruments the `require("lib")` aggregate. A direct
---   `require("lib.nvim.fs.mkdirp")` bypasses it entirely — wrap the module
---   itself if you need those calls counted.
--- - Counts are per-process, but flushes merge with what is already on disk,
---   so two Neovim instances sharing a namespace add up instead of clobbering.
--- - Wrapping changes identity: after `start()`, a reference saved earlier is
---   no longer `==` the table's current value. `stop()` restores exactly.
--- - Recursive functions count every entry by default. Pass
---   `{ outermost_only = true }` to count only the outermost one (costs a
---   `pcall` per call).
--- - Day bucketing reads the clock once per flush, not per call, so calls in
---   the last flush interval before midnight land in the previous day.
---
--- NOT IMPLEMENTED (phase 6 of docs/ROADMAP/usage-telemetry.md)
--- `wrap_tree(prefix)` — hooking `require` to catch lazily-loaded submodules.
--- Strictly more powerful and strictly more ways to surprise; use explicit
--- `wrap()` calls per module.

require("lib.nvim.telemetry.@types")

local uv = vim.uv or vim.loop

local autocmd = require("lib.nvim.autocmd")
local notify = require("lib.nvim.notify").create("[lib.nvim.telemetry]")
local registry = require("lib.nvim.telemetry.registry")
local reminder = require("lib.nvim.telemetry.reminder")
local report_mod = require("lib.nvim.telemetry.report")
local store = require("lib.nvim.telemetry.store")
local toggle = require("lib.nvim.telemetry.toggle")

local M = {}

---@type Lib.Telemetry.Instance[]
local instances = {}

local DEFAULTS = {
  retention_days = 30,
  flush_interval_ms = 60000,
  max_arg_values = 32,
  persist = true,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@param prefix string|nil
---@param name string
---@return string
local function join_key(prefix, name)
  if prefix == nil or prefix == "" then
    return name
  end
  return prefix .. "." .. name
end

---Decide whether a field is in scope. `only`/`except` are exact names by
---design — `filter` is the one escape hatch, rather than two overlapping ones
---(exact names plus patterns) that each need their own edge cases explained.
---@param name string
---@param fn function
---@param opts Lib.Telemetry.WrapOpts
---@return boolean
local function in_scope(name, fn, opts)
  if opts.only then
    local hit = false
    for _, n in ipairs(opts.only) do
      if n == name then
        hit = true
        break
      end
    end
    if not hit then
      return false
    end
  end

  if opts.except then
    for _, n in ipairs(opts.except) do
      if n == name then
        return false
      end
    end
  end

  if opts.filter and not opts.filter(name, fn) then
    return false
  end

  return true
end

---`true` (everything) / a name list / nil.
---@param spec string[]|true|nil
---@param key string
---@return boolean
local function selected(spec, key)
  if spec == nil then
    return false
  end
  if spec == true then
    return true
  end
  for _, n in ipairs(spec) do
    if n == key then
      return true
    end
  end
  return false
end

---@return Lib.Telemetry.Data
local function empty_delta()
  return { version = store.VERSION, sessions = 0, functions = {}, days = {}, reminded = {} }
end

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

---Create a telemetry instance for one namespace.
---
---Instance-based rather than a singleton for the same reason as `logger.new()`:
---this has to be usable by any plugin against its own surface, with its own
---persisted counts, without coordinating with lib.nvim.
---@param opts Lib.Telemetry.Options
---@return Lib.Telemetry.Instance
function M.new(opts)
  opts = opts or {}
  local namespace = type(opts.namespace) == "string" and opts.namespace or "unnamed"

  -- Two plugins picking the same namespace silently share a cache file and
  -- produce merged, wrong numbers. Cheap to warn about; invisible otherwise.
  for _, other in ipairs(instances) do
    if other.namespace == namespace then
      notify.warn(
        ("namespace %q already has a live instance; both will write the same cache file"):format(
          namespace
        )
      )
      break
    end
  end

  local cfg = vim.tbl_extend("force", DEFAULTS, {
    retention_days = opts.retention_days,
    flush_interval_ms = opts.flush_interval_ms,
    max_arg_values = opts.max_arg_values,
    persist = opts.persist,
    dir = opts.dir,
  })
  local cache_opts = cfg.dir and { dir = cfg.dir } or nil
  local remind_after = opts.remind_after
  if remind_after == nil then
    remind_after = reminder.DEFAULTS
  end

  local inst = { namespace = namespace, _cache_opts = cache_opts }

  --- Targets registered via wrap()/wrap_fn(), whether or not currently attached.
  ---@type table[]
  local targets = {}
  local running = false
  local attached = false
  --- Keys rawset onto the `require("lib")` aggregate by wrap_lib(), so unwrap
  --- can take them back off instead of leaving a materialized copy behind.
  local lib_keys = {}
  local timer = nil

  --- Everything on disk as of the last flush.
  local base = cfg.persist and store.load(namespace, cache_opts) or store.empty()
  --- Everything collected since. `report()` is `base + pending`, always.
  local pending = empty_delta()
  pending.sessions = 1
  pending.started_at = os.time()

  --- Read once per flush, not per call — see HONEST LIMITS.
  local today = store.today()

  -- -------------------------------------------------------------------------
  -- Hot path
  -- -------------------------------------------------------------------------

  ---@param key string
  ---@param fp string|nil
  ---@param dur number|nil
  ---@param errored boolean
  function inst._record(key, fp, dur, errored)
    local fns = pending.functions
    local s = fns[key]
    if not s then
      s = { calls = 0 }
      fns[key] = s
    end
    s.calls = s.calls + 1

    local day = pending.days[today]
    if not day then
      day = {}
      pending.days[today] = day
    end
    day[key] = (day[key] or 0) + 1

    if errored then
      s.errors = (s.errors or 0) + 1
    end

    if dur then
      local t = s.timing
      if not t then
        s.timing = { n = 1, total_ms = dur, min_ms = dur, max_ms = dur }
      else
        t.n = t.n + 1
        t.total_ms = t.total_ms + dur
        if dur < t.min_ms then
          t.min_ms = dur
        end
        if dur > t.max_ms then
          t.max_ms = dur
        end
      end
    end

    if fp then
      local a = s.args
      if not a then
        a = { values = {}, other = 0, distinct = 0, n = 0 }
        s.args = a
      end
      local cur = a.values[fp]
      if cur then
        a.values[fp] = cur + 1
      else
        a.distinct = a.distinct + 1
        if a.n < cfg.max_arg_values then
          a.values[fp] = 1
          a.n = a.n + 1
        else
          -- Bounded cardinality: a function called with 10 000 distinct paths
          -- costs `max_arg_values + 1` entries, not 10 000.
          a.other = a.other + 1
        end
      end
    end
  end

  -- -------------------------------------------------------------------------
  -- Attach / detach
  -- -------------------------------------------------------------------------

  local function attach_all()
    for _, tgt in ipairs(targets) do
      registry.attach(tgt.container, tgt.field, tgt.key, inst, tgt.wants)
    end
    attached = true
  end

  local function detach_all()
    for _, tgt in ipairs(targets) do
      registry.detach(tgt.container, tgt.field, inst)
    end
    attached = false
  end

  ---@param container table
  ---@param field string
  ---@param key string
  ---@param opts Lib.Telemetry.WrapOpts
  local function add_target(container, field, key, opts)
    for _, tgt in ipairs(targets) do
      if tgt.container == container and tgt.field == field then
        return
      end
    end
    targets[#targets + 1] = {
      container = container,
      field = field,
      key = key,
      wants = {
        args = opts.profile_args or false,
        time = opts.time or false,
        errors = opts.errors or false,
        outermost_only = opts.outermost_only or false,
      },
    }
    if running then
      local tgt = targets[#targets]
      registry.attach(tgt.container, tgt.field, tgt.key, inst, tgt.wants)
    end
  end

  -- -------------------------------------------------------------------------
  -- Public: scoping
  -- -------------------------------------------------------------------------

  ---Register every in-scope function field of `container`.
  ---@param container table
  ---@param prefix? string
  ---@param wrap_opts? Lib.Telemetry.WrapOpts
  ---@return integer registered
  function inst.wrap(container, prefix, wrap_opts)
    if type(container) ~= "table" then
      return 0
    end
    wrap_opts = wrap_opts or {}

    local n = 0
    for name, value in pairs(container) do
      if type(name) == "string" and type(value) == "function" then
        if in_scope(name, value, wrap_opts) then
          add_target(container, name, join_key(prefix, name), wrap_opts)
          n = n + 1
        end
      end
    end
    return n
  end

  ---Register a single function that is not reachable as a named table field —
  ---a closure returned by a factory, a callback held in a local.
  ---
  ---Returns a stable dispatcher the caller must store and use in place of the
  ---original. That indirection is what lets `start()`/`stop()` toggle the
  ---instrumentation without the caller's saved reference going stale.
  ---@param fn function
  ---@param key string
  ---@param wrap_opts? Lib.Telemetry.WrapOpts
  ---@return function dispatcher
  function inst.wrap_fn(fn, key, wrap_opts)
    if type(fn) ~= "function" then
      return fn
    end
    local box = { fn = fn }
    add_target(box, "fn", key, wrap_opts or {})
    return function(...)
      return box.fn(...)
    end
  end

  ---Register the `require("lib")` aggregate.
  ---
  ---The aggregate is the surface config code actually calls, and its key set is
  ---derivable (`lib.strategies.control`) rather than hand-maintained — a
  ---hand-written list is drift waiting to happen. Table-valued keys
  ---(`lib.strings`, `lib.kit`, …) have their own function fields registered one
  ---level deep, since `lib.strings` itself is never called.
  ---@param wrap_opts? Lib.Telemetry.WrapOpts
  ---@return integer registered
  function inst.wrap_lib(wrap_opts)
    wrap_opts = wrap_opts or {}

    local ok_lib, lib = pcall(require, "lib")
    if not ok_lib then
      return 0
    end
    local control = require("lib.strategies.control")

    local n = 0
    for _, key in ipairs(control.keys(lib)) do
      local ok_value, value = pcall(function()
        return lib[key]
      end)
      if ok_value and type(value) == "function" then
        if in_scope(key, value, wrap_opts) then
          -- Materialize behind the metatable so the field is a real, wrappable
          -- entry. rawset shadows `__index`, so the resolved-key cache cannot
          -- hand out the pre-wrap value for this key.
          rawset(lib, key, value)
          lib_keys[#lib_keys + 1] = key
          add_target(lib, key, key, wrap_opts)
          n = n + 1
        end
      elseif ok_value and type(value) == "table" then
        n = n + inst.wrap(value, key, wrap_opts)
      end
    end

    return n
  end

  ---Detach everything and forget the registered targets.
  function inst.unwrap()
    detach_all()
    targets = {}

    if #lib_keys > 0 then
      local ok_lib, lib = pcall(require, "lib")
      if ok_lib then
        for _, key in ipairs(lib_keys) do
          rawset(lib, key, nil)
        end
        require("lib.strategies.control").reset_cache()
      end
      lib_keys = {}
    end
  end

  ---@return string[]
  function inst.wrapped_keys()
    local out = {}
    for _, tgt in ipairs(targets) do
      out[#out + 1] = tgt.key
    end
    table.sort(out)
    return out
  end

  -- -------------------------------------------------------------------------
  -- Public: lifecycle
  -- -------------------------------------------------------------------------

  local function stop_timer()
    if timer then
      pcall(function()
        timer:stop()
        timer:close()
      end)
      timer = nil
    end
  end

  local function start_timer()
    stop_timer()
    if not cfg.persist or not cfg.flush_interval_ms or cfg.flush_interval_ms <= 0 then
      return
    end
    timer = uv.new_timer()
    if not timer then
      return
    end
    timer:start(cfg.flush_interval_ms, cfg.flush_interval_ms, function()
      -- Timer callbacks run in a fast event context; the flush does file IO
      -- and `os.date`, neither of which belongs there.
      vim.schedule(function()
        inst.flush()
      end)
    end)
  end

  ---Install the wrappers. Idempotent.
  ---
  ---`opts.profile_args` / `opts.time` / `opts.errors` take either a list of
  ---keys or `true`. Argument profiling is deliberately not a global default:
  ---counting is one integer add, fingerprinting is work on every call.
  ---
  ---A no-op while this namespace is persistently disabled
  ---(`telemetry.disable(namespace)` / `:LibTelemetry disable <ns>`) — the
  ---caller that wires `t.start()` up at startup does not need to know or
  ---care; the toggle takes effect without touching that call site.
  ---@param start_opts? Lib.Telemetry.StartOpts
  ---@return boolean started
  function inst.start(start_opts)
    -- Same `cache_opts` this instance already uses for its own counts — so a
    -- custom `dir` (tests; a plugin with its own cache location) is checked
    -- consistently by both. The one edge this does not cover: pre-emptively
    -- disabling a namespace, by name, before an instance with a non-default
    -- `dir` has ever been created — nothing yet knows what dir it will use.
    -- `telemetry.disable(namespace)` before that point falls back to the
    -- default (real) cache; see toggle.lua's module doc-comment.
    if toggle.is_disabled(namespace, cache_opts) then
      return false
    end
    start_opts = start_opts or {}

    for _, tgt in ipairs(targets) do
      tgt.wants.args = tgt.wants.args or selected(start_opts.profile_args, tgt.key)
      tgt.wants.time = tgt.wants.time or selected(start_opts.time, tgt.key)
      tgt.wants.errors = tgt.wants.errors or selected(start_opts.errors, tgt.key)
    end

    -- Unconditional: `attach` is idempotent per (container, field, instance)
    -- and re-attaching is how updated `wants` reach an already-installed site.
    attach_all()

    running = true
    start_timer()
    return true
  end

  ---Restore the originals. Keeps everything collected so far. Idempotent — a
  ---second `stop()`, or one on an instance that never started, is a no-op
  ---rather than an error, because hot-reloaded configs call setup paths twice.
  ---@return boolean stopped
  function inst.stop()
    if not running and not attached then
      return false
    end
    detach_all()
    running = false
    stop_timer()
    inst.flush()
    return true
  end

  ---@return boolean
  function inst.is_running()
    return running
  end

  -- -------------------------------------------------------------------------
  -- Public: data
  -- -------------------------------------------------------------------------

  ---Merge everything collected since the last flush into what is on disk.
  ---
  ---Re-reads first, so two Neovim instances sharing a namespace add up rather
  ---than overwrite each other.
  ---@return boolean ok
  function inst.flush()
    today = store.today()

    if not cfg.persist then
      store.merge(base, pending, cfg.max_arg_values)
      pending = empty_delta()
      inst._check_reminder(base)
      return true
    end

    local disk_data = store.load(namespace, cache_opts)
    store.merge(disk_data, pending, cfg.max_arg_values)
    store.prune(disk_data, cfg.retention_days)

    inst._check_reminder(disk_data)

    local ok = store.save(namespace, disk_data, cache_opts)
    if ok then
      base = disk_data
      pending = empty_delta()
    end
    return ok
  end

  ---@param data Lib.Telemetry.Data
  function inst._check_reminder(data)
    local msg = reminder.check(namespace, data, remind_after)
    if msg then
      vim.schedule(function()
        notify.info(msg)
      end)
    end
  end

  ---@return Lib.Telemetry.Data
  local function merged()
    local snapshot = vim.deepcopy(base)
    return store.merge(snapshot, pending, cfg.max_arg_values)
  end

  ---@param report_opts? Lib.Telemetry.ReportOpts
  ---@return Lib.Telemetry.Report
  function inst.report(report_opts)
    local modes = { counting = true, args = false, timing = false, errors = false }
    for _, tgt in ipairs(targets) do
      modes.args = modes.args or tgt.wants.args
      modes.timing = modes.timing or tgt.wants.time
      modes.errors = modes.errors or tgt.wants.errors
    end

    return report_mod.build(namespace, merged(), {
      running = running,
      disabled = toggle.is_disabled(namespace, cache_opts),
      wrapped = #targets,
      modes = modes,
    }, report_opts)
  end

  ---@param report_opts? Lib.Telemetry.ReportOpts
  ---@return string[]
  function inst.lines(report_opts)
    return report_mod.lines(inst.report(report_opts))
  end

  ---The inverse question: which registered functions were never called? An
  ---exported, documented, never-used function is a maintenance cost, and this
  ---is the set difference between the wrap list and the observed keys.
  ---@return { called: string[], uncalled: string[] }
  function inst.coverage()
    local data = merged()
    local called, uncalled = {}, {}
    for _, tgt in ipairs(targets) do
      local stats = data.functions[tgt.key]
      if stats and (stats.calls or 0) > 0 then
        called[#called + 1] = tgt.key
      else
        uncalled[#uncalled + 1] = tgt.key
      end
    end
    table.sort(called)
    table.sort(uncalled)
    return { called = called, uncalled = uncalled }
  end

  ---Drop everything collected, in memory and on disk. Wrapping is untouched.
  function inst.reset()
    base = store.empty()
    pending = empty_delta()
    pending.started_at = os.time()
    pending.sessions = 1
    if cfg.persist then
      store.clear(namespace, cache_opts)
    end
  end

  -- -------------------------------------------------------------------------
  -- Editor lifecycle
  -- -------------------------------------------------------------------------

  -- Raw augroup rather than autocmd.group(): that caches by name and would
  -- stop re-clearing for a second instance with the same namespace (a
  -- hot-reloaded plugin), leaving the previous instance's callbacks alongside
  -- the new ones instead of replacing them.
  local group = vim.api.nvim_create_augroup(
    "lib_telemetry_" .. store.sanitize(namespace),
    { clear = true }
  )

  autocmd.create("VimLeavePre", function()
    -- Flush is settled; restoring the wrappers is not worth doing at shutdown,
    -- so `stop()` is deliberately not called here — the process is ending and
    -- an unrestored wrapper cannot outlive it.
    pcall(inst.flush)
  end, { group = group, desc = "lib.nvim.telemetry: persist counters on exit" })

  autocmd.create("VimEnter", function()
    -- The one place the reminder is checked outside a flush: a session that
    -- never collects enough to trigger a periodic flush should still tell you
    -- about the week of data already on disk.
    pcall(inst._check_reminder, base)
  end, { group = group, desc = "lib.nvim.telemetry: lifecycle reminder" })

  instances[#instances + 1] = inst

  ---@type Lib.Telemetry.Instance
  return inst
end

-- ---------------------------------------------------------------------------
-- Module-level
-- ---------------------------------------------------------------------------

---Every live instance, so one command can report across all of them without
---each plugin having to register itself somewhere.
---@return Lib.Telemetry.Instance[]
function M.instances()
  return vim.list_slice(instances, 1, #instances)
end

---@param namespace string
---@return Lib.Telemetry.Instance|nil
function M.get(namespace)
  for _, inst in ipairs(instances) do
    if inst.namespace == namespace then
      return inst
    end
  end
  return nil
end

---@param opts? Lib.Telemetry.ReportOpts
---@return Lib.Telemetry.Report[]
function M.report_all(opts)
  local out = {}
  for _, inst in ipairs(instances) do
    out[#out + 1] = inst.report(opts)
  end
  return out
end

---@return integer flushed
function M.flush_all()
  local n = 0
  for _, inst in ipairs(instances) do
    if inst.flush() then
      n = n + 1
    end
  end
  return n
end

---@return integer stopped
function M.stop_all()
  local n = 0
  for _, inst in ipairs(instances) do
    if inst.stop() then
      n = n + 1
    end
  end
  return n
end

---Persistently disable a namespace: survives restarts, and takes effect
---without the caller who wired up `t.start()` needing to change anything —
---see `lib.nvim.telemetry.toggle` for why this is not just `inst.stop()`.
---Stops a live instance immediately if one exists; works even if none does
---(e.g. disabling a plugin before it has loaded this session).
---
---If a live instance already exists, the flag is persisted to ITS cache dir
---(same one `inst.start()` will check) rather than the default — matters
---only for an instance created with a custom `opts.dir`. Disabling a
---not-yet-created namespace always uses the default dir, since nothing yet
---knows what dir a future instance will pick.
---@param namespace string
function M.disable(namespace)
  local inst = M.get(namespace)
  toggle.disable(namespace, inst and inst._cache_opts or nil)
  if inst then
    inst.stop()
  end
end

---Clear a persistent disable. Resumes a live instance immediately if one
---exists (with whatever `start()` options it was last given).
---@param namespace string
function M.enable(namespace)
  local inst = M.get(namespace)
  toggle.enable(namespace, inst and inst._cache_opts or nil)
  if inst then
    inst.start()
  end
end

---@param namespace string
---@return boolean
function M.is_disabled(namespace)
  local inst = M.get(namespace)
  return toggle.is_disabled(namespace, inst and inst._cache_opts or nil)
end

---Every namespace currently persisted as disabled, sorted. Best-effort: only
---sees the default cache dir, so a namespace disabled under a live instance's
---custom `opts.dir` will not appear here even though `is_disabled()` for that
---exact namespace still returns correctly.
---@return string[]
function M.disabled()
  return toggle.disabled_list()
end

---@type Lib.Telemetry
return M
