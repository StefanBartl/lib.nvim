---@module 'lib.nvim.bindings.keymap.which_key'
--- which-key integration for registered keymap actions -- deliberately narrow.
---@description
--- **What which-key already does by itself.** It reads `nvim_get_keymap` and
--- `nvim_buf_get_keymap` and labels each mapping with its own `desc`
--- (`which-key/buf.lua`). A plugin that sets a `desc` -- which
--- `keymap.register` always does -- therefore appears in which-key with the
--- right label *without registering anything at all*.
---
--- That is worth stating plainly, because the obvious API here would be a
--- `which_key = true` switch per action, and it would do **nothing**: it is
--- already the state of the world. Three things are genuinely outside what
--- which-key can infer, and those are what this module covers:
---
---  1. **Group labels.** which-key sees `<leader>sk` and `<leader>sK` but has
---     no way to know that `<leader>s` is "spotlight". Only the plugin knows.
---  2. **Icons.** Not derivable from a mapping -- and only sent when
---     `vim.g.have_nerd_font` says so; see `icons_ok`.
---  3. **Hiding.** `which_key = false` on an action. which-key's own
---     convention for this is the magic description `which_key_ignore`, which
---     `registry.lua` applies directly -- so hiding needs no which-key
---     dependency and works even when which-key is not installed.
---
--- **Soft dependency.** which-key is optional. Nothing here loads it eagerly
--- and nothing fails when it is absent; the mappings simply carry their `desc`
--- and which-key, if it ever appears, picks them up.
---
--- **The spec.** `which_key` may be given at two levels, and a table implies
--- "yes" -- there is no separate `true` to remember:
---
--- ```lua
--- keymap.register("spotlight", {
---   prefix = "<leader>s",
---   which_key = { group = "spotlight", icon = "" },   -- the group label
---   actions = {
---     toggle = { default = "<leader>sK", rhs = ..., desc = "...",
---                which_key = { icon = "" } },        -- per action extras
---     debug  = { default = "g?", rhs = ..., desc = "...",
---                which_key = false },                 -- hidden from which-key
---   },
--- }, cfg.keymaps)
--- ```
---
--- A user can override the group from their own spec with
--- `keymaps = { which_key = { group = "…" } }`, or switch the plugin's group
--- registration off entirely with `keymaps = { which_key = false }` -- their
--- per-action `which_key = false` still hides individual keys either way,
--- since that path does not run through which-key at all.

local M = {}

---@type (fun(mod: table))[]  deliveries waiting for which-key to be loaded
local pending = {}

---@type boolean
local watching = false

---@internal
---which-key, only when it is ALREADY loaded. Never `require`s it: under a lazy
---plugin manager a `require` is the load trigger, and registering a group label
---during startup used to pull the whole plugin in (9-17 ms) for a popup nobody
---has opened yet -- which-key is meant to load on the first `<leader>`.
---@return table|nil
local function loaded_wk()
  local mod = package.loaded["which-key"]
  if type(mod) == "table" then
    return mod
  end
  return nil
end

---@internal
---Hand every queued entry list to which-key, once it is there.
---@return boolean flushed  false while which-key is still not loaded
local function flush()
  local mod = loaded_wk()
  if not mod then
    return false
  end
  local queued = pending
  pending = {}
  for _, delivery in ipairs(queued) do
    -- pcall: which-key's spec format has changed between majors, and a label
    -- being wrong is never worth taking a plugin's setup down with it.
    pcall(delivery, mod)
  end
  return true
end

---@internal
---Flush when which-key shows up. Under lazy.nvim every plugin load (also one
---triggered by someone else's `require`) fires `User LazyLoad`; `VimEnter` /
---`UIEnter` cover a manager that loads it eagerly without an event. One
---watcher, removed once it has delivered.
---@return nil
local function watch()
  if watching then
    return
  end
  watching = true
  local group = vim.api.nvim_create_augroup("lib.nvim.which_key.pending", { clear = true })
  vim.api.nvim_create_autocmd({ "User", "VimEnter", "UIEnter" }, {
    group = group,
    callback = function(ev)
      if ev.event == "User" and ev.match ~= "LazyLoad" and ev.match ~= "VeryLazy" then
        return
      end
      if flush() then
        watching = false
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end
    end,
    desc = "lib.nvim: deliver queued which-key labels once which-key is loaded",
  })
end

---Run `fn(which_key)` once which-key is loaded: at once if it already is,
---otherwise when it loads (see `watch`). For a caller that speaks to which-key
---in its own way -- v2's `register`, a spec it builds itself -- but must not
---`require` it while a lazy manager would take that as the load trigger.
---@param fn fun(mod: table)
---@return boolean ran  true when it ran now, false when it was queued
function M.when_loaded(fn)
  local mod = loaded_wk()
  if mod then
    pcall(fn, mod)
    return true
  end
  pending[#pending + 1] = fn
  watch()
  return false
end

---@internal
---Send `entries` now if which-key is loaded, else queue them.
---@param entries table[]
---@return boolean applied  true when which-key took them, false when queued or rejected
local function send(entries)
  local function deliver(mod)
    if type(mod.add) ~= "function" then
      return false
    end
    return (pcall(mod.add, entries))
  end
  local mod = loaded_wk()
  if mod then
    return deliver(mod)
  end
  pending[#pending + 1] = deliver
  watch()
  return false
end

---Queued label lists that have not reached which-key yet (tests, `:checkhealth`).
---@return integer
function M.pending_count()
  return #pending
end

---Deliver anything queued, if which-key is loaded by now.
---@return boolean flushed
function M.flush()
  return flush()
end

---@internal
--- Is it safe to send icons? Declared by the user, not detected -- see
--- `lib.nvim.ui.nerd_font` for why detection is impossible.
---@return boolean
local function icons_ok()
  return require("lib.nvim.ui.nerd_font").available()
end

---Build one which-key group entry.
---@param prefix string
---@param g table|true  # `{ group?, icon?, mode? }`, or `true` for the plain label
---@param plugin string  # Fallback label.
---@return table
function M.entry(prefix, g, plugin)
  local entry = { prefix, group = (type(g) == "table" and g.group) or plugin }
  if type(g) == "table" then
    -- Icons only where the user says a Nerd Font is present: which-key draws
    -- the glyph either way, and without the font it is an empty box.
    if g.icon and icons_ok() then
      entry.icon = g.icon
    end
    if g.mode then
      entry.mode = g.mode
    end
  end
  return entry
end

---Label one prefix as a group, outside of a `register` call. Delivered when
---which-key is loaded: at once if it already is, otherwise queued until it loads.
---
---`register` puts a plugin's own groups up by itself; this is for the cases
---where the prefix is not known until the user's config has been read --
---sessions.nvim's keys are entirely opt-in, so the prefix they share is
---whatever the user picked.
---@param spec { prefix: string, group?: string, icon?: string, mode?: string|string[] }|table[]
---@return boolean applied  false when queued (which-key not loaded yet) or rejected
function M.add_group(spec)
  vim.validate("spec", spec, "table")

  ---@type table[]
  local entries = {}
  local list = spec[1] ~= nil and spec or { spec }
  for _, g in ipairs(list) do
    if g.prefix then
      entries[#entries + 1] = M.entry(g.prefix, g, g.group or "")
    end
  end
  if #entries == 0 then
    return false
  end

  return send(entries)
end

---Register what which-key cannot infer: the prefix group label, and any
---per-action icons.
---
---Called by `registry.register` after the mappings are set. Silent and
---harmless when which-key is not installed; queued until it loads when it is
---installed but lazy.
---@param plugin string
---@param spec Lib.Keymap.Spec
---@param user table
---@param bound Lib.Keymap.Registered[]
---@return boolean applied
function M.apply(plugin, spec, user, bound)
  -- The user's own `which_key` wins over the plugin's, and `false` opts out.
  local group_spec = spec.which_key
  if user.which_key ~= nil then
    group_spec = user.which_key
  end
  if group_spec == false then
    group_spec = nil
  end

  ---@type table[]
  local entries = {}

  ---@param prefix string|nil
  ---@param g table|true
  local function add_group(prefix, g)
    -- A group spec may carry its own `prefix`. Several plugins have no
    -- top-level `spec.prefix` at all -- their keys do not share one -- and
    -- would otherwise declare a group that silently never appears.
    if type(g) == "table" and g.prefix then
      prefix = g.prefix
    end
    if not prefix then
      return
    end
    entries[#entries + 1] = M.entry(prefix, g, plugin)
  end

  -- One plugin may own several prefixes. fileops labels `<leader>n` and
  -- `<leader>p` separately -- "next file" and "prev file" are two groups, not
  -- one -- so a list is accepted alongside the single-group form. An array
  -- has a [1]; a single group spec does not, so the two cannot be confused.
  if group_spec then
    if type(group_spec) == "table" and group_spec[1] ~= nil then
      for _, g in ipairs(group_spec) do
        add_group(g.prefix, g)
      end
    else
      add_group(spec.prefix, group_spec)
    end
  end

  -- Per-action extras. `desc` is deliberately not repeated here: which-key
  -- already has it from the mapping itself, and sending it twice is how the
  -- two get to disagree later.
  for _, e in ipairs(bound) do
    if e.bound and e.lhs and type(e.which_key) == "table" then
      local entry = { e.lhs }
      if e.which_key.icon and icons_ok() then
        entry.icon = e.which_key.icon
      end
      if e.which_key.group then
        entry.group = e.which_key.group
      end
      entry.mode = e.which_key.mode or e.mode
      if entry.icon or entry.group then
        entries[#entries + 1] = entry
      end
    end
  end

  if #entries == 0 then
    return false
  end

  return send(entries)
end

return M
