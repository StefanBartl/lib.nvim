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
--- autocmds would, not less. See this module's own README.md for the full
--- reasoning it was built from.

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

  local autocmd_id = nil ---@type integer|nil
  local cleanup_id = nil ---@type integer|nil

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
      for _, pat in ipairs(reg.keys) do
        if key_matches(pat, concrete_key) then
          matched[#matched + 1] = reg
          break
        end
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

  local handle = {}

  --- Register one handler for one or more keys.
  ---@param key_or_keys string|string[]
  ---@param spec Lib.Autocmd.Dispatcher.Handler
  ---@return Lib.Autocmd.Dispatcher.Handle
  function handle.register(key_or_keys, spec)
    local keys = type(key_or_keys) == "table" and key_or_keys or { key_or_keys }
    assert(#keys > 0, "dispatcher.register: at least one key is required")

    local fn, priority, once
    if type(spec) == "function" then
      fn, priority, once = spec, 0, false
    else
      assert(
        type(spec) == "table" and type(spec.load) == "function",
        "dispatcher.register: handler must be a function or { load = fn }"
      )
      fn, priority, once = spec.load, spec.priority or 0, spec.once == true
    end

    next_id = next_id + 1
    registrations[#registrations + 1] =
      { keys = keys, fn = fn, priority = priority, once = once, id = next_id }
    resolved_cache = {} -- one new registration can change any key's resolution

    return handle
  end

  --- Create the underlying autocmd(s). Idempotent -- a second call is a no-op.
  ---@return Lib.Autocmd.Dispatcher.Handle
  function handle.attach()
    if autocmd_id then
      return handle
    end

    local autocmd = get_autocmd()

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
    end, { group = opts.group, pattern = opts.pattern or "*" })

    cleanup_id = autocmd.create("BufWipeout", function(args)
      once_seen[args.buf] = nil
    end, { pattern = "*" })

    return handle
  end

  --- Remove the underlying autocmd(s). Idempotent; does not clear the
  --- registry -- a later attach() dispatches to the same handlers again.
  ---@return Lib.Autocmd.Dispatcher.Handle
  function handle.detach()
    if autocmd_id then
      pcall(vim.api.nvim_del_autocmd, autocmd_id)
      autocmd_id = nil
    end
    if cleanup_id then
      pcall(vim.api.nvim_del_autocmd, cleanup_id)
      cleanup_id = nil
    end
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
      attached = autocmd_id ~= nil,
    }
  end

  ---@type Lib.Autocmd.Dispatcher.Handle
  return handle
end

---@type Lib.Autocmd.Dispatcher
return M
