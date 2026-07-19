---@module 'lib.nvim.usercmd.composer.format'
--- Shared rendering of arg schemas into human-readable tokens. Used by both the
--- usage/error messages (parse.lua) and the Markdown docs (docgen.lua) so a
--- route reads the same everywhere.

local M = {}

--- Render one arg spec as a placeholder token, e.g. `{name}`, `{name:INT}`,
--- optionals wrapped in `[ ]`.
---@param spec Lib.UserCmd.Composer.ArgSpec
---@return string
function M.arg_token(spec)
  local inner
  if spec.enum then
    inner = "{" .. spec.name .. "}"
  elseif spec.type and spec.type ~= "STRING" then
    inner = "{" .. spec.name .. ":" .. spec.type .. "}"
  else
    inner = "{" .. spec.name .. "}"
  end
  if spec.optional then
    return "[" .. inner .. "]"
  end
  return inner
end

--- Render one flag spec as a placeholder token, e.g. `[--dry]`,
--- `[--type=<value>]`, `[--engine=<value>]` — always optional (a flag is
--- never required), repeatable ones get a trailing `...`.
---@param spec Lib.UserCmd.Composer.FlagSpec
---@return string
function M.flag_token(spec)
  if spec.bool then
    return "[--" .. spec.name .. "]"
  end
  local value = spec.enum and "<" .. table.concat(spec.enum, "|") .. ">" or "<value>"
  local inner = "--" .. spec.name .. "=" .. value
  return "[" .. inner .. (spec.repeatable and " ..." or "") .. "]"
end

--- Full invocation string for a route, e.g.
--- `:Replace surround {kind} {target} [--dry] [--type=<value>]`.
---@param cmd_name string
---@param route Lib.UserCmd.Composer.Route
---@return string
function M.invocation(cmd_name, route)
  local parts = { ":" .. cmd_name }
  for _, tok in ipairs(route.path) do
    parts[#parts + 1] = tok
  end
  for _, arg in ipairs(route.args or {}) do
    parts[#parts + 1] = M.arg_token(arg)
  end
  for _, flag in ipairs(route.flags or {}) do
    parts[#parts + 1] = M.flag_token(flag)
  end
  return table.concat(parts, " ")
end

--- Enum notes for a route's args (each `{name} ∈ a | b | c`), or empty list.
---@param route Lib.UserCmd.Composer.Route
---@return string[]
function M.enum_notes(route)
  local notes = {}
  for _, arg in ipairs(route.args or {}) do
    if arg.enum then
      notes[#notes + 1] = ("`{%s}` ∈ `%s`"):format(arg.name, table.concat(arg.enum, " | "))
    end
  end
  for _, flag in ipairs(route.flags or {}) do
    if flag.enum then
      notes[#notes + 1] = ("`--%s` ∈ `%s`"):format(flag.name, table.concat(flag.enum, " | "))
    end
  end
  return notes
end

return M
