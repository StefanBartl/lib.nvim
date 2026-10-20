---@module 'lib.lua.config.instance'
--- The config object of a plugin: `DEFAULTS` + the options a user gave, merged
--- the same way everywhere. Made with `require("lib.lua.config").new(DEFAULTS, spec)`.
---@description
--- Every change (`setup`, `layer`, `reset`) recomputes the whole config from
--- scratch: a fresh, alias-free copy of `DEFAULTS`, the layers on top in rank
--- order, then `resolve`. Nothing is ever merged onto the previous state, so an
--- option dropped from the user's config is gone after the next `setup()`.
---
--- Each layer is checked once, when it is set: `normalize` (liberal in), then
--- the schema inferred from `DEFAULTS` (unknown keys with a did-you-mean hint,
--- wrong types), which leaves the rejected part out so the default applies.
---
--- No `vim.*`: notifying and `:checkhealth` are the plugin's, through
--- `spec.notify` and `issues()`.

local config = require("lib.lua.config")
local schema = require("lib.lua.config.schema")

local M = {}

local SETUP = "setup"

---@param dst string[]
---@param src string[]
local function append(dst, src)
  for _, line in ipairs(src) do
    dst[#dst + 1] = line
  end
end

---Write `value` at the dotted `path` of `tbl`, creating the tables on the way.
---@param tbl table
---@param path string
---@param value any
local function set_path(tbl, path, value)
  local node = tbl
  local keys = {}
  for key in path:gmatch("[^.]+") do
    keys[#keys + 1] = key
  end
  for i = 1, #keys - 1 do
    if type(node[keys[i]]) ~= "table" then
      node[keys[i]] = {}
    end
    node = node[keys[i]]
  end
  node[keys[#keys]] = value
end

---@param path string
---@param key any
---@return string
local function join(path, key)
  if path == "" then
    return tostring(key)
  end
  return path .. "." .. tostring(key)
end

---First path at which `a` and `b` differ, or nil.
---@param a any
---@param b any
---@param path string
---@return string?
local function first_difference(a, b, path)
  if a == b then
    return nil
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return path
  end
  for k, v in pairs(a) do
    local d = first_difference(v, b[k], join(path, k))
    if d then
      return d
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return join(path, k)
    end
  end
  return nil
end

---Make `dst` hold what `src` holds, keeping every table `dst` already has in
---place (a consumer that stashed `cfg.get().picker` still sees the new values).
---@param dst table
---@param src table
local function assign_into(dst, src)
  for k in pairs(dst) do
    if src[k] == nil then
      dst[k] = nil
    end
  end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      assign_into(dst[k], v)
    else
      dst[k] = v
    end
  end
end

---@param defaults table
---@param spec? Lib.Config.Spec
---@return Lib.Config.Instance
function M.new(defaults, spec)
  spec = spec or {}
  assert(type(defaults) == "table", "config.new: defaults must be a table")
  local name = spec.name or "config"
  local layer_names = spec.layers or { SETUP }
  local rank = {}
  for i, layer_name in ipairs(layer_names) do
    rank[layer_name] = i
  end
  assert(rank[SETUP], 'config.new: spec.layers must contain "setup"')

  local rules = nil
  for path, rule in pairs(spec.merge or {}) do
    assert(
      rule == "replace" or rule == "entries",
      ("config.new: unknown merge rule %q for '%s'"):format(tostring(rule), path)
    )
    rules = rules or {}
    rules[path] = rule
  end

  local state = {
    layers = {}, ---@type table<string, {clean: table, issues: string[]}>
    resolve_issues = {}, ---@type string[]
    current = nil, ---@type table?
    live = nil, ---@type table?
    pristine = nil, ---@type table?
    schema = nil, ---@type table?
  }

  local function schema_spec()
    if state.schema then
      return state.schema
    end
    local exceptions = {}
    -- A section merged entry by entry holds keys the user chooses: open table.
    for path, rule in pairs(rules or {}) do
      if rule == "entries" then
        exceptions[path] = { "table" }
      end
    end
    for path, s in pairs(spec.schema or {}) do
      exceptions[path] = s
    end
    for key, s in pairs(spec.optional or {}) do
      exceptions[key] = s
    end
    state.schema = schema.infer(defaults, exceptions)
    return state.schema
  end

  ---Normalize and check one layer's options; returns the clean table and the problems.
  ---@param layer_name string
  ---@param data any
  ---@return {clean: table, issues: string[]}
  local function prepare(layer_name, data)
    local raw = {}
    local clean
    -- Opaque paths hold a table that is the user's own (a loaded module, an object): the copy
    -- below would turn it into a different table, so the original is kept and put back after the
    -- merge.
    local refs
    if spec.opaque and type(data) == "table" then
      for _, path in ipairs(spec.opaque) do
        local value = config.get(data, path)
        if type(value) == "table" then
          refs = refs or {}
          refs[path] = value
        end
      end
    end
    if type(data) ~= "table" then
      raw[1] = ("%s takes a table of options, got %s -- ignored"):format(
        layer_name == SETUP and "setup()" or ("layer '" .. layer_name .. "'"),
        schema.describe_got(data)
      )
      clean = {}
    else
      local copy = config.copy(data)
      if spec.normalize then
        local normalized = spec.normalize(copy, raw, layer_name)
        if type(normalized) == "table" then
          copy = normalized
        end
      end
      clean = schema.check_record(copy, schema_spec().fields, "", raw)
    end
    local tag = #layer_names > 1 and ("%s layer: "):format(layer_name) or ""
    local issues = {}
    for i, line in ipairs(raw) do
      issues[i] = tag .. line
    end
    return { clean = clean, issues = issues, refs = refs }
  end

  local built = false

  local function rebuild()
    local result = config.copy(defaults)
    for _, layer_name in ipairs(layer_names) do
      local l = state.layers[layer_name]
      if l then
        config.merge_into(result, l.clean, rules)
        -- only where the value passed the check and is still there
        for path, value in pairs(l.refs or {}) do
          if type(config.get(l.clean, path)) == "table" then
            set_path(result, path, value)
          end
        end
      end
    end
    local found = {}
    if spec.resolve then
      local resolved = spec.resolve(result, found)
      if type(resolved) == "table" then
        result = resolved
      end
    end

    local prev
    if spec.stable then
      state.live = state.live or {}
      prev = (built and spec.on_change) and config.copy(state.live) or nil
      assign_into(state.live, result)
      state.current = state.live
    else
      prev = state.current
      state.current = result
    end
    state.pristine = nil

    local previous = {}
    for _, line in ipairs(state.resolve_issues) do
      previous[line] = true
    end
    state.resolve_issues = found
    built = true

    if spec.notify then
      local fresh = {}
      for _, line in ipairs(found) do
        if not previous[line] then
          fresh[#fresh + 1] = line
        end
      end
      if #fresh > 0 then
        spec.notify("degraded config: " .. table.concat(fresh, "; "))
      end
    end
    if spec.on_change then
      spec.on_change(state.current, prev)
    end
  end

  local function current()
    if not built then
      rebuild()
    end
    return state.current
  end

  local self = { name = name } --[[@as Lib.Config.Instance]]

  ---Set (or with `nil` remove) one layer. Only this layer is checked again; the
  ---others keep what they passed before.
  ---@param layer_name string
  ---@param data table?
  function self.layer(layer_name, data)
    if not rank[layer_name] then
      error(("%s: unknown config layer '%s'"):format(name, tostring(layer_name)), 2)
    end
    local prepared = data ~= nil and prepare(layer_name, data) or nil
    state.layers[layer_name] = prepared
    rebuild()
    if prepared and #prepared.issues > 0 and spec.notify then
      spec.notify("ignored config: " .. table.concat(prepared.issues, "; "))
    end
  end

  ---@param opts table?
  function self.setup(opts)
    self.layer(SETUP, opts)
  end

  ---The path at which the stored table differs from what the layers produce, or nil.
  ---Only meaningful while the checking mode is on.
  ---@return string?
  function self.verify()
    local c = current()
    if not state.pristine then
      state.pristine = config.copy(c)
      return nil
    end
    return first_difference(c, state.pristine, "")
  end

  ---The stored config, or the value at the dot-separated `path`. The table is
  ---the live one: read it, do not write to it (`snapshot()` is the copy to write to).
  ---@param path? string
  ---@return any
  function self.get(path)
    local c = current()
    if config.is_checked() then
      local changed = self.verify()
      if changed then
        error(
          ("%s: the config table was written to at '%s'; write to cfg.snapshot() instead"):format(
            name,
            changed
          ),
          2
        )
      end
    end
    if path == nil then
      return c
    end
    return config.get(c, path)
  end

  ---@return table
  function self.snapshot()
    return config.copy(current())
  end

  ---The layer a value comes from: the highest one that names `path`, else "default".
  ---@param path string
  ---@return string?
  function self.source(path)
    for i = #layer_names, 1, -1 do
      local l = state.layers[layer_names[i]]
      if l and config.get(l.clean, path) ~= nil then
        return layer_names[i]
      end
    end
    if config.get(defaults, path) ~= nil then
      return "default"
    end
    return nil
  end

  ---What the layers dropped or degraded, then what `resolve` degraded.
  ---@return string[]
  function self.issues()
    local out = {}
    for _, layer_name in ipairs(layer_names) do
      local l = state.layers[layer_name]
      if l then
        append(out, l.issues)
      end
    end
    append(out, state.resolve_issues)
    return out
  end

  ---Drop every layer: the config is the defaults again.
  function self.reset()
    state.layers = {}
    rebuild()
  end

  return self
end

return M
