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

--- Names already reported as unknown, per plugin.
---
--- Buffer-local presets re-register on every `FileType`, so without this a
--- single typo would warn once per file opened -- twenty markdown buffers,
--- twenty identical messages. The report is about the *config*, which does not
--- change between buffers, so once is the right number.
---@type table<string, table<string, true>>
local warned = {}

--- Plugins whose which-key groups have been handed over already.
---
--- Groups are global and a buffer-local preset registers per buffer, so
--- without this the same label would be sent on every file opened.
---@type table<string, true>
local wk_applied = {}

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
--- Every `lhs` an action should bind, from the user's override or its default.
---
--- Returns an empty list when the action is to be skipped, which is
--- deliberately the same answer for "the user disabled it" and "the plugin
--- declared no default": an action with no key is not an error, it is simply
--- only reachable through the command or the API.
---
--- A list is accepted on both sides. One action on several keys is a real
--- case, not a convenience -- gopath binds `open_here` to `gF` *and* a
--- double-click -- and it stays one action, so moving or dropping it is still
--- said once.
---@param action Lib.Keymap.Action
---@param override string|string[]|table|false|nil
---@return string[]
local function resolve_lhs(action, override)
  local chosen
  if override == false then
    return {}
  elseif type(override) == "string" or type(override) == "table" then
    chosen = override
  else
    chosen = action.default
  end

  if type(chosen) == "string" then
    return chosen ~= "" and { chosen } or {}
  end

  if type(chosen) == "table" then
    -- A table with an `lhs` field is one key plus the plugin's own options
    -- (insights lets a mapping carry its scope and type). A table without one
    -- is a plain list of keys. The two cannot be confused: an array has no
    -- `lhs`, and a spec table has no positional entries.
    if chosen.lhs ~= nil then
      chosen = chosen.lhs
      if type(chosen) == "string" then
        return chosen ~= "" and { chosen } or {}
      end
      if type(chosen) ~= "table" then
        return {}
      end
    end

    local out = {}
    for _, lhs in ipairs(chosen) do
      if type(lhs) == "string" and lhs ~= "" then
        out[#out + 1] = lhs
      end
    end
    return out
  end

  return {}
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
---@param user table|false|nil   # The user's `keymaps` table; `false` binds nothing.
---@param opts Lib.Keymap.RegisterOpts|nil # `buffer` binds buffer-locally; `surface` separates two sets.
---@return Lib.Keymap.Registered[] bound # What was actually bound, in declaration order. A fresh list; the entries in it are the registry's own records — read them, do not mutate them.
function M.register(plugin, spec, user, opts)
  vim.validate("plugin", plugin, "string")
  vim.validate("spec", spec, "table")
  vim.validate("user", user, { "table", "boolean", "nil" })
  vim.validate("opts", opts, { "table", "nil" })
  opts = opts or {}

  local actions = spec.actions or {}

  -- `keymaps = false` for the whole table is the same statement as
  -- `keymaps = { preset = false }`, and several plugins here spell it the
  -- short way. Accepting both means migrating a plugin never silently changes
  -- what its users' existing config means.
  local all_off = user == false
  user = (type(user) == "table") and user or {}

  -- A plugin may own more than one keymap surface. cascade has two: global
  -- keys, and the list keys that only exist inside a matching buffer. They are
  -- different action sets bound at different times, so they get different
  -- registry keys -- while `desc` keeps the plugin's own name, because that is
  -- what a user reads in which-key and does not care to see split up.
  local key = opts.surface and (plugin .. "/" .. opts.surface) or plugin

  -- Reserved keys are not actions; everything else in `user` claims to be one.
  -- Names a `keymaps` block routinely carries that are settings, not actions.
  -- `prefix` is one: several presets here build their defaults from a
  -- user-configurable prefix, and it sits in the same table as the overrides.
  local reserved = { preset = true, which_key = true, enable = true, prefix = true }
  local unknown = {}
  warned[key] = warned[key] or {}
  for k in pairs(user) do
    if not reserved[k] and actions[k] == nil and not warned[key][k] then
      warned[key][k] = true
      local hint = nearest(k, actions)
      unknown[#unknown + 1] = hint and ("%s (did you mean %s?)"):format(k, hint) or k
    end
  end
  if #unknown > 0 then
    notify.warn(("%s: no such keymap action: %s"):format(plugin, table.concat(unknown, ", ")))
  end

  ---@type Lib.Keymap.Registered[]
  local bound = {}
  registered[key] = bound

  -- `preset = false` / `enable = false` mean "bind nothing". The actions are
  -- still recorded, because the health check and the generated docs want to
  -- know what *exists*, not only what is currently bound.
  local binding_enabled = not all_off
    and opts.bind ~= false
    and user.preset ~= false
    and user.enable ~= false

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
      local lhs_list = resolve_lhs(action, user[name])

      -- One action, possibly several bindings. The same key routinely means
      -- the same *intent* in two modes while calling different functions:
      -- spotlight's `toggle_here` marks the occurrence under the cursor in
      -- normal mode and the selection in visual mode. That is one action to a
      -- user -- one name, one key, one override -- so it stays one action
      -- here, with the per-mode differences in `binds`.
      local binds = action.binds
      if not binds then
        binds = { { mode = action.mode, rhs = action.rhs, desc = action.desc, opts = action.opts } }
      end

      -- An action with no key still yields one entry: the docs and the health
      -- check ask what EXISTS, and "declared, reachable only by command" is a
      -- real answer they need to be able to give.
      local keys = #lhs_list > 0 and lhs_list or { nil }

      for _, b in ipairs(binds) do
        local desc_text = b.desc or action.desc
        local desc = desc_text and ("%s: %s"):format(plugin, desc_text) or nil
        local rhs = b.rhs or action.rhs

        for i = 1, math.max(#keys, 1) do
          local lhs = lhs_list[i]

          ---@type Lib.Keymap.Registered
          local entry = {
            plugin = plugin,
            name = name,
            lhs = lhs,
            mode = b.mode or action.mode or "n",
            desc = desc,
            rhs = rhs,
            which_key = action.which_key,
            bound = false,
            -- Recorded so `conflicts()` can tell a buffer-local binding apart
            -- from a global one. A buffer-local preset re-registers per
            -- buffer, so without this every one of them would look like it
            -- collides with the global map of the same key.
            buffer = require("lib.nvim.bindings.keymap.records").resolve_buffer(opts.buffer),
          }

          if lhs and binding_enabled and rhs ~= nil then
            local map_opts = vim.tbl_extend("force", b.opts or action.opts or {}, {})
            -- A buffer-local preset re-registers per buffer; the caller says
            -- which one, since the action itself is the same everywhere.
            if opts.buffer ~= nil then
              map_opts.buffer = opts.buffer
            end
            -- which-key reads plain keymaps and their `desc` on its own, so an
            -- action needs no registration to show up there. `which_key = false`
            -- is the one thing only the plugin can express, and which-key's own
            -- convention for it is this magic description.
            if action.which_key == false then
              map_opts.desc = "which_key_ignore"
            else
              map_opts.desc = desc
            end
            -- `record = false`: the richer entry below goes into the
            -- registry instead, and without this every registered action
            -- would also appear as a direct one.
            map_opts.record = false
            set(entry.mode, lhs, rhs, map_opts)
            entry.bound = true
          end

          bound[#bound + 1] = entry
        end
      end
    end
  end

  -- Groups are global, so they are handed over once per plugin -- not once
  -- per buffer for a buffer-local preset. `bind = false` still applies them:
  -- declaring the preset is exactly when a plugin wants its label up, whether
  -- or not this particular call binds anything.
  if not all_off and user.preset ~= false and user.enable ~= false and not wk_applied[key] then
    wk_applied[key] = true
    require("lib.nvim.bindings.keymap.which_key").apply(plugin, spec, user, bound)
  end

  -- A copy of the list, not the registry's own array: a caller sorting or
  -- trimming its result for display would otherwise reorder what
  -- `:checkhealth`, `conflicts()` and the generated docs read afterwards.
  -- The entries themselves stay shared, exactly as `M.registered` hands
  -- them out.
  return vim.list_extend({}, bound)
end

---Every action registered so far, or just one plugin's.
---
---This is what makes the registry more than a binder: the list is the same one
---`:checkhealth`, a generated bindings page, and a "reachable as a command too?"
---audit all need, and reading it back beats each of them re-deriving it from
---source.
---
---Includes plain `keymap.set(...)` keymaps, which are recorded separately (see
---`keymap.records`) and merged here. They used to be absent entirely, and that
---was most of them: 59 registered actions against 305 real keymaps in the
---author's config. Merged rather than stored together because `register()`
---replaces a plugin's array wholesale and would otherwise wipe them.
---
---Returns a fresh list (or map of lists), for that same reason -- sorting,
---trimming or extending it does not reach either store. The
---`Lib.Keymap.Registered` entries inside are the live records shared with
---the registry and with `keymap.records`: read them, do not mutate them, or
---`:checkhealth`, `conflicts()` and the generated docs see the change.
---The two shapes are declared as an overload rather than one union return:
---with a union, `pairs(registered())` sees a `Registered[]` branch it cannot
---rule out, and every field read off an entry becomes an `undefined-field`.
---@param plugin string
---@return Lib.Keymap.Registered[]
---@overload fun(): table<string, Lib.Keymap.Registered[]>
function M.registered(plugin)
  local direct = require("lib.nvim.bindings.keymap.records").all()

  if plugin then
    local out = {}
    for _, e in ipairs(registered[plugin] or {}) do
      out[#out + 1] = e
    end
    for _, e in ipairs(direct[plugin] or {}) do
      out[#out + 1] = e
    end
    return out
  end

  local out = {}
  for key, entries in pairs(registered) do
    out[key] = {}
    for _, e in ipairs(entries) do
      out[key][#out[key] + 1] = e
    end
  end
  for key, entries in pairs(direct) do
    out[key] = out[key] or {}
    for _, e in ipairs(entries) do
      out[key][#out[key] + 1] = e
    end
  end
  return out
end

---Forget a plugin's direct `set()` records, or all of them.
---
---For a re-`setup()` that rebinds the same keys: `register()` replaces its own
---array on every call, but direct records would otherwise accumulate and
---describe each keymap as many times as setup has run.
---@param plugin string|nil
---@return integer removed
function M.forget(plugin)
  return require("lib.nvim.bindings.keymap.records").forget(plugin)
end

---Actions whose `lhs` is claimed by more than one registered plugin.
---
---Not called during registration: a plugin cannot know what a later one will
---bind, so the answer is only meaningful once everything has loaded. Meant for
---`:checkhealth` and for the config's own drift report.
---
---Two scopes:
---
--- - `"registered"` (default): only what went through lib.nvim's `register` /
---   `set`. Unchanged behaviour.
--- - `"full"`: that, plus every collision the keymap `tap` recorded -- raw
---   `vim.keymap.set` / `nvim_set_keymap` calls and lazy.nvim `keys` included,
---   overwritten mappings too. Without an installed tap this has nothing but
---   the registry to go on, and says so in the second result (`notes`):
---   `nvim_get_keymap()` only shows the winner of a key, so an overwritten
---   mapping cannot be found after the fact. lazy.nvim's placeholder for a
---   `keys` entry is flagged `benign = "lazy-stub"` and left out unless
---   `opts.benign` is set (the count is in `info.benign_hidden`).
---
---The first result is the same list shape as ever; the second describes how
---the answer was reached.
---@param opts? Lib.Keymap.ConflictsOpts
---@return Lib.Keymap.Conflict[]
---@return Lib.Keymap.ConflictsInfo
function M.conflicts(opts)
  opts = opts or {}
  local which = opts.scope or "registered"
  ---@type Lib.Keymap.ConflictsInfo
  local info = { scope = which, notes = {}, benign_hidden = 0 }
  ---@type table<string, Lib.Keymap.Registered[]>
  local by_lhs = {}
  -- Mode and lhs of each bucket, kept as they were bound: parsing them back out of the bucket key
  -- loses the empty mode (`""`, the `:map` family), which is a perfectly valid one.
  ---@type table<string, { mode: string, lhs: string }>
  local meta = {}
  -- Over `M.registered()`, not the raw table: a collision between two plain
  -- `set()` keymaps was previously invisible here *in principle*, and those
  -- are the majority.
  for _, entries in pairs(M.registered()) do
    for _, e in ipairs(entries) do
      if e.bound and e.lhs then
        local modes = type(e.mode) == "table" and e.mode or { e.mode }
        -- Buffer scope is part of the identity. A buffer-local `p` and a
        -- global `p` do not collide -- the local one shadows the global one
        -- inside its buffer and that is the point of it. Bucketing them
        -- together would report every buffer-local preset as a conflict, and
        -- a report that cries wolf is one nobody reads.
        local scope = e.buffer == nil and "*" or tostring(e.buffer)
        for _, mode in
          ipairs(modes --[[@as string[] ]])
        do
          local key = mode .. " " .. scope .. " " .. e.lhs
          by_lhs[key] = by_lhs[key] or {}
          meta[key] = meta[key] or { mode = mode, lhs = e.lhs }
          table.insert(by_lhs[key], e)
        end
      end
    end
  end

  ---@type Lib.Keymap.Conflict[]
  local out = {}
  for key, entries in pairs(by_lhs) do
    if #entries > 1 then
      out[#out + 1] = { mode = meta[key].mode, lhs = meta[key].lhs, claimants = entries }
    end
  end
  table.sort(out, function(a, b)
    return (a.lhs .. a.mode) < (b.lhs .. b.mode)
  end)

  if which == "full" then
    local tap = require("lib.nvim.bindings.keymap.tap")
    local lhs_mod = require("lib.nvim.bindings.keymap.lhs")
    info.tap_installed = tap.is_installed()
    if not info.tap_installed then
      if #tap.log() > 0 then
        info.notes[#info.notes + 1] =
          "the keymap tap is stopped: collisions up to that point are included, later ones are not seen."
      else
        info.notes[#info.notes + 1] = "the keymap tap was not installed: only what lib.nvim bound and "
          .. "the live state are known, and a mapping that was overwritten is invisible. Install it "
          .. "before the plugins load: nvim --cmd \"lua require('lib.nvim.bindings.keymap.tap').install()\""
      end
    end
    if tap.truncated() then
      info.notes[#info.notes + 1] = (
        "the keymap tap stopped recording at %d events (tap.max_events): bindings after that "
        .. "point are not in the answer, so a clean result proves nothing."
      ):format(#tap.log())
    end

    -- A collision the registry already reports is not listed twice; the
    -- registry's entry names the plugin and action, which is the richer one.
    -- The registry keeps the modes as bound (`""` stands for n/x/s/o, `"v"` for
    -- x/s) while the tap records real ones, so a row is known under each real
    -- mode it stands for.
    ---@type table<string, { index: integer, same_mode: boolean }>
    local known = {}
    for i, c in ipairs(out) do
      local buffer = c.claimants[1] and c.claimants[1].buffer
      for _, m in ipairs(lhs_mod.modes(c.mode)) do
        known[table.concat({ m, lhs_mod.scope(buffer), lhs_mod.normalize(c.lhs) }, "\0")] = {
          index = i,
          same_mode = m == c.mode,
        }
      end
    end
    for _, c in ipairs(tap.collisions()) do
      local buffer = c.claimants[1] and c.claimants[1].buffer
      local key = table.concat({ c.mode, lhs_mod.scope(buffer), c.lhs }, "\0")
      local seen = known[key]
      if c.benign and not opts.benign then
        info.benign_hidden = info.benign_hidden + 1
      elseif not seen then
        out[#out + 1] = c
      elseif seen.same_mode and #c.claimants > #out[seen.index].claimants then
        -- The tap saw a later binding the registry did not (a raw `vim.keymap.set`
        -- over two lib.nvim ones): that row has the winner, so it replaces the
        -- registry's.
        out[seen.index] = c
      end
    end
    table.sort(out, function(a, b)
      return (a.lhs .. a.mode) < (b.lhs .. b.mode)
    end)
  end
  return out, info
end

return M
