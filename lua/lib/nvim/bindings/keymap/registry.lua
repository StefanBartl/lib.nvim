---@module 'lib.nvim.bindings.keymap.registry'
--- Named keymap actions, overridable from a plugin's own setup spec.
---@description
--- **The problem.** A plugin that hard-codes `lhs` strings gives a user two
--- options: accept them, or fork. The usual escape hatch is one config key per
--- mapping plus a hand-written `bind()` helper that skips `false` and honours a
--- `preset` switch -- which is why that helper had been copy-pasted, with small
--- differences, into a dozen plugins here before this module existed.
---
--- **The shape.** A plugin declares *actions* by name and hands over whatever
--- the user's spec said. The name is the stable identity; the `lhs` is just its
--- current default:
---
--- ```lua
--- keymap.register("spotlight", {
---   actions = {
---     toggle_here = { default = "<leader>sk", mode = { "n", "x" },
---                     rhs = api.toggle_here, desc = "toggle this occurrence only" },
---     next        = { default = "]k", rhs = api.next, desc = "next spotlight" },
---   },
--- }, cfg.keymaps)
--- ```
---
--- and the user writes, in that plugin's spec:
---
--- ```lua
--- keymaps = {
---   toggle_here = "<leader>x",   -- remap
---   next        = false,         -- drop just this one
---   preset      = false,         -- or: bind nothing at all
--- }
--- ```
---
--- **Why names and not `lhs` keys.** Keying the override table by the current
--- default -- `{ ["]k"] = "<leader>n" }` -- reads more directly, and was the
--- first idea. It breaks in three ways a name does not:
---
---  1. It cannot say "disable": the key already *is* the value's counterpart,
---     so `false` has nowhere to attach that does not also mean "remap to
---     nothing".
---  2. It breaks **silently** when the plugin changes a default. The user's
---     `["]k"]` then matches no action: no error, no mapping, no clue.
---  3. It cannot say *which* plugin is meant. Two plugins defaulting to the
---     same `lhs` are indistinguishable in a table keyed by `lhs`.
---
--- A name has none of those failure modes, and a wrong one is *detectable*:
--- see `M.register`'s unknown-key report.
---
--- **What this does not do.** It does not introduce a `<Plug>` layer. `<Plug>`
--- exists so a user can remap an action without the plugin offering a config
--- key -- which is the very thing this module offers. Mappings bind straight
--- onto the action's `rhs`.
---@see lib.nvim.bindings.keymap.which_key

local set = require("lib.nvim.bindings.keymap.set")
local notify = require("lib.nvim.notify").create("[lib.nvim.bindings.keymap]")

local M = {}

--- Everything registered so far, keyed by plugin name.
---
--- Kept so the surface can be *read back*: `:checkhealth`, generated binding
--- docs, and "is every action also reachable as a user command?" all need the
--- list, and each of them reconstructing it from source would drift.
---@type table<string, Lib.Keymap.Registered[]>
local registered = {}

---@internal
--- Levenshtein distance, capped -- only ever run over the action names of one
--- plugin (a handful of short strings) when a spec key did not match.
---@param a string
---@param b string
---@return integer
local function distance(a, b)
  local prev = {}
  for j = 0, #b do
    prev[j] = j
  end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

---@internal
--- The closest action name to `key`, if one is close enough to be worth
--- suggesting. "Close enough" scales with the name's length so that `nexr` ->
--- `next` is offered while `zzz` -> `next` is not.
---@param key string
---@param actions table<string, Lib.Keymap.Action>
---@return string|nil
local function nearest(key, actions)
  local best, best_d = nil, math.huge
  for name in pairs(actions) do
    local d = distance(key, name)
    if d < best_d then
      best, best_d = name, d
    end
  end
  if best and best_d <= math.max(2, math.floor(#best / 3)) then
    return best
  end
  return nil
end

---@internal
--- Resolve one action's `lhs` from the user's override table.
---
--- Returns `nil` when the action is to be skipped, which is deliberately the
--- same answer for "the user disabled it" and "the plugin declared no default":
--- an action with no key is not an error, it is simply only reachable through
--- the command or the API.
---@param action Lib.Keymap.Action
---@param override string|false|nil
---@return string|nil
local function resolve_lhs(action, override)
  if override == false then
    return nil
  end
  if type(override) == "string" and override ~= "" then
    return override
  end
  local default = action.default
  if type(default) == "string" and default ~= "" then
    return default
  end
  return nil
end

---Register a plugin's named keymap actions and bind the ones that survive the
---user's overrides.
---
---`user` is the plugin's own `keymaps`/`mappings` config table, passed through
---untouched. Two keys in it are reserved and are never treated as action
---names: `preset = false` binds nothing at all, and `which_key` carries the
---prefix-level which-key spec (see `lib.nvim.bindings.keymap.which_key`).
---
---Unknown keys are reported rather than ignored. A typo in a keymap override
---is otherwise completely silent -- the mapping simply never appears, and
---nothing says why -- which is the single most common way this kind of config
---wastes somebody's afternoon.
---@param plugin string          # Plugin name, used in messages and as the registry key.
---@param spec Lib.Keymap.Spec
---@param user table|nil         # The user's `keymaps` table, or nil for defaults.
---@return Lib.Keymap.Registered[] bound # What was actually bound, in declaration order.
function M.register(plugin, spec, user)
  vim.validate("plugin", plugin, "string")
  vim.validate("spec", spec, "table")
  vim.validate("user", user, { "table", "nil" })

  local actions = spec.actions or {}
  user = user or {}

  -- Reserved keys are not actions; everything else in `user` claims to be one.
  local reserved = { preset = true, which_key = true, enable = true }
  local unknown = {}
  for key in pairs(user) do
    if not reserved[key] and actions[key] == nil then
      local hint = nearest(key, actions)
      unknown[#unknown + 1] = hint and ("%s (did you mean %s?)"):format(key, hint) or key
    end
  end
  if #unknown > 0 then
    notify.warn(("%s: no such keymap action: %s"):format(plugin, table.concat(unknown, ", ")))
  end

  ---@type Lib.Keymap.Registered[]
  local bound = {}
  registered[plugin] = bound

  -- `preset = false` / `enable = false` mean "bind nothing". The actions are
  -- still recorded, because the health check and the generated docs want to
  -- know what *exists*, not only what is currently bound.
  local binding_enabled = user.preset ~= false and user.enable ~= false

  -- Declaration order, not `pairs` order: the docs and the health report read
  -- top to bottom and should not reshuffle between runs.
  local names = spec.order
  if not names then
    names = {}
    for name in pairs(actions) do
      names[#names + 1] = name
    end
    table.sort(names)
  end

  for _, name in ipairs(names) do
    local action = actions[name]
    if action then
      local lhs = resolve_lhs(action, user[name])
      local desc = action.desc and ("%s: %s"):format(plugin, action.desc) or nil

      ---@type Lib.Keymap.Registered
      local entry = {
        plugin = plugin,
        name = name,
        lhs = lhs,
        mode = action.mode or "n",
        desc = desc,
        rhs = action.rhs,
        which_key = action.which_key,
        bound = false,
      }

      if lhs and binding_enabled and action.rhs ~= nil then
        local opts = vim.tbl_extend("force", action.opts or {}, {})
        -- which-key reads plain keymaps and their `desc` on its own, so an
        -- action needs no registration to show up there. `which_key = false`
        -- is the one thing only the plugin can express, and which-key's own
        -- convention for it is this magic description.
        if action.which_key == false then
          opts.desc = "which_key_ignore"
        else
          opts.desc = desc
        end
        set(entry.mode, lhs, action.rhs, opts)
        entry.bound = true
      end

      bound[#bound + 1] = entry
    end
  end

  if binding_enabled then
    require("lib.nvim.bindings.keymap.which_key").apply(plugin, spec, user, bound)
  end

  return bound
end

---Every action registered so far, or just one plugin's.
---
---This is what makes the registry more than a binder: the list is the same one
---`:checkhealth`, a generated bindings page, and a "reachable as a command too?"
---audit all need, and reading it back beats each of them re-deriving it from
---source.
---@param plugin string|nil
---@return table<string, Lib.Keymap.Registered[]>|Lib.Keymap.Registered[]
function M.registered(plugin)
  if plugin then
    return registered[plugin] or {}
  end
  return registered
end

---Actions whose `lhs` is claimed by more than one registered plugin.
---
---Not called during registration: a plugin cannot know what a later one will
---bind, so the answer is only meaningful once everything has loaded. Meant for
---`:checkhealth` and for the config's own drift report.
---@return Lib.Keymap.Conflict[]
function M.conflicts()
  ---@type table<string, Lib.Keymap.Registered[]>
  local by_lhs = {}
  for _, entries in pairs(registered) do
    for _, e in ipairs(entries) do
      if e.bound and e.lhs then
        local modes = type(e.mode) == "table" and e.mode or { e.mode }
        for _, mode in
          ipairs(modes --[[@as string[] ]])
        do
          local key = mode .. " " .. e.lhs
          by_lhs[key] = by_lhs[key] or {}
          table.insert(by_lhs[key], e)
        end
      end
    end
  end

  ---@type Lib.Keymap.Conflict[]
  local out = {}
  for key, entries in pairs(by_lhs) do
    if #entries > 1 then
      local mode, lhs = key:match("^(%S+) (.*)$")
      out[#out + 1] = { mode = mode, lhs = lhs, claimants = entries }
    end
  end
  table.sort(out, function(a, b)
    return (a.lhs .. a.mode) < (b.lhs .. b.mode)
  end)
  return out
end

return M
