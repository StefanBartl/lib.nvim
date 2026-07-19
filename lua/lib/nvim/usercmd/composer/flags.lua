---@module 'lib.nvim.usercmd.composer.flags'
--- --flag / --flag=value parsing, shared by dispatch and completion so a
--- route's flags stay one declaration read by both (same principle as the
--- route tree itself). Modeled on replacer.nvim's BOOL_FLAGS/VALUE_FLAGS
--- tokenizer split (see docs/ROADMAP/usrcmd_builder.md Phase 6).
---
--- Strictly opt-in per route: every function here is a no-op passthrough when
--- `route.flags` is nil/empty, so a route that never declares flags keeps its
--- pre-Phase-6 behavior exactly — a leading "--" in one of its positional
--- values is not treated specially.

local argtypes = require("lib.nvim.usercmd.composer.argtypes")

local M = {}

---@param route Lib.UserCmd.Composer.Route
---@param name string
---@return Lib.UserCmd.Composer.FlagSpec|nil
local function find_spec(route, name)
  for _, f in ipairs(route.flags or {}) do
    if f.name == name then
      return f
    end
  end
  return nil
end
M.find_spec = find_spec

--- A flag-shaped token (`--name` or `--name=value`) — excludes the bare `--`
--- stop sentinel, which is a token of its own.
---@param tok string
---@return boolean
local function is_flag_token(tok)
  return tok:sub(1, 2) == "--" and tok ~= "--"
end
M.is_flag_token = is_flag_token

--- Split `tokens` into (positionals, flags), honoring a literal `--` as "stop
--- parsing flags — everything after is positional" (mirrors replacer.nvim's
--- `flags_done` sentinel). An undeclared `--name` is a hard error, same
--- fail-loud stance as a bad positional arg — silently downgrading it to a
--- positional would surprise a caller who mistyped a flag name.
---@param route Lib.UserCmd.Composer.Route
---@param tokens string[]
---@return string[]|nil positionals
---@return table<string, any>|nil flags
---@return string|nil err
function M.split(route, tokens)
  if not route.flags or #route.flags == 0 then
    return tokens, {}, nil
  end

  local positionals, flags = {}, {}
  local stopped = false
  local i = 1
  while i <= #tokens do
    local tok = tokens[i]
    if not stopped and tok == "--" then
      stopped = true
    elseif not stopped and is_flag_token(tok) then
      local body = tok:sub(3)
      local eq = body:find("=", 1, true)
      local name = eq and body:sub(1, eq - 1) or body
      local inline_val = eq and body:sub(eq + 1) or nil

      local spec = find_spec(route, name)
      if not spec then
        return nil, nil, ("unknown flag '--%s'"):format(name)
      end

      if spec.bool then
        if inline_val then
          return nil, nil, ("flag '--%s' takes no value"):format(name)
        end
        flags[name] = true
      else
        local raw = inline_val
        if raw == nil then
          local nxt = tokens[i + 1]
          if nxt == nil or nxt == "--" or is_flag_token(nxt) then
            return nil, nil, ("flag '--%s' requires a value"):format(name)
          end
          raw = nxt
          i = i + 1
        end
        local ok, value, verr = argtypes.validate(raw, spec)
        if not ok then
          return nil, nil, ("flag '--%s': %s"):format(name, verr)
        end
        if spec.repeatable then
          flags[name] = flags[name] or {}
          table.insert(flags[name], value)
        else
          flags[name] = value
        end
      end
    else
      positionals[#positionals + 1] = tok
    end
    i = i + 1
  end

  for _, spec in ipairs(route.flags) do
    if flags[spec.name] == nil and spec.default ~= nil then
      flags[spec.name] = spec.default
    end
  end

  return positionals, flags, nil
end

--- Lenient, non-validating strip of flag-shaped tokens (and the value token a
--- declared non-bool flag consumes) — used by completion to compute which
--- positional slot is being typed without miscounting a `--flag value` pair.
--- Never errors: an unknown or malformed flag while mid-typing just isn't
--- stripped (best-effort), rather than blowing up completion.
---@param route Lib.UserCmd.Composer.Route
---@param tokens string[]
---@return string[]
function M.strip(route, tokens)
  if not route.flags or #route.flags == 0 then
    return tokens
  end

  local out = {}
  local stopped = false
  local i = 1
  while i <= #tokens do
    local tok = tokens[i]
    if not stopped and tok == "--" then
      stopped = true
    elseif not stopped and is_flag_token(tok) then
      local body = tok:sub(3)
      if not body:find("=", 1, true) then
        local spec = find_spec(route, body)
        if spec and not spec.bool then
          i = i + 1 -- also skip the value token
        end
      end
    else
      out[#out + 1] = tok
    end
    i = i + 1
  end
  return out
end

--- Completion candidates for a flag-shaped `arg_lead` (route must declare
--- flags; returns {} otherwise).
---@param route Lib.UserCmd.Composer.Route|nil
---@param arg_lead string
---@return string[]
function M.candidates(route, arg_lead)
  if not route or not route.flags or #route.flags == 0 then
    return {}
  end

  local eq = arg_lead:find("=", 1, true)
  if eq then
    local name = arg_lead:sub(3, eq - 1)
    local value_lead = arg_lead:sub(eq + 1)
    local spec = find_spec(route, name)
    if not spec or spec.bool then
      return {}
    end
    local out = {}
    for _, v in ipairs(argtypes.complete(value_lead, spec)) do
      out[#out + 1] = ("--%s=%s"):format(name, v)
    end
    return out
  end

  local prefix = arg_lead:sub(3)
  local out = {}
  for _, f in ipairs(route.flags) do
    if f.name:sub(1, #prefix) == prefix then
      out[#out + 1] = "--" .. f.name
    end
  end
  return out
end

return M
