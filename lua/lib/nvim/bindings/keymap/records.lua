---@module 'lib.nvim.bindings.keymap.records'
--- What plain `keymap.set(...)` calls left behind.
---@description
--- `registry.register()` records the actions it binds, and that is what
--- `registered()`/`conflicts()` and every generated bindings page read. A plain
--- `keymap.set(...)` recorded nothing at all — and that is the call almost
--- everybody actually makes.
---
--- The gap was not small. In the author's config: 59 registry entries against
--- **305** real keymaps. A page generated from the registry would have been
--- over eighty percent blind, and `conflicts()` could not see a collision
--- between two `set()` keymaps *even in principle* — which is most of them.
---
--- So `set()` records too. Two things follow from that, and both are why this
--- lives in its own module rather than inside `registry`:
---
--- * **No require cycle.** `registry` requires `set`; if `set` required
---   `registry` back, loading either would fail.
--- * **No clobbering.** `register()` assigns `registered[plugin]` wholesale, so
---   direct entries kept in that same table would be wiped the moment the same
---   plugin also called `register()`. They are merged on read instead.
---
--- The bucket a direct keymap lands in is derived from its **call site** — the
--- directory holding the `lua/` it sits under — so `filetree.nvim`'s direct
--- calls group under `filetree.nvim` without anyone passing a name. That is
--- also the half of the answer a reader actually wants: not only "something
--- maps `<leader>q`" but which file to open.

local M = {}

--- Direct `set()` keymaps, keyed by the plugin their call site belongs to.
---@type table<string, Lib.Keymap.Registered[]>
local direct = {}

---@internal
--- Where the `keymap.set` call came from, as `file:line`.
---
--- Stack layout: getinfo -> this -> M.add -> the `set` wrapper -> the caller.
--- One frame deeper than the equivalent in `lib.nvim.bindings.autocmd`, because
--- there the recording happens in the wrapper itself rather than one call down.
---@return string
local function caller_site()
  local info = debug.getinfo(4, "Sl")
  if not info then
    return "?"
  end
  local src = (info.source or "?"):gsub("^@", "")
  return ("%s:%d"):format(src, info.currentline or -1)
end

---@internal
--- The plugin a source path belongs to: the first directory under `lua/`.
---
--- Derived from the path rather than from `cwd`, for the reason
--- `lib.nvim.bindings.autocmd.docs` spells out: the answer has to be right when
--- the call comes from a plugin while the editor sits in an unrelated project.
---@param src string
---@return string
local function plugin_of(src)
  local plugin = (src or ""):gsub("\\", "/"):match("/lua/([^/]+)/")
  return plugin or "(unknown)"
end

---@internal
--- Canonical string for a `mode`, comparable even when it is a table (order
--- should not matter for "is this the same registration").
---@param modes string|string[]
---@return string
local function mode_key(modes)
  if type(modes) == "table" then
    local sorted = vim.deepcopy(modes)
    table.sort(sorted)
    return table.concat(sorted, ",")
  end
  return modes
end

---`buffer = true`/`0` mean "the buffer that is current right now"; recorded as such they would read as
---"some buffer" forever. Resolved to the real number at the moment of binding, so a record can be compared
---with `==` against the buffer a reader asks about.
---@param buffer integer|boolean|nil
---@return integer|boolean|nil
function M.resolve_buffer(buffer)
  if buffer == true or buffer == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return buffer
end

---Whether the keymap a record describes can no longer exist: its buffer was wiped (buffer numbers are never
---reused), or it was only unloaded (`:bdelete`, `:bunload`, `bufhidden=delete`), which discards the
---buffer-local maps while the buffer number stays valid. An unloaded buffer that still has a map in the
---record's mode is kept: this errs on the side of keeping a record.
---@param entry table
---@return boolean
local function is_dead(entry)
  local b = entry.buffer
  if type(b) ~= "number" or b <= 0 then
    return false
  end
  if not vim.api.nvim_buf_is_valid(b) then
    return true
  end
  if vim.api.nvim_buf_is_loaded(b) then
    return false
  end
  local modes = type(entry.mode) == "table" and entry.mode or { entry.mode }
  for _, m in ipairs(modes) do
    if #vim.api.nvim_buf_get_keymap(b, m) > 0 then
      return false
    end
  end
  return true
end

---Drop the records of buffer-local keymaps that are gone with their buffer. A UI buffer that is recreated on
---every open (a picker, a float) gets a fresh buffer number each time and binds its keys again from the same
---call site, so without this the list grew by one entry per open and `registered()` described keymaps of
---buffers nobody can reach any more. A plugin bucket left empty is removed too.
---@return integer removed
local function prune_dead_buffers()
  local removed = 0
  for plugin, entries in pairs(direct) do
    for i = #entries, 1, -1 do
      if is_dead(entries[i]) then
        table.remove(entries, i)
        removed = removed + 1
      end
    end
    if #entries == 0 then
      direct[plugin] = nil
    end
  end
  return removed
end

---Record one keymap created by a plain `set()`.
---
---Called from the `set` wrapper. `registry.register()` passes `record = false`
---through to it, because it writes its own richer entry -- without that, every
---registered action would be listed twice.
---
---Replaces a same-site record instead of accumulating one: the same call
---site firing twice for the same buffer+lhs+mode is one keymap set twice,
---not two keymaps. A `FileType` autocmd firing again for an already-typed
---buffer is the common real case -- Neovim re-fires it even when the value
---does not change -- and left unchecked it grew the direct list on every
---re-fire, with `conflicts()` then reporting a same-site "conflict" against
---itself.
---
---`src` is part of the match on purpose, not just buffer+lhs+mode: two
---*different* call sites binding the same key is exactly the collision
---`conflicts()` exists to report (`keymap_registry_spec.lua`'s "a collision
---between two plain set() keymaps is reported" -- caught this once already,
---as a real regression: the first cut of this fix matched on
---buffer+lhs+mode alone and silently swallowed that case whenever both
---calls happened to land in the same `plugin` bucket). Only a *repeat* call
---from the identical source line is the idempotent-re-registration case
---this function exists to collapse.
---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts Lib.Map.Opts
---@return nil
function M.add(modes, lhs, rhs, opts)
  local src = caller_site()
  local plugin = plugin_of(src)
  prune_dead_buffers()
  direct[plugin] = direct[plugin] or {}

  local key_mode, key_buffer = mode_key(modes), M.resolve_buffer(opts.buffer)
  for i, existing in ipairs(direct[plugin]) do
    if
      existing.lhs == lhs
      and mode_key(existing.mode) == key_mode
      and existing.buffer == key_buffer
      and existing.src == src
    then
      table.remove(direct[plugin], i)
      break
    end
  end

  table.insert(direct[plugin], {
    plugin = plugin,
    -- A direct `set()` has no action name -- that concept belongs to
    -- `register()`. The `lhs` is the only identity it has, and putting it here
    -- keeps one shape for both kinds of entry rather than a nullable field
    -- every reader has to branch on.
    name = lhs,
    lhs = lhs,
    mode = modes,
    desc = (opts.desc ~= nil and opts.desc ~= "") and opts.desc or nil,
    rhs = rhs,
    bound = true,
    direct = true,
    buffer = key_buffer,
    src = src,
  })
end

---Everything `set()` recorded, keyed by plugin.
---@return table<string, Lib.Keymap.Registered[]>
function M.all()
  prune_dead_buffers()
  return direct
end

---Drop every direct record for `plugin`, or all of them.
---
---For a re-`setup()` that rebinds the same keys: without it the list grows on
---every call and describes each keymap as many times as setup has run -- the
---same drift the registry exists to prevent, arriving by a different door.
---@param plugin string|nil
---@return integer removed
function M.forget(plugin)
  if plugin then
    local n = #(direct[plugin] or {})
    direct[plugin] = nil
    return n
  end
  local n = 0
  for _, entries in pairs(direct) do
    n = n + #entries
  end
  direct = {}
  return n
end

return M
