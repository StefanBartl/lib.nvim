---@module 'lib.nvim.usercmd.composer.parse'
--- Dispatch: walk the tree with the invoked tokens, bind + coerce positional
--- args, build the handler context, and call `run`. Pure-ish: takes an injected
--- notifier so it stays headlessly testable.

local tree = require("lib.nvim.usercmd.composer.tree")
local argtypes = require("lib.nvim.usercmd.composer.argtypes")
local format = require("lib.nvim.usercmd.composer.format")
local flags = require("lib.nvim.usercmd.composer.flags")
local kv = require("lib.nvim.usercmd.composer.kv")

local M = {}

--- Resolve a route's `run` (function, or a module path returning a callable /
--- `{ run = fn }`) to a callable. Lazy `require` keeps feature modules unloaded
--- until their subcommand actually fires.
---
--- The second return value is nil whenever `run` was already a function (there
--- is nothing to fail); for a string path it carries the real reason a lookup
--- failed — a `require` error, or the loaded module having the wrong shape —
--- so callers that want to report *why* (dispatch's error message, check.lua's
--- pre-flight validation) don't have to redo the require themselves.
---@param run fun(ctx)|string
---@return fun(ctx)|nil fn
---@return string|nil err
function M.resolve_run(run)
  if type(run) == "function" then
    return run, nil
  end
  if type(run) == "string" then
    local ok, mod = pcall(require, run)
    if not ok then
      return nil, tostring(mod)
    end
    if type(mod) == "function" then
      return mod, nil
    end
    if type(mod) == "table" and type(mod.run) == "function" then
      return mod.run, nil
    end
    return nil, ("module '%s' loaded but is not callable and has no .run"):format(run)
  end
  return nil, nil
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

  -- Bare `:Verb` (no tokens): an explicit spec.default always wins. Otherwise,
  -- if a `path = {}` root route is registered, fall through to the normal
  -- tree-walk/dispatch pipeline below -- tree.walk(root, {}) resolves to the
  -- root node itself, so a root route naturally handles bare invocation the
  -- same way it handles any other, enforcing its own required args/flags/kv
  -- instead of being silently skipped. Only when neither exists do we show
  -- the auto-generated usage listing.
  if #fargs == 0 then
    if spec.default then
      return spec.default(M.build_ctx({}, {}, {}, {}, {}, {}, opts))
    end
    if not root.route then
      notify.info(M.usage(cmd_name, root))
      return
    end
  end

  local node, consumed = tree.walk(root, fargs)

  if not node.route then
    -- Either the first unmatched token is a bad subcommand, or a valid group
    -- prefix was given without a leaf. Point at the offending token.
    local bad = fargs[consumed + 1]
    if bad then
      notify.error(("unknown subcommand '%s'.\n%s"):format(bad, M.usage(cmd_name, root)))
    else
      notify.error(
        ("'%s' needs a subcommand.\n%s"):format(
          table.concat({ cmd_name, unpack(fargs, 1, consumed) }, " "),
          M.usage(cmd_name, root)
        )
      )
    end
    return
  end

  local route = node.route
  local rest = {}
  for i = consumed + 1, #fargs do
    rest[#rest + 1] = fargs[i]
  end

  local after_flags, flag_values, ferr = flags.split(route, rest)
  if ferr then
    notify.error(("%s\n  %s"):format(ferr, format.invocation(cmd_name, route)))
    return
  end

  local positionals, kv_values, kverr = kv.split(route, after_flags)
  if kverr then
    notify.error(("%s\n  %s"):format(kverr, format.invocation(cmd_name, route)))
    return
  end

  local args, pos, leftover, err = bind_args(route, positionals)
  if err then
    notify.error(("%s\n  %s"):format(err, format.invocation(cmd_name, route)))
    return
  end

  local run, run_err = M.resolve_run(route.run)
  if not run then
    local msg = ("route '%s' has no runnable handler"):format(table.concat(route.path, " "))
    if run_err then
      msg = msg .. ": " .. run_err
    end
    notify.error(msg)
    return
  end

  return run(M.build_ctx(args, pos, flag_values, kv_values, leftover, route.path, opts))
end

--- Best-effort Visual-mode/column info for the range that was just given.
---
--- `vim.fn.visualmode()`/the `'<`/`'>` marks are NOT proof that the CURRENT
--- range invocation came from a Visual selection just now — they persist
--- from whichever Visual selection was last active, so a manually typed
--- `:5,10Verb` after an unrelated earlier visual selection would still
--- report that stale mode/columns. There is no reliable way in Neovim's API
--- to distinguish "this range came from leaving Visual mode" from "this
--- range happens to share lines with an old Visual selection" — callers
--- that need certainty should not treat `mode` as a guarantee.
---@return string|nil mode "v"|"V"|"\22", or nil if Visual mode was never used this session
---@return integer|nil col1 byte column of the '< mark
---@return integer|nil col2 byte column of the '> mark
local function visual_info()
  local mode = vim.fn.visualmode()
  if mode == "" then
    return nil, nil, nil
  end
  return mode, vim.fn.getpos("'<")[3], vim.fn.getpos("'>")[3]
end

--- Assemble the handler context.
---@return Lib.UserCmd.Composer.Ctx
function M.build_ctx(args, pos, flag_values, kv_values, rest, path, opts)
  local mode, col1, col2
  if opts.range and opts.range > 0 then
    mode, col1, col2 = visual_info()
  end

  return {
    args = args,
    pos = pos,
    flags = flag_values or {},
    kv = kv_values or {},
    rest = rest,
    path = path,
    bang = opts.bang or false,
    range = {
      line1 = opts.line1 or 0,
      line2 = opts.line2 or 0,
      count = opts.count or -1,
      range = opts.range or 0,
      mode = mode,
      col1 = col1,
      col2 = col2,
    },
    raw = opts,
  }
end

return M
