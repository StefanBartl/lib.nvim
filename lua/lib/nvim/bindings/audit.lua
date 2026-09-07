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

-- Lib.Bindings.Audit.{KeyAction,CmdRoute,KeyTier,KeyRisk}: see @types/audit.lua.

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
--- Words vague enough, alone, to plausibly name almost any subcommand — the
--- shape `:LspDoctor deep` had before it became `:LspDoctor fmt_check` (the
--- prior name said a *level*, not what the command actually reports: which
--- formatter is active). Listed so a route whose last path segment is one of
--- these gets flagged for a human look. The word is not wrong by itself —
--- `:Lsp status` is fine, "status" names the whole answer there — only a
--- *bare* occurrence as the final segment is a candidate.
local VAGUE_LAST_SEGMENT = {
  deep = true,
  full = true,
  check = true,
  info = true,
  debug = true,
  all = true,
  basic = true,
  extra = true,
  advanced = true,
  misc = true,
}

---Every command route (`command_routes`), flagged where its last path
---segment is a single vague word.
---
---A candidate list, not a verdict — same caveat `gaps` already carries: the
---fix is always a judgment call about what the command *actually* reports,
---which this cannot know. `root` scopes the same way `command_routes` does.
---@param root string|nil
---@return (Lib.Bindings.Audit.CmdRoute|{vague: boolean})[]
function M.naming_candidates(root)
  local routes = M.command_routes(root)
  local out = {}
  for _, r in ipairs(routes) do
    local last = r.path:match("(%S+)$")
    local vague = last ~= nil and VAGUE_LAST_SEGMENT[last:lower()] == true
    out[#out + 1] = vim.tbl_extend("force", {}, r, { vague = vague })
  end
  return out
end

---`naming_candidates()`, flagged rows only, as printable lines.
---@param root string|nil
---@return string[]
function M.naming_candidate_lines(root)
  local flagged = {}
  for _, r in ipairs(M.naming_candidates(root)) do
    if r.vague then
      flagged[#flagged + 1] = r
    end
  end
  if #flagged == 0 then
    return { "no naming candidates -- no route's last segment is a bare vague word." }
  end
  local out = {
    ("%d route(s) worth a naming look (last segment is a single vague word):"):format(#flagged),
    "",
  }
  for _, r in ipairs(flagged) do
    out[#out + 1] = ("  :%-16s %-24s %s"):format(r.name, r.path, r.desc)
  end
  out[#out + 1] = ""
  out[#out + 1] =
    "a flag here is a candidate, not a verdict -- e.g. :LspDoctor deep became :LspDoctor fmt_check for exactly this reason."
  return out
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

---@internal
--- Every user-command name Neovim currently knows, builtins excluded.
---@return string[]  sorted
local function live_command_names()
  local names = {}
  for name in pairs(vim.api.nvim_get_commands({ builtin = false })) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

-- Lib.Bindings.Audit.PrefixAmbiguity: see @types/audit.lua.

---Command names that are a strict prefix of another registered name — the
---`<Tab>`/abbreviation collision a plugin's own docs cannot see, because it
---only knows its own names.
---
---Exact-name duplicates cannot happen here: `nvim_create_user_command`
---errors on a second registration of a name that already exists (unless the
---first is deleted first), so the only thing left to find between two
---*distinct* live names is one swallowing the other's abbreviation — typing
---the short one in full still resolves correctly, `<Tab>` after it does not.
---@return Lib.Bindings.Audit.PrefixAmbiguity[]  sorted by `short`
function M.prefix_ambiguities()
  local names = live_command_names()
  local out = {}
  for i, short in ipairs(names) do
    local longer = {}
    for j, other in ipairs(names) do
      if i ~= j and #other > #short and other:sub(1, #short) == short then
        longer[#longer + 1] = other
      end
    end
    if #longer > 0 then
      out[#out + 1] = { short = short, longer = longer }
    end
  end
  return out
end

---`prefix_ambiguities()` as printable lines.
---@return string[]
function M.prefix_ambiguity_lines()
  local rows = M.prefix_ambiguities()
  if #rows == 0 then
    return { "no prefix ambiguities -- every command name resolves to itself uniquely." }
  end
  local out = { ("%d command name(s) that are a prefix of another:"):format(#rows) }
  for _, r in ipairs(rows) do
    local shown = {}
    for _, n in ipairs(r.longer) do
      shown[#shown + 1] = ":" .. n
    end
    out[#out + 1] = ("  :%-20s <Tab> also offers: %s"):format(r.short, table.concat(shown, ", "))
  end
  out[#out + 1] = ""
  out[#out + 1] =
    "typing the short name in full still resolves to it -- only abbreviation/<Tab> is affected."
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

---@internal
--- Words suggesting an action is destructive enough to want a second look
--- before triggering it -- never used to invoke anything (nothing in this
--- module ever does), only to sort candidates into their own checklist
--- section so they are not stumbled into by accident. A guess, not a
--- verdict: this config's own command surface includes `:Sandbox wsl
--- shutdown-all`, `:Cases delete`, `:File delete` and `:MyPlugins remove`,
--- and no keyword list is trustworthy enough to *decide* which of ~1300
--- entries are safe to fire unattended -- see the module doc above
--- `checklist_lines` for why that path was rejected outright rather than
--- attempted.
local RISKY_WORDS = {
  "delete",
  "remove",
  "kill",
  "shutdown",
  "stop",
  "wipe",
  "prune",
  "reset",
  "clean",
  "restart",
  "uninstall",
  "destroy",
  "drop",
  "force",
  "reclone",
  "revert",
  "overwrite",
}

---@internal
---@param text string|nil
---@return boolean
local function looks_risky(text)
  local lower = (text or ""):lower()
  for _, w in ipairs(RISKY_WORDS) do
    if lower:find(w, 1, true) then
      return true
    end
  end
  return false
end

---A Markdown checklist over every registered keymap action and command
---route — one box per item, meant to be worked through **by hand** in a real
---session: trigger each one yourself, tick it if it does what its
---description says, leave a note if it does not. Same
---checkbox-and-manual-verification shape
---`docs/ROADMAP/personal/All/FINISH/PLUGIN_ROADMAPS_TESTPLAN.md` already
---uses in the calling config, not a new convention.
---
---**Deliberately never invokes anything itself.** The obvious next step —
---auto-run everything that "looks safe" — was considered and rejected: this
---config's own command surface includes things like `:Sandbox wsl
---shutdown-all`, `:Cases delete` and `:File delete`, and a keyword guess
---is not trustworthy enough to gate real execution of ~1300 entries. See
---`docs/ROADMAP/handovers/CDX-bindings-runtime-check.md`, Phase 4, for the
---full reasoning. `looks_risky` below sorts candidates into their own
---section for extra caution — a hint for the human doing the walk, nothing
---more.
---@param root string|nil
---@return string[]
function M.checklist_lines(root)
  local actions = M.keymap_actions(root)
  local routes = M.command_routes(root)

  local out = {
    "# Bindings — runtime checklist",
    "",
    "Generated, not hand-written -- work through it in a real session: trigger",
    "each one yourself, tick it if it does what its description says, leave a",
    "note here if it does not. Nothing on this list was invoked by the",
    "generator to build it -- see `bindings.audit.checklist_lines`'s doc",
    "comment for why.",
    "",
    "Checkbox convention: `- [ ]` open, `- [x]` verified.",
    "",
    "## Keymaps",
    "",
  }

  local by_surface, surfaces = {}, {}
  for _, a in ipairs(actions) do
    if a.bound and a.lhs then
      if not by_surface[a.surface] then
        by_surface[a.surface] = {}
        surfaces[#surfaces + 1] = a.surface
      end
      table.insert(by_surface[a.surface], a)
    end
  end
  table.sort(surfaces)

  local risky = {}
  for _, surface in ipairs(surfaces) do
    local kept = {}
    for _, a in ipairs(by_surface[surface]) do
      if looks_risky(a.desc) or looks_risky(a.name) then
        risky[#risky + 1] = ("- [ ] `%s` (%s) -- %s"):format(a.lhs, surface, a.desc or a.name)
      else
        kept[#kept + 1] = ("- [ ] `%s` -- %s"):format(a.lhs, a.desc or a.name)
      end
    end
    -- Only a group with something left earns a heading -- one whose every
    -- key was risky would otherwise leave a dangling "### surface" with
    -- nothing under it.
    if #kept > 0 then
      out[#out + 1] = "### " .. surface
      out[#out + 1] = ""
      vim.list_extend(out, kept)
      out[#out + 1] = ""
    end
  end

  out[#out + 1] = "## Usercmds"
  out[#out + 1] = ""

  local by_name, names = {}, {}
  for _, r in ipairs(routes) do
    if not by_name[r.name] then
      by_name[r.name] = {}
      names[#names + 1] = r.name
    end
    table.insert(by_name[r.name], r)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local kept = {}
    for _, r in ipairs(by_name[name]) do
      local bare = r.path == "(bare)" or r.path == "(root)" or r.path == "(plain)"
      local trigger = bare and (":" .. name) or (":" .. name .. " " .. r.path)
      local desc = r.desc ~= "" and r.desc or "(no description)"
      local line = ("- [ ] `%s` -- %s"):format(trigger, desc)
      if looks_risky(r.desc) or looks_risky(r.path) then
        risky[#risky + 1] = line
      else
        kept[#kept + 1] = line
      end
    end
    if #kept > 0 then
      out[#out + 1] = "### :" .. name
      out[#out + 1] = ""
      vim.list_extend(out, kept)
      out[#out + 1] = ""
    end
  end

  if #risky > 0 then
    out[#out + 1] = "## ⚠ Handle with care"
    out[#out + 1] = ""
    out[#out + 1] = ("%d item(s) flagged by a keyword guess (delete/remove/kill/"):format(#risky)
    out[#out + 1] = "shutdown/... in the description or route) -- a candidate for extra"
    out[#out + 1] = "caution, not a verdict. Read the description before triggering any of these."
    out[#out + 1] = ""
    for _, l in ipairs(risky) do
      out[#out + 1] = l
    end
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

  -- No `[path]` argument, unlike the three above: prefix ambiguity is a
  -- property of the whole live command namespace, not of one repo's routes
  -- — scoping it to a directory would not change which names collide.
  usercmd.create(base .. "Prefixes", function()
    show(" " .. base .. "Prefixes ", M.prefix_ambiguity_lines())
  end, {
    desc = "Command names that are a strict prefix of another live command (<Tab>/abbreviation collisions)",
  })

  usercmd.create(base .. "Naming", function(opts)
    local root = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p"):gsub("/$", "") or nil
    show(" " .. base .. "Naming ", M.naming_candidate_lines(root))
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Routes whose last path segment is a bare vague word (deep/full/check/...) -- candidates for a naming review, not a verdict",
  })

  usercmd.create(base .. "Checklist", function(opts)
    local root = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p"):gsub("/$", "") or nil
    show(" " .. base .. "Checklist ", M.checklist_lines(root))
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Markdown checklist over every keymap action and command route, for a manual runtime pass (optional: scope to a repo path; never invokes anything)",
  })
end

---@type Lib.Bindings.Audit
return M
