---@module 'lib.nvim.docmap.diff'
--- Structural difference between two maps: what a branch changed about the
--- shape of the tree, rather than about its text.
---
--- This is the point at which the committed artifact stops being a picture and
--- starts being a *comparison point*. It is already in every commit, so any
--- two revisions can be compared without generating anything — and the answer
--- ("one module added, one new dependency, a cycle introduced, this module's
--- blast radius went from 29 to 34") is a review summary nobody writes by
--- hand.
---
--- Pure: two IRs in, a structured diff out. No git, no filesystem, no
--- rendering — `command.lua` fetches the old artifact and prints the result,
--- and a CI job could do the same without an editor.
---
--- ## Comparing against an older schema
---
--- The artifact carries `meta.schema`, and older ones are genuinely missing
--- data rather than merely differing in layout: schema 1 predates the require
--- and call graphs entirely, so its `edges` are type edges only. Reporting
--- every dependency in the tree as "added" against such a map would be
--- technically true and completely useless, so those sections are suppressed
--- and the reason is stated instead. Silently comparing incomparable things is
--- the failure mode worth avoiding here.

local M = {}

---Node ids present in an IR, as a set.
---@param ir Lib.Docmap.IR
---@return table<string, boolean>
local function node_set(ir)
  local set = {}
  for _, id in ipairs(ir.order or {}) do
    set[id] = true
  end
  return set
end

---`"<node id>#<declared name>"` for every documented function, as a set —
---the same key the HTML map and the handle queries use.
---@param ir Lib.Docmap.IR
---@return table<string, boolean>
local function function_set(ir)
  local set = {}
  for _, id in ipairs(ir.order or {}) do
    for _, fn in ipairs((ir.nodes[id] or {}).functions or {}) do
      set[id .. "#" .. fn.name] = true
    end
  end
  return set
end

---Require edges as `"from -> to"`, mapped to whether the edge is lazy.
---@param ir Lib.Docmap.IR
---@return table<string, boolean> edges key -> deferred
---@return integer count
local function require_set(ir)
  local set, n = {}, 0
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "require" then
      local key = e.from .. " -> " .. e.to
      if set[key] == nil then
        n = n + 1
      end
      set[key] = e.deferred == true
    end
  end
  return set, n
end

---True when this IR is old enough that its dependency data is absent rather
---than merely different.
---@param ir Lib.Docmap.IR
---@return boolean
local function predates_graphs(ir)
  local schema = (ir.meta or {}).schema or 1
  if schema >= 2 then
    return false
  end
  local _, n = require_set(ir)
  return n == 0
end

---Sorted keys of a set.
---@param set table<string, any>
---@return string[]
local function sorted_keys(set)
  local out = {}
  for k in pairs(set) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

---Compare two maps.
---@param before Lib.Docmap.IR
---@param after Lib.Docmap.IR
---@return Lib.Docmap.Diff
function M.compare(before, after)
  local was, now = node_set(before), node_set(after)

  ---@type Lib.Docmap.Diff
  local diff = {
    nodes_added = {},
    nodes_removed = {},
    functions_added = {},
    functions_removed = {},
    deps_added = {},
    deps_removed = {},
    deps_comparable = not predates_graphs(before),
    cycles_added = {},
    cycles_removed = {},
    impact_changed = {},
  }

  for _, id in ipairs(sorted_keys(now)) do
    if not was[id] then
      diff.nodes_added[#diff.nodes_added + 1] = id
    end
  end
  for _, id in ipairs(sorted_keys(was)) do
    if not now[id] then
      diff.nodes_removed[#diff.nodes_removed + 1] = id
    end
  end

  local fn_was, fn_now = function_set(before), function_set(after)
  for _, key in ipairs(sorted_keys(fn_now)) do
    if not fn_was[key] then
      diff.functions_added[#diff.functions_added + 1] = key
    end
  end
  for _, key in ipairs(sorted_keys(fn_was)) do
    if not fn_now[key] then
      diff.functions_removed[#diff.functions_removed + 1] = key
    end
  end

  if diff.deps_comparable then
    local dep_was, dep_now = require_set(before), require_set(after)
    for _, key in ipairs(sorted_keys(dep_now)) do
      if dep_was[key] == nil then
        diff.deps_added[#diff.deps_added + 1] = { edge = key, deferred = dep_now[key] }
      elseif dep_was[key] ~= dep_now[key] then
        -- A dependency that stopped being lazy is a load-time dependency that
        -- did not exist before, which is exactly the kind of change that
        -- introduces an initialisation cycle. Not "added", but not nothing.
        diff.deps_added[#diff.deps_added + 1] = {
          edge = key,
          deferred = dep_now[key],
          changed = true,
        }
      end
    end
    for _, key in ipairs(sorted_keys(dep_was)) do
      if dep_now[key] == nil then
        diff.deps_removed[#diff.deps_removed + 1] = { edge = key, deferred = dep_was[key] }
      end
    end

    local check = require("lib.nvim.docmap.check")
    local function cycle_keys(ir)
      local set = {}
      for _, component in ipairs(check.require_cycles(ir)) do
        set[table.concat(component, " ↔ ")] = true
      end
      return set
    end
    local cyc_was, cyc_now = cycle_keys(before), cycle_keys(after)
    for _, key in ipairs(sorted_keys(cyc_now)) do
      if not cyc_was[key] then
        diff.cycles_added[#diff.cycles_added + 1] = key
      end
    end
    for _, key in ipairs(sorted_keys(cyc_was)) do
      if not cyc_now[key] then
        diff.cycles_removed[#diff.cycles_removed + 1] = key
      end
    end

    -- Blast radius, only for nodes that exist on both sides: a module that
    -- was added has no "before" to compare against, and reporting 0 -> N for
    -- it would drown the changes that are actually about coupling.
    local deps = require("lib.nvim.docmap.deps")
    for _, id in ipairs(sorted_keys(now)) do
      if was[id] then
        local a = #(deps.impact(before, id))
        local b = #(deps.impact(after, id))
        if a ~= b then
          diff.impact_changed[#diff.impact_changed + 1] = { id = id, before = a, after = b }
        end
      end
    end
    table.sort(diff.impact_changed, function(x, y)
      local dx, dy = math.abs(x.after - x.before), math.abs(y.after - y.before)
      if dx ~= dy then
        return dx > dy
      end
      return x.id < y.id
    end)
  end

  return diff
end

---True when nothing structural changed.
---@param diff Lib.Docmap.Diff
---@return boolean
function M.is_empty(diff)
  return #diff.nodes_added == 0
    and #diff.nodes_removed == 0
    and #diff.functions_added == 0
    and #diff.functions_removed == 0
    and #diff.deps_added == 0
    and #diff.deps_removed == 0
    and #diff.cycles_added == 0
    and #diff.cycles_removed == 0
    and #diff.impact_changed == 0
end

---Render a diff as plain lines.
---
---`after` is passed so ids can be shown as module paths where one exists;
---removed nodes fall back to their id, which is the only name left for them.
---True when a function key names implementation rather than surface.
---
---`@internal` when the map has it, and the shape of the declared name when it
---does not — an older artifact carries no such field, and a diff against one
---should still sort its entries sensibly rather than give up.
---@param ir Lib.Docmap.IR
---@param key string
---@return boolean
local function is_helper(ir, key)
  local id, fn_name = key:match("^(.*)#([^#]*)$")
  for _, fn in ipairs(((ir.nodes or {})[id or ""] or {}).functions or {}) do
    if fn.name == fn_name then
      if fn.internal ~= nil then
        return fn.internal
      end
      break
    end
  end
  return not (fn_name or ""):find(".", 1, true)
end

---@param diff Lib.Docmap.Diff
---@param before Lib.Docmap.IR
---@param after Lib.Docmap.IR
---@param label string? What the comparison is against, for the header.
---@return string[]
function M.render(diff, before, after, label)
  local function name(id)
    local node = (after.nodes or {})[id] or (before.nodes or {})[id]
    return (node and (node.module or node.path)) or id
  end
  local function fn_name(key)
    local id, fn = key:match("^(.*)#([^#]*)$")
    return ("%s  %s"):format(name(id or key), fn or "?")
  end
  local function edge_name(key)
    local from, to = key:match("^(.-) %-> (.*)$")
    return ("%s → %s"):format(name(from or key), name(to or ""))
  end

  local out = {
    ("Structural diff%s"):format(label and (" against " .. label) or ""),
    "",
  }

  if M.is_empty(diff) then
    out[#out + 1] = "Nothing structural changed."
    return out
  end

  ---@param title string
  ---@param items string[]
  ---@param prefix string
  local function section(title, items, prefix)
    if #items == 0 then
      return
    end
    out[#out + 1] = ("%s (%d)"):format(title, #items)
    for _, line in ipairs(items) do
      out[#out + 1] = ("  %s %s"):format(prefix, line)
    end
    out[#out + 1] = ""
  end

  section("Modules added", vim.tbl_map(name, diff.nodes_added), "+")
  section("Modules removed", vim.tbl_map(name, diff.nodes_removed), "-")
  -- Split by whether the declared name is qualified (`M.compare`) or bare
  -- (`node_set`). A qualified name is the module's surface; a bare one is a
  -- file-local helper, and a diff that lists both equally buries the six
  -- entries that matter under eleven that do not. The count is still shown,
  -- because "this change added eleven helpers" is itself information.
  local function split_surface(keys, ir)
    local public, private = {}, {}
    for _, key in ipairs(keys) do
      if is_helper(ir, key) then
        private[#private + 1] = fn_name(key)
      else
        public[#public + 1] = fn_name(key)
      end
    end
    return public, private
  end

  local pub_add, priv_add = split_surface(diff.functions_added, after)
  local pub_del, priv_del = split_surface(diff.functions_removed, before)
  section("Functions added", pub_add, "+")
  section("Functions removed", pub_del, "-")
  if #priv_add > 0 or #priv_del > 0 then
    out[#out + 1] = ("Module-local helpers: +%d / -%d"):format(#priv_add, #priv_del)
    out[#out + 1] = ""
  end

  if not diff.deps_comparable then
    out[#out + 1] = "Dependencies, cycles and impact are not comparable:"
    out[#out + 1] = "the older map predates the dependency graph (schema 1)."
    out[#out + 1] = ""
  else
    section(
      "Dependencies added",
      vim.tbl_map(function(d)
        return edge_name(d.edge)
          .. (d.changed and "   (was lazy, now load-time)" or (d.deferred and "   (lazy)" or ""))
      end, diff.deps_added),
      "+"
    )
    section(
      "Dependencies removed",
      vim.tbl_map(function(d)
        return edge_name(d.edge)
      end, diff.deps_removed),
      "-"
    )

    -- Cycles first among the "!" items: a new load-time cycle is the one
    -- finding here that can break the build rather than merely describe it.
    section(
      "Load-time cycles introduced",
      vim.tbl_map(function(key)
        local parts = {}
        for id in key:gmatch("[^ ↔]+") do
          parts[#parts + 1] = name(id)
        end
        return table.concat(parts, " ↔ ")
      end, diff.cycles_added),
      "!"
    )
    section(
      "Load-time cycles resolved",
      vim.tbl_map(function(key)
        local parts = {}
        for id in key:gmatch("[^ ↔]+") do
          parts[#parts + 1] = name(id)
        end
        return table.concat(parts, " ↔ ")
      end, diff.cycles_removed),
      "✓"
    )

    section(
      "Blast radius changed",
      vim.tbl_map(function(c)
        return ("%s   %d → %d"):format(name(c.id), c.before, c.after)
      end, diff.impact_changed),
      "~"
    )
  end

  return out
end

return M
