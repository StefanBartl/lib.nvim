---@module 'lib.nvim.bindings.autocmd'
-- =========================================================
-- Autocommand helper utilities.
--
-- Provides standardized autocmd creation with automatic
-- augroup handling and defensive callbacks.
-- =========================================================

local notify = require("lib.nvim.notify").create("[lib.nvim.bindings.autocmd]")

local M = {}

M.augroup = require("lib.lua.lazy").require("lib.nvim.bindings.autocmd.augroup")
M.dispatcher = require("lib.lua.lazy").require("lib.nvim.bindings.autocmd.dispatcher")

---@type table<string, integer>
local groups = {}

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

--- Create (or look up) an augroup, memoized by name.
---
--- The cache is verified, not trusted. `nvim_del_augroup_by_name` is a normal
--- thing for a consumer to call -- a plugin that owns a group and wants to stop
--- owning it has no other way -- and the deleted id stayed in this cache, so
--- the next `group()` for that name handed back an id Neovim no longer knew and
--- every `create()` against it failed with "Invalid 'group'". Found from
--- lsp.nvim, whose `bindings/autocmds.clear()` does exactly that.
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
      return vim.api.nvim_create_augroup(name, { clear = true })
    end
    return cached
  end

  if clear == true then
    forget_group(name)
  end
  groups[name] = vim.api.nvim_create_augroup(name, { clear = clear == true })
  return groups[name]
end

---@type table<string, integer>
local cache = {}
-- Augroup registry.
--
-- Centralized augroup creation with optional prefixing
-- and deduplication.
---@param name string
---@param opts { clear?: boolean, prefix?: string }|nil
---@return integer
function M.get_augroup(name, opts)
  opts = opts or {}
  local full_name = opts.prefix and (opts.prefix .. "." .. name) or name

  if cache[full_name] == nil then
    cache[full_name] = vim.api.nvim_create_augroup(full_name, {
      clear = opts.clear == true,
    })
  end

  return cache[full_name]
end

---@param event string|string[]
---@param callback fun(args:Lib.Autocmd.Args)
---@param opts LibAutocmdOpts|nil
---@return integer autocmd_id
function M.create(event, callback, opts)
  opts = opts or {}

  if opts.desc == nil then
    opts.desc = ""
  end

  local group = opts.group
  if type(group) == "string" then
    group = M.group(group)
  end

  local user_cb = callback
  callback = function(args)
    local ok, err = pcall(user_cb, args)
    if not ok then
      local event_names = table.concat(vim.iter({ event }):flatten():totable(), ", ")
      notify.error(("Autocmd failed (%s):\n%s"):format(event_names, err))
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

  local id = vim.api.nvim_create_autocmd(event, native_opts)

  records[#records + 1] = {
    id = id,
    events = vim.iter({ event }):flatten():totable(),
    group = type(opts.group) == "string" and opts.group or nil,
    pattern = native_opts.pattern,
    buffer = native_opts.buffer,
    desc = opts.desc ~= "" and opts.desc or nil,
    once = native_opts.once,
    src = caller_site(),
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
