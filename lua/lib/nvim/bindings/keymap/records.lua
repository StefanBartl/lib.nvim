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

---Record one keymap created by a plain `set()`.
---
---Called from the `set` wrapper. `registry.register()` passes `record = false`
---through to it, because it writes its own richer entry -- without that, every
---registered action would be listed twice.
---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts Lib.Map.Opts
---@return nil
function M.add(modes, lhs, rhs, opts)
  local src = caller_site()
  local plugin = plugin_of(src)
  direct[plugin] = direct[plugin] or {}
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
    buffer = opts.buffer,
    src = src,
  })
end

---Everything `set()` recorded, keyed by plugin.
---@return table<string, Lib.Keymap.Registered[]>
function M.all()
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
