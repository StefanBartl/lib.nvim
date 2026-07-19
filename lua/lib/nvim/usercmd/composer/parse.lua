---@module 'lib.nvim.usercmd.composer.parse'
--- Dispatch: walk the tree with the invoked tokens, bind + coerce positional
--- args, build the handler context, and call `run`. Pure-ish: takes an injected
--- notifier so it stays headlessly testable.

local tree = require("lib.nvim.usercmd.composer.tree")
local argtypes = require("lib.nvim.usercmd.composer.argtypes")
local format = require("lib.nvim.usercmd.composer.format")
local flags = require("lib.nvim.usercmd.composer.flags")

local M = {}

--- Resolve a route's `run` (function, or a module path returning a callable /
--- `{ run = fn }`) to a callable. Lazy `require` keeps feature modules unloaded
--- until their subcommand actually fires.
---@param run fun(ctx)|string
---@return fun(ctx)|nil
function M.resolve_run(run)
  if type(run) == "function" then
    return run
  end
  if type(run) == "string" then
    local ok, mod = pcall(require, run)
    if not ok then
      return nil
    end
    if type(mod) == "function" then
      return mod
    end
    if type(mod) == "table" and type(mod.run) == "function" then
      return mod.run
    end
  end
  return nil
end

--- Auto-generated usage block for a verb (all invocations, one per line).
---@param cmd_name string
---@param root Lib.UserCmd.Composer.Node
---@return string
function M.usage(cmd_name, root)
  local lines = { ("Usage: :%s <subcommand> …"):format(cmd_name) }
  tree.each_route(root, function(route)
    local line = "  " .. format.invocation(cmd_name, route)
    if route.desc and route.desc ~= "" then
      line = line .. "  — " .. route.desc
    end
    lines[#lines + 1] = line
  end)
  return table.concat(lines, "\n")
end

--- Bind leftover tokens to a route's arg schema, coercing each.
---@param route Lib.UserCmd.Composer.Route
---@param rest string[]
---@return table<string, any>|nil args, any[]|nil pos, string[]|nil leftover, string|nil err
local function bind_args(route, rest)
  local specs = route.args or {}
  local args, pos = {}, {}
  local ri = 1
  for _, spec in ipairs(specs) do
    local raw = rest[ri]
    if raw == nil then
      if spec.optional then
        if spec.default ~= nil then
          args[spec.name] = spec.default
          pos[#pos + 1] = spec.default
        end
        -- omitted optional with no default: leave unset
      else
        return nil, nil, nil, ("missing required argument %s"):format(format.arg_token(spec))
      end
    else
      local ok, value, verr = argtypes.validate(raw, spec)
      if not ok then
        return nil, nil, nil, ("argument %s: %s"):format(format.arg_token(spec), verr)
      end
      args[spec.name] = value
      pos[#pos + 1] = value
      ri = ri + 1
    end
  end
  -- leftover tokens beyond the declared schema
  local leftover = {}
  for i = ri, #rest do
    leftover[#leftover + 1] = rest[i]
  end
  return args, pos, leftover, nil
end

--- Handle one `:Verb …` invocation.
---@param cmd_name string
---@param spec Lib.UserCmd.Composer.Spec
---@param root Lib.UserCmd.Composer.Node
---@param opts Lib.UserCommand.Args   # nvim callback args
---@param notify { error: fun(msg), info: fun(msg) }
function M.dispatch(cmd_name, spec, root, opts, notify)
  local fargs = opts.fargs or {}

  -- Bare `:Verb` → default handler (or usage).
  if #fargs == 0 then
    if spec.default then
      return spec.default(M.build_ctx({}, {}, {}, {}, {}, opts))
    end
    notify.info(M.usage(cmd_name, root))
    return
  end

  local node, consumed = tree.walk(root, fargs)

  if not node.route then
    -- Either the first unmatched token is a bad subcommand, or a valid group
    -- prefix was given without a leaf. Point at the offending token.
    local bad = fargs[consumed + 1]
    if bad then
      notify.error(("unknown subcommand '%s'.\n%s"):format(bad, M.usage(cmd_name, root)))
    else
      notify.error(("'%s' needs a subcommand.\n%s"):format(
        table.concat({ cmd_name, unpack(fargs, 1, consumed) }, " "), M.usage(cmd_name, root)))
    end
    return
  end

  local route = node.route
  local rest = {}
  for i = consumed + 1, #fargs do
    rest[#rest + 1] = fargs[i]
  end

  local positionals, flag_values, ferr = flags.split(route, rest)
  if ferr then
    notify.error(("%s\n  %s"):format(ferr, format.invocation(cmd_name, route)))
    return
  end

  local args, pos, leftover, err = bind_args(route, positionals)
  if err then
    notify.error(("%s\n  %s"):format(err, format.invocation(cmd_name, route)))
    return
  end

  local run = M.resolve_run(route.run)
  if not run then
    notify.error(("route '%s' has no runnable handler"):format(table.concat(route.path, " ")))
    return
  end

  return run(M.build_ctx(args, pos, flag_values, leftover, route.path, opts))
end

--- Assemble the handler context.
---@return Lib.UserCmd.Composer.Ctx
function M.build_ctx(args, pos, flag_values, rest, path, opts)
  return {
    args = args,
    pos = pos,
    flags = flag_values or {},
    rest = rest,
    path = path,
    bang = opts.bang or false,
    range = {
      line1 = opts.line1 or 0,
      line2 = opts.line2 or 0,
      count = opts.count or -1,
      range = opts.range or 0,
    },
    raw = opts,
  }
end

return M
