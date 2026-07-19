---@module 'lib.nvim.usercmd.composer.kv'
--- key=value (no dashes) parsing, shared by dispatch and completion — the
--- same one-declaration-two-readers principle as flags.lua. Opt-in per route
--- via Route.kv. Unlike -- flags, an unrecognized key=value-shaped token
--- (key not declared) is left as an ordinary positional rather than an
--- error — "=" shows up in too many legitimate positional values (URLs, env
--- assignments passed through, ...) to treat every match as intentional.

local argtypes = require("lib.nvim.usercmd.composer.argtypes")

local M = {}

---@param route Lib.UserCmd.Composer.Route
---@param key string
---@return Lib.UserCmd.Composer.KvSpec|nil
local function find_spec(route, key)
  for _, kv in ipairs(route.kv or {}) do
    if kv.key == key then
      return kv
    end
  end
  return nil
end
M.find_spec = find_spec

--- Parse a "key=value"-shaped token into (key, value); nil if the token
--- doesn't have the shape at all (no "=", or "=" is the first character).
---@param tok string
---@return string|nil key, string|nil value
local function parse_kv_token(tok)
  local eq = tok:find("=", 1, true)
  if not eq or eq == 1 then
    return nil, nil
  end
  return tok:sub(1, eq - 1), tok:sub(eq + 1)
end
M.parse_kv_token = parse_kv_token

--- Split `tokens` into (positionals, kv-values). A "key=value" token whose
--- key is declared in route.kv is consumed and coerced; anything else
--- (including a key=value-shaped token with an undeclared key) passes
--- through unchanged as an ordinary positional.
---@param route Lib.UserCmd.Composer.Route
---@param tokens string[]
---@return string[]|nil positionals
---@return table<string, any>|nil values
---@return string|nil err
function M.split(route, tokens)
  if not route.kv or #route.kv == 0 then
    return tokens, {}, nil
  end

  local positionals, values = {}, {}
  for _, tok in ipairs(tokens) do
    local key, raw = parse_kv_token(tok)
    local spec = key and find_spec(route, key)
    if spec then
      local ok, value, verr = argtypes.validate(raw, spec)
      if not ok then
        return nil, nil, ("%s=…: %s"):format(key, verr)
      end
      values[key] = value
    else
      positionals[#positionals + 1] = tok
    end
  end

  for _, spec in ipairs(route.kv) do
    if values[spec.key] == nil and spec.default ~= nil then
      values[spec.key] = spec.default
    end
  end

  return positionals, values, nil
end

--- Lenient, non-validating strip of declared key=value tokens — used by
--- completion to compute which positional slot is being typed. Never errors.
---@param route Lib.UserCmd.Composer.Route
---@param tokens string[]
---@return string[]
function M.strip(route, tokens)
  if not route.kv or #route.kv == 0 then
    return tokens
  end
  local out = {}
  for _, tok in ipairs(tokens) do
    local key = parse_kv_token(tok)
    if not (key and find_spec(route, key)) then
      out[#out + 1] = tok
    end
  end
  return out
end

--- Completion candidates for kv pairs. Two shapes: `arg_lead` already
--- contains "key=..." for a declared key -> that key's value completer;
--- otherwise -> "key=" prefixes for every declared key matching what's typed
--- so far (kv tokens have no marker prefix, so this is meant to be merged
--- alongside whatever else is valid at this slot, not used exclusively).
---@param route Lib.UserCmd.Composer.Route|nil
---@param arg_lead string
---@return string[]
function M.candidates(route, arg_lead)
  if not route or not route.kv or #route.kv == 0 then
    return {}
  end

  local key, value_lead = parse_kv_token(arg_lead)
  if key then
    local spec = find_spec(route, key)
    if not spec then
      return {}
    end
    local out = {}
    for _, v in ipairs(argtypes.complete(value_lead, spec)) do
      out[#out + 1] = ("%s=%s"):format(key, v)
    end
    return out
  end

  local out = {}
  for _, kv in ipairs(route.kv) do
    if kv.key:sub(1, #arg_lead) == arg_lead then
      out[#out + 1] = kv.key .. "="
    end
  end
  return out
end

return M
