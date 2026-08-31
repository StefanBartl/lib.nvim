---@module 'lib.nvim.bindings.autocmd.dispatcher'
--- Generic, event-agnostic autocmd dispatcher: one autocmd, many handlers.
---
--- Bundles N logically-related handlers behind a single `nvim_create_autocmd`,
--- keyed by a caller-supplied function of the event table (e.g. `ev.match`
--- for FileType — see `dispatcher.filetype` for that exact wrapper). What it
--- buys: uniform lazy-loading (a handler's `load` module is `require`d only
--- once its key actually matches), deterministic ordering via `priority`
--- (native autocmds fire in registration order, effectively arbitrary across
--- plugins), and a per-buffer `once` with no native equivalent
--- (`nvim_create_autocmd`'s own `once` is once-globally).
---
--- What it deliberately does NOT buy: raw speed. Neovim's autocmd dispatch is
--- C-side and already filters by event/pattern; this replaces that with one
--- autocmd that fires for every occurrence and does the matching in Lua, so
--- for a buffer with no registered handlers it does *more* work than native
--- autocmds would, not less.
---
--- Measured, so the trade is a number: a non-matching event costs ~30us here
--- against ~1us native -- but a native autocmd with an *empty* Lua callback
--- already costs ~29us, so what is being paid for is entering Lua at all, not
--- this module's own work (that is the remaining ~1us). Hits are a wash below
--- ~20 handlers and cheaper above. Full table, method and caveats in
--- README.md; benchmark script in the author's config repo under
--- `docs/ROADMAP/tools/autocmd_dispatch_bench.lua`.

require("lib.nvim.bindings.autocmd.dispatcher.@types")

local M = {}

-- `lib.nvim.bindings.autocmd` itself eagerly pulls this module in (`M.dispatcher =
-- ...`, mirroring how it already does for `augroup`), so requiring it back
-- at THIS file's top level would be a load-time cycle -- deferred to first
-- actual use (inside attach()) instead, by which point both modules have
-- finished loading.
---@return Lib.AutoCmd
local function get_autocmd()
  return require("lib.nvim.bindings.autocmd")
end

M.filetype = require("lib.lua.lazy").require("lib.nvim.bindings.autocmd.dispatcher.filetype")

--- Every dispatcher created in this session, in creation order.
---
--- A dispatcher collapses N handlers into ONE autocmd, so the autocmd registry
--- can only ever show one row for it -- and a generated table that says "one
--- autocmd on BufEnter" where ten features are listening is worse than no
--- table. `docs` reads this back to list the handlers underneath their
--- dispatcher, so collapsing them costs nothing in what the reader can see.
---@type Lib.Autocmd.Dispatcher.LiveEntry[]
local live = {}

---Every dispatcher created in this session, newest last.
---
---For `docs` and for `:checkhealth`-style introspection: what fans out from
---which autocmd, and which file registered each handler.
---@return Lib.Autocmd.Dispatcher.Entry[]
function M.registry()
  local out = {}
  for _, entry in ipairs(live) do
    out[#out + 1] = {
      name = entry.name,
      events = vim.deepcopy(entry.events),
      group = entry.group,
      attached = entry.handle.stats().attached,
      mode = entry.handle.stats().mode,
      handlers = entry.handle.handlers(),
    }
  end
  return out
end

--- Global default for `opts.dispatch`, read at every `attach()`.
---
--- `vim.g.lib_nvim_autocmd_dispatch = false` puts EVERY dispatcher into bypass
--- mode -- one plain autocmd per handler instead of one for all of them. Two
--- reasons it exists:
---
--- * **An escape hatch.** A dispatcher makes N features share one object. If
---   it misbehaves, the alternative used to be editing all N call sites. Now
---   it is a flag plus `reattach_all()`.
--- * **Checking the claim.** The README argues the shared dispatch costs a
---   flat ~30 us and that this should not decide anything. An argument you
---   cannot re-measure in your own config is one you have to take on faith.
---
--- Read at `attach()`, not at `new()`, so `detach()` -> flip -> `attach()`
--- switches a live dispatcher without rebuilding it.
---@return "dispatch"|"bypass"
local function resolve_mode(opts)
  if opts.dispatch ~= nil then
    return opts.dispatch == false and "bypass" or "dispatch"
  end
  if vim.g.lib_nvim_autocmd_dispatch == false then
    return "bypass"
  end
  return "dispatch"
end

---Re-attach every dispatcher that is currently attached.
---
---What makes the global switch usable: flipping `vim.g.lib_nvim_autocmd_dispatch`
---only takes effect at the next `attach()`, and nothing re-attaches on its own.
---Dispatchers that were never attached, or were explicitly detached, stay that
---way -- re-attaching those would turn something off back on behind the
---caller's back.
---@return integer reattached
function M.reattach_all()
  local n = 0
  for _, entry in ipairs(live) do
    if entry.handle.stats().attached then
      entry.handle.detach()
      entry.handle.attach()
      n = n + 1
    end
  end
  return n
end

---@internal
--- Where `register()` was called from, as `file:line`.
---
--- The same reasoning as in `lib.nvim.bindings.autocmd`: "something re-renders
--- the tree on BufEnter" is only half an answer without the file to open.
--- Level 3: getinfo -> this function -> handle.register -> the caller.
---@return string
local function caller_site()
  local info = debug.getinfo(3, "Sl")
  if not info then
    return "?"
  end
  local src = (info.source or "?"):gsub("^@", "")
  return ("%s:%d"):format(src, info.currentline or -1)
end

---@internal
--- Convert a glob-ish key pattern ("noice*") to an anchored Lua pattern.
---@param glob string
---@return string
local function glob_to_lua_pattern(glob)
  local escaped = glob:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
  escaped = escaped:gsub("%*", ".*")
  return "^" .. escaped .. "$"
end

---@internal
--- Exact match is the fast, common path; `*` triggers glob matching.
---@param pattern string
---@param candidate string
---@return boolean
local function key_matches(pattern, candidate)
  if pattern == candidate then
    return true
  end
  if not pattern:find("*", 1, true) then
    return false
  end
  return candidate:match(glob_to_lua_pattern(pattern)) ~= nil
end

---@param opts Lib.Autocmd.Dispatcher.Opts
---@return Lib.Autocmd.Dispatcher.Handle
function M.new(opts)
  assert(type(opts) == "table" and opts.event, "dispatcher.new: opts.event is required")
  assert(type(opts.key) == "function", "dispatcher.new: opts.key must be a function(ev)")

  ---@class Lib.Autocmd.Dispatcher.Registration
  ---@field keys string[]
  ---@field fn Lib.Autocmd.Dispatcher.HandlerFn
  ---@field priority integer
  ---@field once boolean
  ---@field id integer
  ---@field owner string|nil
  ---@field desc string|nil
  ---@field src string

  --- What this dispatcher is called in generated docs and introspection.
  local name = opts.name or opts.group or "dispatcher"

  --- Where this dispatcher was created, recorded onto the autocmds `attach()`
  --- makes. Without it they are attributed to this file -- and `docs` filters
  --- records by source, so the owning plugin's page would omit its own
  --- dispatcher, or refuse to render at all if the dispatcher is all it has.
  local created_at = caller_site()

  ---@type Lib.Autocmd.Dispatcher.Registration[]
  local registrations = {}
  local next_id = 0

  -- Resolved-and-sorted matches per concrete key, e.g. "lua" -> {reg1, reg2}.
  -- Cleared wholesale on every register() so a repeated key (the common case
  -- -- the same filetype opened many times) is matched/sorted once, not per
  -- dispatch.
  ---@type table<string, Lib.Autocmd.Dispatcher.Registration[]>
  local resolved_cache = {}

  -- once-per-buffer tracking. Keyed by real bufnr (a number, not a
  -- GC-collectible value) rather than a weak table, which would silently do
  -- nothing here -- weak tables only reclaim table/userdata/function/thread
  -- keys, never numbers. Cleaned up explicitly on BufWipeout instead (see
  -- attach()).
  ---@type table<integer, table<integer, boolean>>
  local once_seen = {}

  --- The single dispatch autocmd. `nil` in bypass mode.
  local autocmd_id = nil ---@type integer|nil
  --- Bypass mode: registration id -> its own autocmd id. Empty in dispatch mode.
  ---@type table<integer, integer>
  local per_handler = {}
  local cleanup_id = nil ---@type integer|nil
  --- Whichever mode `attach()` resolved. `nil` while detached.
  ---@type "dispatch"|"bypass"|nil
  local mode = nil

  ---@internal
  --- Does any of this registration's key patterns match the concrete key?
  ---@param reg Lib.Autocmd.Dispatcher.Registration
  ---@param concrete_key string
  ---@return boolean
  local function reg_matches(reg, concrete_key)
    for _, pat in ipairs(reg.keys) do
      if key_matches(pat, concrete_key) then
        return true
      end
    end
    return false
  end

  ---@internal
  ---@param concrete_key string
  ---@return Lib.Autocmd.Dispatcher.Registration[]
  local function resolve(concrete_key)
    local cached = resolved_cache[concrete_key]
    if cached then
      return cached
    end

    local matched = {}
    for _, reg in ipairs(registrations) do
      if reg_matches(reg, concrete_key) then
        matched[#matched + 1] = reg
      end
    end

    table.sort(matched, function(a, b)
      if a.priority ~= b.priority then
        return a.priority < b.priority
      end
      return a.id < b.id -- stable tiebreak: registration order
    end)

    resolved_cache[concrete_key] = matched
    return matched
  end

  ---@internal
  ---@param reg Lib.Autocmd.Dispatcher.Registration
  ---@param bufnr integer
  ---@return boolean
  local function should_run(reg, bufnr)
    if not reg.once then
      return true
    end
    local seen = once_seen[bufnr]
    if seen and seen[reg.id] then
      return false
    end
    once_seen[bufnr] = seen or {}
    once_seen[bufnr][reg.id] = true
    return true
  end

  ---@internal
  --- Registrations in dispatch order: priority, then registration id.
  ---@return Lib.Autocmd.Dispatcher.Registration[]
  local function sorted_regs()
    local out = {}
    for _, reg in ipairs(registrations) do
      out[#out + 1] = reg
    end
    table.sort(out, function(a, b)
      if a.priority ~= b.priority then
        return a.priority < b.priority
      end
      return a.id < b.id
    end)
    return out
  end

  ---@internal
  --- Bypass mode: give one registration its own plain autocmd.
  ---
  --- It still runs `opts.key(ev)` and matches in Lua -- the key is arbitrary
  --- Lua and generally cannot be expressed as an autocmd `pattern`. That means
  --- N handlers do the key work N times, which is exactly the shape this
  --- module replaced, and therefore the honest thing to measure against.
  ---
  --- `src` is the registration's own call site, so these show up in a
  --- generated bindings table attributed to the feature that owns them rather
  --- than to whoever built the dispatcher.
  ---@param reg Lib.Autocmd.Dispatcher.Registration
  ---@return integer autocmd_id
  local function create_bypass(reg)
    return get_autocmd().create(opts.event, function(ev)
      local concrete_key = opts.key(ev)
      if concrete_key == nil or not reg_matches(reg, concrete_key) then
        return
      end
      if not should_run(reg, ev.buf) then
        return
      end
      reg.fn({
        ev = ev,
        buf = ev.buf,
        key = concrete_key,
        -- Per matching handler here, once per event in dispatch mode. The one
        -- observable difference a caller with an expensive or side-effecting
        -- `context` has to know about.
        context = opts.context and opts.context(ev) or nil,
      })
    end, {
      group = opts.group,
      pattern = opts.pattern or "*",
      desc = reg.desc or ("%s handler: %s"):format(name, table.concat(reg.keys, ", ")),
      src = reg.src,
    })
  end

  local handle = {}

  --- Register one handler for one or more keys.
  ---
  --- `spec.owner` names whoever registered it, so it can be taken back out
  --- again with `unregister(owner)`; `spec.desc` is what the generated
  --- bindings table prints for it. Both are optional and both are worth
  --- giving: without an owner a handler can only ever be removed by tearing
  --- the whole dispatcher down, and without a desc the table says
  --- `_(no desc)_`.
  ---@param key_or_keys string|string[]
  ---@param spec Lib.Autocmd.Dispatcher.Handler
  ---@return Lib.Autocmd.Dispatcher.Handle
  function handle.register(key_or_keys, spec)
    local keys = type(key_or_keys) == "table" and key_or_keys or { key_or_keys }
    assert(#keys > 0, "dispatcher.register: at least one key is required")

    local fn, priority, once, owner, desc
    if type(spec) == "function" then
      fn, priority, once = spec, 0, false
    else
      assert(
        type(spec) == "table" and type(spec.load) == "function",
        "dispatcher.register: handler must be a function or { load = fn }"
      )
      fn, priority, once = spec.load, spec.priority or 0, spec.once == true
      owner, desc = spec.owner, spec.desc
    end

    next_id = next_id + 1
    registrations[#registrations + 1] = {
      keys = keys,
      fn = fn,
      priority = priority,
      once = once,
      id = next_id,
      owner = owner,
      desc = desc,
      src = caller_site(),
    }
    resolved_cache = {} -- one new registration can change any key's resolution

    -- Bypass mode builds one autocmd per registration up front, so a handler
    -- that arrives after attach() needs its own here. Note that it lands at
    -- the END of the event's autocmd list whatever its `priority` says --
    -- native autocmds fire in creation order and there is no way to insert.
    -- Register before attach() if the order matters, which is what the
    -- setup/install lifecycle this module is built for already does.
    if mode == "bypass" then
      per_handler[registrations[#registrations].id] = create_bypass(registrations[#registrations])
    end

    return handle
  end

  --- Take every handler registered under `owner` back out again.
  ---
  --- Without this a shared dispatcher cannot be used by anything with a
  --- `setup()`/`teardown()` cycle. A plain autocmd is cleared by re-creating
  --- its augroup with `clear = true`, and that is exactly what a feature's
  --- idempotent re-setup relies on; handing the same handler to a shared
  --- dispatcher a second time would instead run it twice per event, and there
  --- would be no way to stop it short of `detach()`, which takes every other
  --- feature's handlers down with it.
  ---
  --- Also forgets the `once`-per-buffer bookkeeping for the removed handlers,
  --- so re-registering the same owner starts clean rather than inheriting
  --- "already ran" from the previous cycle.
  ---@param owner string
  ---@return integer removed  # how many registrations were dropped
  function handle.unregister(owner)
    assert(type(owner) == "string" and owner ~= "", "dispatcher.unregister: owner is required")

    local kept, dropped = {}, {}
    for _, reg in ipairs(registrations) do
      if reg.owner == owner then
        dropped[#dropped + 1] = reg.id
      else
        kept[#kept + 1] = reg
      end
    end

    if #dropped == 0 then
      return 0
    end

    registrations = kept
    resolved_cache = {}
    for _, seen in pairs(once_seen) do
      for _, id in ipairs(dropped) do
        seen[id] = nil
      end
    end
    for _, id in ipairs(dropped) do
      if per_handler[id] then
        get_autocmd().delete(per_handler[id])
        per_handler[id] = nil
      end
    end

    return #dropped
  end

  --- Every handler currently registered, in dispatch order.
  ---
  --- What `docs` renders underneath the dispatcher's single autocmd, so
  --- collapsing N handlers into one autocmd does not cost the reader the list
  --- of what actually listens.
  ---@return Lib.Autocmd.Dispatcher.HandlerInfo[]
  function handle.handlers()
    local out = {}
    for _, reg in ipairs(registrations) do
      out[#out + 1] = {
        keys = vim.deepcopy(reg.keys),
        owner = reg.owner,
        desc = reg.desc,
        priority = reg.priority,
        once = reg.once,
        src = reg.src,
      }
    end
    table.sort(out, function(a, b)
      if a.priority ~= b.priority then
        return a.priority < b.priority
      end
      return (a.keys[1] or "") < (b.keys[1] or "")
    end)
    return out
  end

  --- Create the underlying autocmd(s). Idempotent -- a second call is a no-op.
  ---
  --- Resolves the mode here rather than in `new()`, so `detach()` -> flip
  --- `vim.g.lib_nvim_autocmd_dispatch` -> `attach()` switches a live
  --- dispatcher between one shared autocmd and one per handler.
  ---@return Lib.Autocmd.Dispatcher.Handle
  function handle.attach()
    if mode then
      return handle
    end

    local autocmd = get_autocmd()
    mode = resolve_mode(opts)

    if mode == "bypass" then
      -- Created in dispatch order: native autocmds fire in creation order, so
      -- this is the only point at which `priority` can be honoured at all.
      for _, reg in ipairs(sorted_regs()) do
        per_handler[reg.id] = create_bypass(reg)
      end
      cleanup_id = autocmd.create("BufWipeout", function(args)
        once_seen[args.buf] = nil
      end, {
        group = opts.group,
        pattern = "*",
        desc = ("Drop %s's once-per-buffer bookkeeping for a wiped buffer"):format(name),
        src = created_at,
      })
      return handle
    end

    autocmd_id = autocmd.create(opts.event, function(ev)
      local concrete_key = opts.key(ev)
      if concrete_key == nil then
        return
      end

      local matched = resolve(concrete_key)
      if #matched == 0 then
        return
      end

      local ctx_value = opts.context and opts.context(ev) or nil

      for _, reg in ipairs(matched) do
        if should_run(reg, ev.buf) then
          reg.fn({ ev = ev, buf = ev.buf, key = concrete_key, context = ctx_value })
        end
      end
    end, {
      group = opts.group,
      pattern = opts.pattern or "*",
      desc = opts.desc or ("Dispatch %s to its registered handlers"):format(name),
      src = created_at,
    })

    cleanup_id = autocmd.create("BufWipeout", function(args)
      once_seen[args.buf] = nil
    end, {
      group = opts.group,
      pattern = "*",
      desc = ("Drop %s's once-per-buffer bookkeeping for a wiped buffer"):format(name),
      src = created_at,
    })

    return handle
  end

  --- Remove the underlying autocmd(s). Idempotent; does not clear the
  --- registry -- a later attach() dispatches to the same handlers again.
  ---@return Lib.Autocmd.Dispatcher.Handle
  function handle.detach()
    -- `delete`, not `nvim_del_autocmd`: the latter leaves the record behind,
    -- so a detached dispatcher would go on being listed in the generated
    -- bindings table as if it still fired.
    local autocmd = get_autocmd()
    if autocmd_id then
      autocmd.delete(autocmd_id)
      autocmd_id = nil
    end
    for id, au_id in pairs(per_handler) do
      autocmd.delete(au_id)
      per_handler[id] = nil
    end
    if cleanup_id then
      autocmd.delete(cleanup_id)
      cleanup_id = nil
    end
    mode = nil
    return handle
  end

  --- Introspection: registered key count, handler count, and attach state.
  ---@return Lib.Autocmd.Dispatcher.Stats
  function handle.stats()
    local key_set = {}
    for _, reg in ipairs(registrations) do
      for _, k in ipairs(reg.keys) do
        key_set[k] = true
      end
    end

    return {
      total_keys = vim.tbl_count(key_set),
      total_handlers = #registrations,
      keys = vim.tbl_keys(key_set),
      attached = mode ~= nil,
      mode = mode,
      autocmds = autocmd_id and 1 or vim.tbl_count(per_handler),
    }
  end

  live[#live + 1] = {
    name = name,
    events = vim.iter({ opts.event }):flatten():totable(),
    group = opts.group,
    handle = handle,
  }

  ---@type Lib.Autocmd.Dispatcher.Handle
  return handle
end

---@type Lib.Autocmd.Dispatcher
return M
