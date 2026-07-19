---@module 'lib.nvim.usercmd.composer.complete'
--- Completion engine. Derived entirely from the route tree: at the current slot
--- it offers subcommand literals, or — once literals are exhausted — the current
--- positional arg's completer. Adding a route or arg type extends `<Tab>` for
--- free.

local tree = require("lib.nvim.usercmd.composer.tree")
local argtypes = require("lib.nvim.usercmd.composer.argtypes")
local flags = require("lib.nvim.usercmd.composer.flags")
local kv = require("lib.nvim.usercmd.composer.kv")

local M = {}

--- Split a command line into the committed tokens the user has already entered
--- (excluding the command word itself and the in-progress `arg_lead`).
---@param cmd_line string
---@param arg_lead string
---@return string[]
function M.committed(cmd_line, arg_lead)
  -- Drop everything up to and including the first whitespace run: that first
  -- token is the command word (with any range/bang prefix, which contain no
  -- spaces), leaving only the argument portion.
  local rest = cmd_line:gsub("^%s*%S+%s*", "", 1)
  local toks = {}
  for tok in rest:gmatch("%S+") do
    toks[#toks + 1] = tok
  end
  -- When the user is mid-token (arg_lead ~= ""), the last split token IS that
  -- in-progress lead — it is not committed yet, so drop it.
  if arg_lead ~= "" and #toks > 0 and toks[#toks] == arg_lead then
    toks[#toks] = nil
  end
  return toks
end

--- Compute completion candidates.
---@param root Lib.UserCmd.Composer.Node
---@param arg_lead string
---@param cmd_line string
---@return string[]
function M.candidates(root, arg_lead, cmd_line)
  local committed = M.committed(cmd_line, arg_lead)
  local node, consumed = tree.walk(root, committed)
  local route = node.route

  -- Currently typing a --flag or a bare "-" (short-flag prefix) — only
  -- meaningful once a route is matched; a route with no declared flags falls
  -- through unchanged, see flags.lua.
  if (arg_lead:sub(1, 2) == "--" and arg_lead ~= "--") or arg_lead == "-" then
    return flags.candidates(route, arg_lead)
  end

  -- Already typing "key=..." for a declared kv key — kv tokens have no
  -- marker prefix, so this is the only unambiguous signal; delegate fully.
  if route and route.kv and kv.parse_kv_token(arg_lead) then
    local out = kv.candidates(route, arg_lead)
    if #out > 0 then
      return out
    end
    -- unrecognized key=... : fall through, it's just a positional value
  end

  -- Tokens sitting past the last matched literal are already-filled
  -- positional args of node.route — flag-/kv-shaped tokens among them don't
  -- occupy a positional slot, so strip them before counting.
  local tail = {}
  for i = consumed + 1, #committed do
    tail[#tail + 1] = committed[i]
  end
  local clean = route and flags.strip(route, tail) or tail
  clean = route and kv.strip(route, clean) or clean
  local filled = #clean

  local out = {}

  -- Choosing a subcommand: at a node that has children and no positional args
  -- have been started yet.
  if next(node.children) ~= nil and filled == 0 then
    out = argtypes.prefix(tree.child_keys(node), arg_lead)
  elseif route and route.args then
    -- Otherwise we are completing a positional argument of the matched route.
    local spec = route.args[filled + 1]
    if spec then
      out = argtypes.complete(arg_lead, spec)
    end
  end

  -- kv tokens have no marker prefix, so "key=" prefixes are always a valid
  -- alternative alongside whatever else applies at this slot.
  if route and route.kv then
    for _, c in ipairs(kv.candidates(route, arg_lead)) do
      out[#out + 1] = c
    end
  end

  return out
end

--- Build the `complete` callback nvim expects: (arg_lead, cmd_line, cursor_pos).
---@param root_provider fun(): Lib.UserCmd.Composer.Node
---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
function M.make(root_provider)
  return function(arg_lead, cmd_line, _)
    local ok, out = pcall(M.candidates, root_provider(), arg_lead, cmd_line)
    if not ok then
      return {}
    end
    return out
  end
end

return M
