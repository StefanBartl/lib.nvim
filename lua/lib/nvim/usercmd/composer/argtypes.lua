---@module 'lib.nvim.usercmd.composer.argtypes'
--- Argument-type registry: each type carries BOTH validation and completion, so
--- a route's arg schema drives coercion (dispatch) and `<Tab>` (completion) from
--- one definition. Coercion reuses `lib.nvim.normalize.validators`; PATH/DIR/FILE
--- completion uses Neovim's own file completion so it is cross-platform.

local validators = require("lib.nvim.normalize.validators")
local is_dir = require("lib.nvim.fs.is_dir")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

---@type table<string, Lib.UserCmd.Composer.TypeDef>
local REGISTRY = {}

--- Filter a candidate list down to those starting with `arg_lead`.
---@param cands string[]
---@param arg_lead string
---@return string[]
local function prefix(cands, arg_lead)
  if arg_lead == "" then
    return cands
  end
  local out = {}
  for _, c in ipairs(cands) do
    if c:sub(1, #arg_lead) == arg_lead then
      out[#out + 1] = c
    end
  end
  return out
end
M.prefix = prefix

--- Register (or override) an argument type.
---@param name string
---@param def Lib.UserCmd.Composer.TypeDef
function M.register(name, def)
  assert(type(name) == "string" and name ~= "", "composer.argtypes: type name must be a non-empty string")
  assert(type(def) == "table" and type(def.validate) == "function",
    "composer.argtypes: type def needs a validate(raw, spec) function")
  REGISTRY[name] = def
end

--- Look up a type def; falls back to STRING for unknown names.
---@param name string|nil
---@return Lib.UserCmd.Composer.TypeDef
function M.get(name)
  return REGISTRY[name or "STRING"] or REGISTRY.STRING
end

--- Validate a raw token against an arg spec (honoring `enum` first).
---@param raw string
---@param spec Lib.UserCmd.Composer.ArgSpec
---@return boolean ok, any value, string|nil err
function M.validate(raw, spec)
  if spec.enum then
    -- Case-insensitive, normalizing to the canonical member — forgiving for
    -- hand-typed commands; completion still offers the exact-case members.
    local v = validators.to_enum(raw, spec.enum, true)
    if v == nil then
      return false, nil, ("expected one of %s"):format(table.concat(spec.enum, "|"))
    end
    return true, v, nil
  end
  return M.get(spec.type).validate(raw, spec)
end

--- Completion candidates for an arg spec (honoring `enum` first).
---@param arg_lead string
---@param spec Lib.UserCmd.Composer.ArgSpec
---@return string[]
function M.complete(arg_lead, spec)
  if spec.enum then
    return prefix(spec.enum, arg_lead)
  end
  local def = M.get(spec.type)
  if def.complete then
    return def.complete(arg_lead, spec)
  end
  return {}
end

-- ── Built-in types ──────────────────────────────────────────────────────────

M.register("STRING", {
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(arg_lead, spec)
    return prefix(spec.values or {}, arg_lead)
  end,
})

M.register("INT", {
  validate = function(raw)
    local n = validators.to_int(raw)
    if n == nil then
      return false, nil, ("'%s' is not an integer"):format(raw)
    end
    return true, n, nil
  end,
})

M.register("FLOAT", {
  validate = function(raw)
    local n = validators.to_float(raw)
    if n == nil then
      return false, nil, ("'%s' is not a number"):format(raw)
    end
    return true, n, nil
  end,
})

local BOOL_WORDS = { "true", "false", "on", "off", "yes", "no" }
M.register("BOOL", {
  validate = function(raw)
    local b = validators.to_bool(raw)
    if b == nil then
      return false, nil, ("'%s' is not a boolean (true/false/on/off/yes/no)"):format(raw)
    end
    return true, b, nil
  end,
  complete = function(arg_lead)
    return prefix(BOOL_WORDS, arg_lead)
  end,
})

-- Path family. Validation is intentionally soft for PATH (accept any token —
-- the handler decides), strict for DIR/FILE. All three expand `~`, `$VAR`,
-- `${VAR}` and `%VAR%` before validating/returning, so e.g. `root=$REPOS_DIR`
-- resolves instead of failing "not a directory" on the literal token.
M.register("PATH", {
  validate = function(raw)
    return true, expand_path(raw), nil
  end,
  complete = function(arg_lead)
    return vim.fn.getcompletion(arg_lead, "file")
  end,
})

M.register("DIR", {
  validate = function(raw)
    local expanded = expand_path(raw)
    if not is_dir(vim.fn.fnamemodify(expanded, ":p")) then
      return false, nil, ("'%s' is not a directory"):format(raw)
    end
    return true, expanded, nil
  end,
  complete = function(arg_lead)
    return vim.fn.getcompletion(arg_lead, "dir")
  end,
})

M.register("FILE", {
  validate = function(raw)
    local expanded = expand_path(raw)
    local p = vim.fn.fnamemodify(expanded, ":p")
    if vim.fn.filereadable(p) ~= 1 then
      return false, nil, ("'%s' is not a readable file"):format(raw)
    end
    return true, expanded, nil
  end,
  complete = function(arg_lead)
    return vim.fn.getcompletion(arg_lead, "file")
  end,
})

M.register("BUFFER", {
  validate = function(raw)
    local n = validators.to_int(raw)
    if n and vim.api.nvim_buf_is_valid(n) then
      return true, n, nil
    end
    -- fall back to a name match
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        local name = vim.api.nvim_buf_get_name(b)
        if name ~= "" and name:find(raw, 1, true) then
          return true, b, nil
        end
      end
    end
    return false, nil, ("no buffer matching '%s'"):format(raw)
  end,
  complete = function(arg_lead)
    local out = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        local name = vim.api.nvim_buf_get_name(b)
        if name ~= "" then
          out[#out + 1] = vim.fn.fnamemodify(name, ":t")
        end
      end
    end
    return prefix(out, arg_lead)
  end,
})

return M
