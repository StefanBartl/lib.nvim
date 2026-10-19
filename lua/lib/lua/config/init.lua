---@module 'lib.lua.config'
--- Pure helpers for the "defaults + user overrides" config store pattern:
--- the `setup(opts)` / `get(path)` pair almost every plugin's `config` module
--- implements.
---@description
--- Extracted from **two** byte-identical copies: cascade.nvim's and
--- spotlight.nvim's `config/init.lua` each had their own `deep_merge` and
--- `M.get`.
---
--- `deep_merge` here is deliberately not `lib.lua.tables.core.deep_merge`:
--- that one mutates `dst` in place and recurses into *every* nested table,
--- including list-like ones. A default `{ groups = { "a", "b", "c" } }`
--- overridden with `{ groups = { "x" } }` would then keep `"b"` and `"c"`
--- behind index 1's new value — exactly the array-merge surprise a config
--- store must not have, since it silently keeps stale defaults a user
--- explicitly tried to replace. This version copies `base` instead of
--- mutating it, and replaces a list-like table (per
--- `lib.lua.tables.core.is_array`) wholesale rather than recursing into it.
---
--- The result shares no table with either argument: writing into it later
--- (a plugin storing a cursor position under `cfg.state`, say) can neither
--- change the defaults a following `setup()` starts from nor the table the
--- caller passed in (a lazy.nvim `opts`).

local tables = require("lib.lua.tables.core")

local M = {}

---Deep copy of `t`: every table is new, functions and other values are kept as
---they are, metatables are carried over by reference. Shared and cyclic
---references inside `t` stay shared and cyclic inside the copy.
---@generic T
---@param t T
---@param seen? table<table, table>
---@return T
function M.copy(t, seen)
  if type(t) ~= "table" then
    return t
  end
  seen = seen or {}
  if seen[t] then
    return seen[t]
  end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do
    out[M.copy(k, seen)] = M.copy(v, seen)
  end
  local mt = getmetatable(t)
  if mt ~= nil then
    setmetatable(out, mt)
  end
  return out
end

---Write `override` into `out`, which is already a private copy (see
---`deep_merge` for the rules). With `rules` (dotted path -> rule), a path can
---be merged differently from the default way:
---  * `"replace"`: the override value replaces whatever is there, even `{}` or
---    a map, so "this exact set" can be said for a section that would merge;
---  * `"entries"`: the override is a map of independent entries; each entry
---    replaces the default one of the same key as a whole, `false` removes it,
---    entries it does not name stay.
---@param out table
---@param override table
---@param rules? table<string, Lib.Config.MergeRule>
---@param path? string  dotted path of `out`, only tracked when `rules` is given
function M.merge_into(out, override, rules, path)
  for k, v in pairs(override) do
    local cur = out[k]
    local here = rules and (path and (path .. "." .. tostring(k)) or tostring(k)) or nil
    local rule = rules and rules[here] or nil
    if rule == "replace" then
      out[k] = M.copy(v)
    elseif rule == "entries" and type(v) == "table" then
      if type(cur) ~= "table" then
        cur = {}
        out[k] = cur
      end
      for entry_key, entry in pairs(v) do
        if entry == false then
          cur[entry_key] = nil
        else
          cur[entry_key] = M.copy(entry)
        end
      end
    elseif type(v) ~= "table" or type(cur) ~= "table" then
      out[k] = M.copy(v)
    elseif next(v) == nil then
      if next(cur) == nil or tables.is_array(cur) then
        out[k] = {}
      end
    elseif tables.is_array(v) or tables.is_array(cur) then
      out[k] = M.copy(v)
    else
      M.merge_into(cur, v, rules, here)
    end
  end
end

---Recursively merge `override` into a copy of `base`. Neither argument is
---mutated and the result shares no table with them.
---
---Which tables merge and which replace:
---  * a list-like override replaces wholesale (never merged index by index),
---    so overriding e.g. `cycle.groups` fully redefines it;
---  * an empty `{}` override follows the shape of the default: over a list (or
---    another empty table) it replaces, i.e. "no entries", over a map it
---    changes nothing, because an empty map has no key to override;
---  * a map override merges key by key into a map default;
---  * anything else (scalar, `false`, mismatched shapes) replaces;
---  * `rules` changes this for single paths, see `merge_into`.
---@param base table
---@param override table
---@param rules? table<string, Lib.Config.MergeRule>
---@return table
function M.deep_merge(base, override, rules)
  local out = M.copy(base)
  M.merge_into(out, override, rules)
  return out
end

---Read a value out of `tbl` by dot-separated `path`, e.g. `get(opts, "a.b.c")`.
---A missing intermediate key, or a non-table where a table was expected,
---returns `nil` rather than erroring.
---@param tbl table
---@param path string?
---@return any
function M.get(tbl, path)
  if type(path) ~= "string" then
    return nil
  end
  local node = tbl
  for key in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
  end
  return node
end

local checked = os.getenv("LIB_CONFIG_CHECKED") == "1"

---Switch the checking mode of every config object made by `new`: while on,
---`get()` fails when the stored table was written to since it was built (the
---message names the path), instead of the write going unnoticed until a later
---`setup()` starts from a changed state. Meant for the specs of a plugin; the
---environment variable `LIB_CONFIG_CHECKED=1` turns it on from the outside.
---(A read-only proxy would catch the write itself, but LuaJIT has no `__pairs`,
---`__len` or `__ipairs`, so a proxy could not be iterated.)
---@param on boolean
function M.set_checked(on)
  checked = on == true
end

---@return boolean
function M.is_checked()
  return checked
end

---A config object for a plugin: see `lib.lua.config.instance`.
---@param defaults table
---@param spec? Lib.Config.Spec
---@return Lib.Config.Instance
function M.new(defaults, spec)
  return require("lib.lua.config.instance").new(defaults, spec)
end

---@type Lib.Config
return M
