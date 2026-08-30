---@module 'lib.nvim.bindings.audit'
--- Keymap actions vs. command routes, for whatever is registered in the
--- current session.
---@description
--- `bindings.usercmd.docs` and `bindings.autocmd.docs` answer "what got
--- written to disk". This answers a different question: does every
--- user-facing keymap action have a discoverable `:command` counterpart, or
--- vice versa — the thing you can only see by holding both registries next
--- to each other.
---
--- Promoted from a throwaway pair of scripts in nvim-config
--- (`docs/ROADMAP/tools/keymap_command_audit.lua` +
--- `keymap_command_gaps.py`) that had to load a plugin fresh in an isolated
--- `nvim --clean -l` session just to see its registry. A real command does
--- not need that: it reads whatever is already loaded in the *current*
--- session, which is simpler and always current.
---
--- **Scope.** Every function here takes an optional `root` — a directory
--- path, same convention `bindings.usercmd.docs` uses for its own `opts.root`
--- (see `docs_util.repo_of`). `nil` means "everything registered, no
--- filtering", not "the caller's own repo" — unlike `usercmd.docs`, there is
--- no call-site to infer one from when this runs from an interactive
--- `:LibBindingsAudit` rather than a library call. Pass a path, or nothing
--- for the whole session.

local util = require("lib.nvim.bindings.docs_util")

local M = {}

---@internal
--- Tier order, worst last. Mirrors `keymap.portability`'s own ranking.
local RANK = { portable = 1, common = 2, fragile = 3 }

---@class Lib.Bindings.Audit.KeyAction
---@field surface string
---@field name string
---@field lhs string|nil
---@field bound boolean
---@field desc string|nil

---@class Lib.Bindings.Audit.CmdRoute
---@field name string
---@field path string
---@field desc string

---@class Lib.Bindings.Audit.KeyTier
---@field lhs string
---@field tier Lib.Keymap.Portability.Tier
---@field reason string

---@class Lib.Bindings.Audit.KeyRisk
---@field surface string
---@field name string
---@field keys Lib.Bindings.Audit.KeyTier[]  # every lhs the action binds, classified
---@field best Lib.Keymap.Portability.Tier   # the most reliable one it has
---@field desc string|nil

---@internal
--- The plugin name a root resolves to: the single subdirectory under its
--- `lua/`, when there is exactly one — same fallback
--- `bindings.usercmd.docs`'s `defaults()` uses when it cannot derive a name
--- from a caller's file. Ambiguous (0 or >1 candidates) returns `nil`, which
--- callers treat as "do not filter by plugin name".
---@param root string
---@return string|nil
local function plugin_of(root)
  local dirs = {}
  for _, e in ipairs(vim.fn.readdir(root .. "/lua") or {}) do
    if vim.fn.isdirectory(root .. "/lua/" .. e) == 1 then
      dirs[#dirs + 1] = e
    end
  end
  return #dirs == 1 and dirs[1] or nil
end

---Every keymap action currently registered, deduplicated by `surface.name`.
---@param root string|nil  scope to one repo's registered plugin name
---@return Lib.Bindings.Audit.KeyAction[]
function M.keymap_actions(root)
  local keymap = require("lib.nvim.bindings.keymap")
  local plugin = root and plugin_of(root) or nil
  local buckets = plugin and { [plugin] = keymap.registered(plugin) } or keymap.registered()

  local seen, actions = {}, {}
  for surface, entries in pairs(buckets) do
    for _, e in ipairs(entries) do
      local id = surface .. "." .. e.name
      if not seen[id] then
        seen[id] = true
        actions[#actions + 1] =
          { surface = surface, name = e.name, lhs = e.lhs, bound = e.bound, desc = e.desc }
      end
    end
  end
  table.sort(actions, function(a, b)
    if a.surface ~= b.surface then
      return a.surface < b.surface
    end
    return a.name < b.name
  end)
  return actions
end

---Every command route currently registered — composer verbs expanded to
---their subcommand paths, plain `usercmd.create()` calls as `(plain)`.
---
---Composer verbs are never filtered by `root`: a `Handle` carries no source
---location to filter on (only plain `usercmd.create()` records do, via
---`src`), and in practice a session holds few verbs, each named after the
---plugin that owns it, so eyeballing which belong to `root` is not the
---burden the plain-command list would be.
---@param root string|nil  scope the *plain* half of the list to sources under this directory
---@return Lib.Bindings.Audit.CmdRoute[]
function M.command_routes(root)
  local usercmd = require("lib.nvim.bindings.usercmd")
  local composer = require("lib.nvim.bindings.usercmd.composer")

  local composer_names, routes = {}, {}
  for name, handle in pairs(composer.registry()) do
    composer_names[name] = true
    local ok_spec, spec = pcall(function()
      return handle:spec()
    end)
    if ok_spec and type(spec) == "table" then
      if spec.default then
        routes[#routes + 1] = { name = name, path = "(bare)", desc = spec.desc or "" }
      end
      for _, r in ipairs(spec.routes or {}) do
        local path = table.concat(r.path or {}, " ")
        routes[#routes + 1] =
          { name = name, path = path ~= "" and path or "(root)", desc = r.desc or "" }
      end
    else
      routes[#routes + 1] = { name = name, path = "?", desc = "(spec not readable)" }
    end
  end

  -- `registered()`'s own `filter` param takes a `{name?, buffer?}` table, not
  -- a predicate -- `root` scoping happens client-side here, same as
  -- `bindings.usercmd.docs.build()` does for its own `opts.filter`.
  for _, r in ipairs(usercmd.registered()) do
    if not composer_names[r.name] and (not root or util.is_under(r.src, root)) then
      routes[#routes + 1] = { name = r.name, path = "(plain)", desc = r.desc or "" }
    end
  end

  table.sort(routes, function(a, b)
    return a.name < b.name
  end)
  return routes
end

---@internal
--- Every registered action with *all* of its `lhs` values, unlike
--- `keymap_actions`, which keeps one. The distinction is the whole point
--- here: an action bound to a fragile key and a portable alias is fine, and
--- collapsing the two would hide exactly the thing being checked.
---@param root string|nil
---@return table<string, { surface: string, name: string, desc: string|nil, lhs: string[] }>
local function actions_with_keys(root)
  local keymap = require("lib.nvim.bindings.keymap")
  local plugin = root and plugin_of(root) or nil
  local buckets = plugin and { [plugin] = keymap.registered(plugin) } or keymap.registered()

  local out = {}
  for surface, entries in pairs(buckets) do
    for _, e in ipairs(entries) do
      if e.bound and e.lhs then
        local id = surface .. "." .. e.name
        local rec = out[id]
        if not rec then
          rec = { surface = surface, name = e.name, desc = e.desc, lhs = {} }
          out[id] = rec
        end
        if not vim.tbl_contains(rec.lhs, e.lhs) then
          rec.lhs[#rec.lhs + 1] = e.lhs
        end
      end
    end
  end
  return out
end

---Actions with no `lhs` a terminal is guaranteed to deliver.
---
---The lint half of `keymap.portability`: that module says what a key notation
---costs, this one says who is *exposed* to it -- an action is only reported
---when **none** of its keys classifies `portable`. An action bound to
---`<C-M-y>` and `<leader>cy` never appears here; one bound to `<C-M-y>` alone
---does.
---
---Two tiers surface, and they are not the same finding:
---
---  - `fragile` -- the key needs "CSI u"/modifyOtherKeys or a GUI. On a
---    terminal without it, the action is simply unreachable. Fix it.
---  - `common` -- the key arrives nearly everywhere, but through a mechanism
---    with an off switch (Alt as ESC prefix, Ctrl+Space as NUL) or an
---    ambiguity (`<C-i>` is `<Tab>`'s byte). Worth an alias, not an alarm.
---
---The fix is always the same shape, and the registry has always supported it:
---put a portable key in the action's `default` list next to the fancy one.
---Detection is not an option -- see `keymap.portability` for why.
---@param root string|nil  same scope `keymap_actions` takes
---@return Lib.Bindings.Audit.KeyRisk[] # `fragile` first, then `common`.
function M.key_risks(root)
  local portability = require("lib.nvim.bindings.keymap.portability")

  local risks = {}
  for _, rec in pairs(actions_with_keys(root)) do
    local keys, best = {}, "fragile"
    for _, lhs in ipairs(rec.lhs) do
      local tier, reason = portability.classify(lhs)
      keys[#keys + 1] = { lhs = lhs, tier = tier, reason = reason }
      if RANK[tier] < RANK[best] then
        best = tier
      end
    end
    if best ~= "portable" then
      risks[#risks + 1] =
        { surface = rec.surface, name = rec.name, keys = keys, best = best, desc = rec.desc }
    end
  end

  table.sort(risks, function(a, b)
    if a.best ~= b.best then
      return RANK[a.best] > RANK[b.best]
    end
    if a.surface ~= b.surface then
      return a.surface < b.surface
    end
    return a.name < b.name
  end)
  return risks
end

---`key_risks` as printable lines.
---@param root string|nil
---@return string[]
function M.key_risk_lines(root)
  local risks = M.key_risks(root)
  if #risks == 0 then
    return { "every registered action has at least one key a terminal is sure to deliver." }
  end

  local fragile = 0
  for _, r in ipairs(risks) do
    if r.best == "fragile" then
      fragile = fragile + 1
    end
  end

  local out = {
    ('%d action(s) with no portable key -- %d unreachable without "CSI u", %d layout-sensitive:'):format(
      #risks,
      fragile,
      #risks - fragile
    ),
    "",
  }
  for _, r in ipairs(risks) do
    local shown = {}
    for _, k in ipairs(r.keys) do
      shown[#shown + 1] = k.lhs
    end
    out[#out + 1] = ("  %-8s %-28s %s"):format(
      r.best,
      r.surface .. "." .. r.name,
      table.concat(shown, " ")
    )
    for _, k in ipairs(r.keys) do
      if k.reason ~= "" then
        out[#out + 1] = ("           %s: %s"):format(k.lhs, k.reason)
      end
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = "fix: add a portable lhs to the action's `default` list -- it accepts several."
  return out
end

---@internal
local STOP = {
  ["the"] = true,
  ["a"] = true,
  ["an"] = true,
  ["to"] = true,
  ["in"] = true,
  ["of"] = true,
  ["and"] = true,
  ["or"] = true,
  ["for"] = true,
  ["this"] = true,
  ["that"] = true,
  ["with"] = true,
  ["on"] = true,
  ["at"] = true,
  ["by"] = true,
  ["it"] = true,
  ["as"] = true,
  ["from"] = true,
  ["toggle"] = true,
  ["open"] = true,
  ["show"] = true,
}

---@internal
--- Meaningful words in `text`: lowercase, 3+ chars, past the stoplist.
---@param text string|nil
---@return table<string, true>
local function words(text)
  local set = {}
  for w in (text or ""):lower():gmatch("[%a%d]+") do
    if #w > 2 and not STOP[w] then
      set[w] = true
    end
  end
  return set
end

---@internal
---Does `action` have a plausible counterpart among `routes`? Name match (the
---action's own name, or every `_`-part of it, in a route's text), else at
---least half its description's meaningful words covered.
---@param action Lib.Bindings.Audit.KeyAction
---@param blob string  every route's name/path/desc, lowercased, joined
---@param blob_words table<string, true>
---@return boolean
local function has_route_match(action, blob, blob_words)
  local name_lower = action.name:lower()
  if blob:find(name_lower, 1, true) then
    return true
  end
  local name_parts = {}
  for p in action.name:gmatch("[^_]+") do
    if #p > 2 then
      name_parts[#name_parts + 1] = p
    end
  end
  if #name_parts > 0 then
    local all = true
    for _, p in ipairs(name_parts) do
      if not blob:find(p:lower(), 1, true) then
        all = false
        break
      end
    end
    if all then
      return true
    end
  end
  local dw = words(action.desc)
  local dw_count, overlap = 0, 0
  for w in pairs(dw) do
    dw_count = dw_count + 1
    if blob_words[w] then
      overlap = overlap + 1
    end
  end
  return dw_count > 0 and overlap >= math.max(1, math.floor(dw_count / 2))
end

---Keymap actions with no obvious command counterpart. A candidate list, not
---a verdict — a route with a typed argument (`:Open <handler>`) can cover
---many actions without naming any of them by name, so every candidate still
---wants a look.
---@param root string|nil  same scope `keymap_actions`/`command_routes` take
---@return Lib.Bindings.Audit.KeyAction[]
function M.gaps(root)
  local actions = M.keymap_actions(root)
  if #actions == 0 then
    return {}
  end
  local routes = M.command_routes(root)

  local parts = {}
  for _, r in ipairs(routes) do
    parts[#parts + 1] = r.name
    parts[#parts + 1] = r.path
    parts[#parts + 1] = r.desc
  end
  local blob = table.concat(parts, " "):lower()
  local blob_words = words(blob)

  local gaps = {}
  for _, a in ipairs(actions) do
    if not has_route_match(a, blob, blob_words) then
      gaps[#gaps + 1] = a
    end
  end
  return gaps
end

---Full audit as printable lines: every keymap action, then every command
---route.
---@param root string|nil
---@return string[]
function M.lines(root)
  local actions = M.keymap_actions(root)
  local routes = M.command_routes(root)

  local out = { ("KEYMAP ACTIONS: %d"):format(#actions) }
  for _, a in ipairs(actions) do
    out[#out + 1] = ("  %-28s %-10s %s"):format(
      a.surface .. "." .. a.name,
      a.lhs or "-",
      a.desc or ""
    )
  end
  out[#out + 1] = ""
  out[#out + 1] = ("COMMAND ROUTES: %d"):format(#routes)
  for _, r in ipairs(routes) do
    out[#out + 1] = ("  %-20s %-24s %s"):format(r.name, r.path, r.desc)
  end
  return out
end

---Gaps as printable lines.
---@param root string|nil
---@return string[]
function M.gap_lines(root)
  local gaps = M.gaps(root)
  if #gaps == 0 then
    return { "no gaps -- every keymap action has a plausible command counterpart." }
  end
  local out = { ("%d action(s) with no obvious command counterpart:"):format(#gaps) }
  for _, a in ipairs(gaps) do
    out[#out + 1] = ("  %-28s %s"):format(a.surface .. "." .. a.name, a.desc or "")
  end
  return out
end

---Expose `:<name> [path]` (full audit) and `:<name>Gaps [path]` for the
---calling config or plugin. Put this call in **your own config**, not in a
---library — the same reasoning `bindings.usercmd.docs.create_usercmd` gives.
---@param name string|nil  # Default `LibBindingsAudit`.
---@return nil
function M.create_usercmd(name)
  local base = name or "LibBindingsAudit"
  local usercmd = require("lib.nvim.bindings.usercmd")

  local function show(title, lines)
    local ok, kit = pcall(require, "lib.nvim.ui.kit")
    if ok then
      kit.viewer({ lines = lines, title = title, width = math.min(120, vim.o.columns - 8) })
      return
    end
    print(table.concat(lines, "\n"))
  end

  usercmd.create(base, function(opts)
    local root = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p"):gsub("/$", "") or nil
    show(" " .. base .. " ", M.lines(root))
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Keymap actions vs. command routes, registered in this session (optional: scope to a repo path)",
  })

  usercmd.create(base .. "Keys", function(opts)
    local root = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p"):gsub("/$", "") or nil
    show(" " .. base .. "Keys ", M.key_risk_lines(root))
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Actions whose every key needs an extended terminal encoding (optional: scope to a repo path)",
  })

  usercmd.create(base .. "Gaps", function(opts)
    local root = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p"):gsub("/$", "") or nil
    show(" " .. base .. "Gaps ", M.gap_lines(root))
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Keymap actions with no obvious command counterpart (optional: scope to a repo path)",
  })
end

return M
