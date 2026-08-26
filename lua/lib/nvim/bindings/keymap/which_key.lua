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

---@internal
--- Is it safe to send icons? Declared by the user, not detected -- see
--- `lib.nvim.ui.nerd_font` for why detection is impossible.
---@return boolean
local function icons_ok()
  return require("lib.nvim.ui.nerd_font").available()
end

---@internal
---@return table|nil
local function wk()
  local ok, mod = pcall(require, "which-key")
  if not ok or type(mod) ~= "table" or type(mod.add) ~= "function" then
    return nil
  end
  return mod
end

---Register what which-key cannot infer: the prefix group label, and any
---per-action icons.
---
---Called by `registry.register` after the mappings are set. Silent and
---harmless when which-key is not installed.
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

  local prefix = spec.prefix
  if group_spec and prefix then
    local group = type(group_spec) == "table" and group_spec.group or plugin
    local entry = { prefix, group = group }
    if type(group_spec) == "table" and group_spec.icon and icons_ok() then
      entry.icon = group_spec.icon
    end
    if type(group_spec) == "table" and group_spec.mode then
      entry.mode = group_spec.mode
    end
    entries[#entries + 1] = entry
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

  local mod = wk()
  if not mod then
    return false
  end

  -- pcall: which-key's spec format has changed between majors, and a label
  -- being wrong is never worth taking a plugin's setup down with it.
  local ok = pcall(mod.add, entries)
  return ok
end

return M
