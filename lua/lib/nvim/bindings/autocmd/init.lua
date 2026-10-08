---@module 'lib.nvim.bindings.autocmd'
--- Autocommand helpers: standardized creation with automatic augroup handling,
--- defensive (pcall-wrapped) callbacks, and a registry read back by the
--- generated-docs writers.

local notify = require("lib.nvim.notify").create("[lib.nvim.bindings.autocmd]")

local M = {}

M.augroup = require("lib.lua.lazy").require("lib.nvim.bindings.autocmd.augroup")
M.dispatcher = require("lib.lua.lazy").require("lib.nvim.bindings.autocmd.dispatcher")
M.docs = require("lib.lua.lazy").require("lib.nvim.bindings.autocmd.docs")

---@type table<string, integer>
local groups = {}

--- id -> name, so a record can name its group even when the caller passed
--- the id. Most callers do: they take `group(name)` once into a local and
--- hand the integer to every `create()` after it, which is the documented
--- shape of `nvim_create_autocmd` and not something to talk them out of.
---@type table<integer, string>
local group_names = {}

---@internal
--- Does this augroup id still exist?
---
--- `nvim_get_autocmds` raises for an unknown group, which is the only way to
--- ask -- there is no lookup that returns nil.
---@param id integer
---@return boolean
local function group_exists(id)
  return (pcall(vim.api.nvim_get_autocmds, { group = id }))
end

---@type table<string, integer>
local cache = {}

--- Prune once the three caches together hold more than this many entries;
--- doubles with the live count, so a long-lived plugin never prunes per call.
local PRUNE_ABOVE = 64

---@internal
--- Drop the cache entries of augroups Neovim no longer knows.
---
--- Callers delete groups behind this module's back (`nvim_del_augroup_by_id`
--- when a popup closes); the ids stayed in `groups`, `group_names` and `cache`
--- for good, two stale entries per popup. Every cache entry costs one
--- `nvim_get_autocmds` call here, which is why this runs only when the caches
--- have outgrown `PRUNE_ABOVE`, not on every lookup. The records of a dead
--- group stay: they are the caller's to forget (`forget_group`, or
--- `record = false` for a throwaway).
local function prune_dead_groups()
  local size = 0
  for _ in pairs(group_names) do
    size = size + 1
  end
  if size <= PRUNE_ABOVE then
    return
  end
  local alive = {}
  for id in pairs(group_names) do
    alive[id] = group_exists(id)
  end
  for id in pairs(alive) do
    if not alive[id] then
      group_names[id] = nil
    end
  end
  for name, id in pairs(groups) do
    if alive[id] == false then
      groups[name] = nil
    end
  end
  for name, id in pairs(cache) do
    if alive[id] == false then
      cache[name] = nil
    end
  end
  -- Twice what survived (never below 64): a growing set of live groups prunes
  -- every time it has doubled, not on every new group.
  local live = 0
  for id in pairs(alive) do
    if alive[id] then
      live = live + 1
    end
  end
  PRUNE_ABOVE = math.max(64, 2 * live)
end

--- Every autocmd this module created, in creation order.
---
--- Recorded rather than catalogued by hand. A plugin's own list of "what
--- fires when" is a mirror, and mirrors drift: filetree's hand-written one
--- claimed fourteen entries against forty-six real registrations, and nothing
--- anywhere said so. This one cannot be wrong about what exists, because it
--- *is* what exists.
---
--- The source location is part of the answer. "Something re-highlights on
--- CursorMoved" is only half of what a reader wants; the other half is which
--- file to open.
---@type Lib.Autocmd.Record[]
local records = {}

---@internal
--- Where `create()` was called from, as `file:line`.
---
--- Level 3: getinfo -> this function -> M.create -> the caller.
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
--- Forget every record belonging to `group_name`.
---
--- Called when an augroup is cleared: Neovim drops the autocmds, so keeping
--- their records would make the list grow on every `setup()` and describe
--- autocmds that no longer fire -- the exact failure the hand-written
--- catalogues had.
---@param group_name string
---@return nil
local function forget_group(group_name)
  local kept = {}
  for _, r in ipairs(records) do
    if r.group ~= group_name then
      kept[#kept + 1] = r
    end
  end
  records = kept
end

---Forget every record belonging to the augroup `name`.
---
---For code that clears or replaces a group by another route than `group()` /
---`get_augroup()` (`augroup.create.clear` does): Neovim drops the autocmds of
---a cleared group, so their records must go too or the registry grows on every
---`setup()`.
---@param name string
---@return nil
function M.forget_group(name)
  forget_group(name)
end

---Every autocmd created through this module, newest last.
---
---What `:checkhealth`, a generated bindings page and a "what fires on
---BufWritePost" question all need, without any of them re-deriving it from
---source.
---@param filter { event?: string, group?: string }|nil
---@return Lib.Autocmd.Record[]
function M.registered(filter)
  if not filter then
    return vim.deepcopy(records)
  end
  local out = {}
  for _, r in ipairs(records) do
    local ok = true
    if filter.group and r.group ~= filter.group then
      ok = false
    end
    if ok and filter.event then
      ok = false
      for _, e in ipairs(r.events) do
        if e == filter.event then
          ok = true
          break
        end
      end
    end
    if ok then
      out[#out + 1] = vim.deepcopy(r)
    end
  end
  return out
end

---The same records grouped by event, which is how the question is usually
---asked: "what happens on FileType?"
---@return table<string, Lib.Autocmd.Record[]>
function M.by_event()
  local out = {}
  for _, r in ipairs(records) do
    for _, e in ipairs(r.events) do
      out[e] = out[e] or {}
      out[e][#out[e] + 1] = vim.deepcopy(r)
    end
  end
  return out
end

---Delete an autocmd **and** forget its record.
---
---`nvim_del_autocmd` alone leaves the record behind: the autocmd stops firing
---and the generated bindings table goes on listing it, which is the precise
---failure this registry exists to prevent. Clearing an augroup through
---`group(name, true)` already forgets its records; this is the same guarantee
---for deleting one autocmd by id.
---
---Found from the dispatcher's `detach()`: flipping a dispatcher between shared
---and per-handler mode twice left sixteen records describing fourteen real
---autocmds.
---@param id integer
---@return boolean deleted  # false when nvim did not know the id
function M.delete(id)
  local deleted = pcall(vim.api.nvim_del_autocmd, id)
  local kept = {}
  for _, r in ipairs(records) do
    if r.id ~= id then
      kept[#kept + 1] = r
    end
  end
  records = kept
  return deleted
end

--- Create (or look up) an augroup, memoized by name.
---
--- The cache is verified, not trusted. `nvim_del_augroup_by_name` is a normal
--- thing for a consumer to call -- a plugin that owns a group and wants to stop
--- owning it has no other way -- and the deleted id stayed in this cache, so
--- the next `group()` for that name handed back an id Neovim no longer knew and
--- every `create()` against it failed with "Invalid 'group'". Found from
--- lsp.nvim, whose `bindings/autocmds.clear()` does exactly that.
---@param name string
---@param clear boolean|nil
---@return integer
function M.group(name, clear)
  local cached = groups[name]
  if cached ~= nil and group_exists(cached) then
    if clear == true then
      -- Re-requesting with `clear` must still clear: the caller is rebuilding
      -- its autocommands, and leaving the old ones would double them up.
      forget_group(name)
      local id = vim.api.nvim_create_augroup(name, { clear = true })
      groups[name] = id
      group_names[id] = name
      return id
    end
    return cached
  end

  if clear == true then
    forget_group(name)
  end
  prune_dead_groups()
  groups[name] = vim.api.nvim_create_augroup(name, { clear = clear == true })
  group_names[groups[name]] = name
  return groups[name]
end

--- Augroup registry: create or look up an augroup, optionally namespaced with
--- `opts.prefix` and deduplicated by the resulting full name. Unlike `group()`
--- above, the cache here is not re-verified against Neovim.
---@param name string
---@param opts { clear?: boolean, prefix?: string }|nil
---@return integer
function M.get_augroup(name, opts)
  opts = opts or {}
  local full_name = opts.prefix and (opts.prefix .. "." .. name) or name

  if cache[full_name] == nil then
    if opts.clear == true then
      -- A group of this name may already exist (a reloaded module has a fresh
      -- cache): clearing it drops its autocmds, so drop their records too.
      forget_group(full_name)
    end
    prune_dead_groups()
    cache[full_name] = vim.api.nvim_create_augroup(full_name, {
      clear = opts.clear == true,
    })
  elseif opts.clear == true then
    -- Re-requesting with `clear` must still clear, same as `group()` above:
    -- the caller is rebuilding its autocommands, and a cache hit that skips
    -- the re-clear leaves the old ones registered alongside the new. The
    -- records of the cleared autocmds go with them, or the registry grows on
    -- every setup() and lists autocmds that no longer fire.
    forget_group(full_name)
    cache[full_name] = vim.api.nvim_create_augroup(full_name, { clear = true })
  end
  group_names[cache[full_name]] = full_name

  return cache[full_name]
end

---@internal
--- Entries held by the group caches (`group_names`); for specs.
---@return integer
function M._cache_size()
  local n = 0
  for _ in pairs(group_names) do
    n = n + 1
  end
  return n
end

---Create an autocmd and record it, unless `opts.record` is `false`.
---
---The callback is wrapped in `pcall` unless `opts.raw` is true; see the note
---at that wrapper for the two cases that need it off.
---
---`record = false` is for throwaway autocmds of something that lives for a
---moment and is created over and over -- a popup's per-window lifecycle hooks.
---Their group name carries the window id, so it is new every time and nothing
---ever asks for the same group again; the record would outlive the autocmd for
---good. The keymap wrapper has the same option for the same reason. It is the
---caller's call, not automatic (`once` autocmds keep their record after they
---fire): the generated tables are built from these records.
---@param event string|string[]
---@param callback fun(args:Lib.Autocmd.Args): boolean|nil  # a `true` return deletes the autocmd (native behaviour; needs `opts.raw`)
---@param opts LibAutocmdOpts|nil
---@return integer autocmd_id
function M.create(event, callback, opts)
  opts = opts or {}

  if opts.desc == nil then
    opts.desc = ""
  end

  local group = opts.group
  local group_name = nil
  if type(group) == "string" then
    group_name = group
    group = M.group(group)
  elseif type(group) == "number" then
    group_name = group_names[group]
  end

  -- The pcall wrapper turns a crashing callback into one notification instead
  -- of a stack trace on every event, which is what almost every caller wants.
  -- Two callbacks want the opposite, and both are load-bearing:
  --
  --   * a `BufWritePre` guard that calls `error()` to CANCEL the write --
  --     wrapped, the write goes through and the guard silently does nothing;
  --   * a callback that returns `true` to delete its own autocmd -- wrapped,
  --     the return value is discarded and it fires forever.
  --
  -- Those used to be reasons to bypass this module altogether, which cost them
  -- their record and their row in the generated table. `raw` keeps the record
  -- and gives up only the wrapper.
  if opts.raw ~= true then
    local user_cb = callback
    callback = function(args)
      local ok, err = pcall(user_cb, args)
      if not ok then
        local event_names = table.concat(vim.iter({ event }):flatten():totable(), ", ")
        notify.error(("Autocmd failed (%s):\n%s"):format(event_names, err))
      end
    end
  end

  local native_opts = {
    group = group,
    desc = opts.desc,
    once = opts.once == true,
    nested = opts.nested == true,
    callback = callback,
  }
  -- `pattern` and `buffer` are mutually exclusive in nvim_create_autocmd;
  -- a buffer-scoped request must win outright, or every buffer-local autocmd
  -- silently downgrades to a global `pattern = "*"` (opts.pattern is nil).
  if opts.buffer ~= nil then
    native_opts.buffer = opts.buffer
  else
    native_opts.pattern = opts.pattern
  end

  -- Counting this one would report lib.nvim itself as having an
  -- undocumented autocmd forever: it IS the registering call.
  -- lib-docs: fallback
  local id = vim.api.nvim_create_autocmd(event, native_opts)

  if opts.record == false then
    return id
  end

  records[#records + 1] = {
    id = id,
    events = vim.iter({ event }):flatten():totable(),
    group = group_name,
    pattern = native_opts.pattern,
    buffer = native_opts.buffer,
    desc = opts.desc ~= "" and opts.desc or nil,
    once = native_opts.once,
    -- `opts.src` lets a wrapper that creates an autocmd on someone else's
    -- behalf say whose it is. Without it the dispatcher's own autocmd is
    -- attributed to this file, so a plugin that routes everything through a
    -- dispatcher owns no records at all and `docs.write()` refuses with
    -- "nothing registered".
    src = opts.src or caller_site(),
  }

  return id
end

-- Normalize event configuration to a non-empty list.
-- - Always guarantees a non-empty string[] for Autocmd events
-- - Decoups feature configuration from internal defaults
--
-- - Allows multiple configuration options:
--  * Explicit event list
--  * False / nil / empty table → Fallback
-- - Prevents errors such as:
--  * Empty event lists
--  * Incorrect types
--  * Uninitialized fields
---@param ev any
---@param fallback string[]
---@return string[]
function M.norm_events(ev, fallback)
  if type(ev) == "table" and #ev > 0 then
    return ev
  end
  return fallback
end

--- Normalize an autocmd pattern field.
---@param pat any
---@return string|string[]
function M.norm_pattern(pat)
  if pat == nil then
    return "*"
  end
  return pat
end

---@type Lib.AutoCmd
return M
