---@module 'lib.nvim.bindings.keymap'
--- Keymaps: the one-off wrapper, and the named-action registry.
---@description
--- Two levels, and most plugins want both:
---
--- **`keymap(...)`** -- the validated `vim.keymap.set` wrapper this module has
--- always been. For the mappings that are not part of a plugin's public
--- surface: buffer-local keys inside a floating window, `q` to close a report,
--- anything a user has no reason to rebind.
---
--- ```lua
--- local keymap = require("lib.nvim.bindings.keymap")
--- keymap("n", "q", close, { buffer = true }, "close")
--- ```
---
--- **`keymap.register(...)`** -- named actions the user's spec can remap or
--- switch off, one by one. For everything that *is* public surface. See
--- `registry.lua` for the shape and for why the override table is keyed by
--- action name rather than by the current `lhs`.
---
--- ```lua
--- keymap.register("spotlight", {
---   prefix = "<leader>s",
---   which_key = { group = "Spotlight" },
---   actions = {
---     toggle = { default = "<leader>sK", rhs = api.toggle, desc = "toggle every occurrence" },
---   },
--- }, cfg.keymaps)
--- ```
---
--- The module stays **callable** so that the first form keeps working
--- unchanged: it is `require`d in over a hundred places across these plugins,
--- and turning it into a plain table would have broken every one of them for
--- no benefit.
---@see lib.nvim.bindings.keymap.registry
---@see lib.nvim.bindings.keymap.which_key

local set = require("lib.nvim.bindings.keymap.set")

local M = {}

--- Set one keymap. Identical to calling the module itself.
---@type fun(modes: string|string[], lhs: string, rhs: string|function, opts: Lib.Map.Opts|nil, desc: string?): nil
M.set = set

--- Register a plugin's named actions. See `registry.register`.
---@param plugin string
---@param spec Lib.Keymap.Spec
---@param user table|false|nil
---@param opts Lib.Keymap.RegisterOpts|nil
---@return Lib.Keymap.Registered[]
function M.register(plugin, spec, user, opts)
  return require("lib.nvim.bindings.keymap.registry").register(plugin, spec, user, opts)
end

--- Everything registered so far. See `registry.registered`.
---The two shapes are declared as an overload rather than one union return:
---with a union, `pairs(registered())` sees a `Registered[]` branch it cannot
---rule out, and every field read off an entry becomes an `undefined-field`.
---@param plugin string
---@return Lib.Keymap.Registered[]
---@overload fun(): table<string, Lib.Keymap.Registered[]>
function M.registered(plugin)
  return require("lib.nvim.bindings.keymap.registry").registered(plugin)
end

--- Forget direct `set()` records. See `registry.forget`.
---@param plugin string|nil
---@return integer
function M.forget(plugin)
  return require("lib.nvim.bindings.keymap.registry").forget(plugin)
end

--- `lhs` values claimed by more than one plugin. See `registry.conflicts`.
---@return Lib.Keymap.Conflict[]
function M.conflicts()
  return require("lib.nvim.bindings.keymap.registry").conflicts()
end

---@internal
--- How many of lazy.nvim's tracked plugins are loaded right now, or `nil`
--- when lazy.nvim is not present or everything is already loaded.
--- `conflicts()` only sees registrations that already ran -- a plugin
--- lazy.nvim has not loaded yet cannot have bound anything, so a clean
--- report this early is not evidence of anything.
---@return string|nil
local function lazy_coverage_note()
  local ok, lazy_config = pcall(require, "lazy.core.config")
  if not ok then
    return nil
  end
  local total, loaded = 0, 0
  for _, spec in pairs(lazy_config.plugins) do
    total = total + 1
    if spec._ ~= nil and spec._.loaded ~= nil then
      loaded = loaded + 1
    end
  end
  if loaded >= total then
    return nil
  end
  return ("note: %d/%d lazy-loaded plugins loaded right now -- the rest have bound nothing yet."):format(
    loaded,
    total
  )
end

---`conflicts()` as printable lines, for `:checkhealth` and a report command.
---@return string[]
function M.conflict_lines()
  local conflicts = M.conflicts()
  local out = {}
  local coverage = lazy_coverage_note()
  if coverage then
    out[#out + 1] = coverage
    out[#out + 1] = ""
  end
  if #conflicts == 0 then
    out[#out + 1] = "no keymap conflicts -- every lhs is claimed once per mode+scope."
    return out
  end
  out[#out + 1] = ("%d lhs claimed by more than one registration:"):format(#conflicts)
  for _, c in ipairs(conflicts) do
    out[#out + 1] = ("  %-4s %s"):format(c.mode, c.lhs)
    for _, cl in ipairs(c.claimants) do
      local who = cl.direct and (cl.src or (cl.plugin .. " (direct)"))
        or (cl.plugin .. "." .. cl.name)
      out[#out + 1] = ("       %s%s"):format(who, cl.desc and (" -- " .. cl.desc) or "")
    end
  end
  return out
end

---Expose `:<name>` for `conflicts()`. Put this call in **your own config**,
---not in a library -- same reasoning `bindings.usercmd.docs.create_usercmd`
---and `bindings.audit.create_usercmd` give.
---@param name string|nil  # Default `LibKeymapConflicts`.
---@return nil
function M.create_usercmd(name)
  local base = name or "LibKeymapConflicts"
  local usercmd = require("lib.nvim.bindings.usercmd")

  usercmd.create(base, function()
    local lines = M.conflict_lines()
    local ok, kit = pcall(require, "lib.nvim.ui.kit")
    if ok then
      kit.viewer({
        lines = lines,
        title = " " .. base .. " ",
        width = math.min(120, vim.o.columns - 8),
      })
      return
    end
    print(table.concat(lines, "\n"))
  end, { desc = "lhs values claimed by more than one plugin/registration in this session" })
end

---@type Lib.Keymap
return setmetatable(M, {
  __call = function(_, modes, lhs, rhs, opts, desc)
    return set(modes, lhs, rhs, opts, desc)
  end,
})
