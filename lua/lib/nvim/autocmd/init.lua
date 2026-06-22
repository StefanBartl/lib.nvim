---@module 'lib.nvim.autocmd'
-- =========================================================
-- Autocommand helper utilities.
--
-- Provides standardized autocmd creation with automatic
-- augroup handling and defensive callbacks.
-- =========================================================

local notify = require("lib.nvim.notify").create("[lib.nvim.autocmd]")

local M = {}

M.augroup = require("lib.lua.lazy").require("lib.nvim.autocmd.augroup")

---@type table<string, integer>
local groups = {}

---@param name string
---@param clear boolean|nil
---@return integer
function M.group(name, clear)
  if groups[name] == nil then
    groups[name] = vim.api.nvim_create_augroup(name, { clear = clear == true })
  end
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
---@return nil
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
      notify.error(("Autocmd failed (%s):\n%s"):format( table.concat(vim.tbl_flatten({ event }), ", "), err ))
    end
  end

  vim.api.nvim_create_autocmd(event, {
    group = group,
    pattern = opts.pattern,
    desc = opts.desc,
    once = opts.once == true,
    nested = opts.nested == true,
    callback = callback,
  })
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

