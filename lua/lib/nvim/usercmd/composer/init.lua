---@module 'lib.nvim.usercmd.composer'
--- Compose a route spec into ONE Neovim user command with subcommands,
--- `<Tab>` completion, and Markdown docs — all read from the same tree.
---
--- Turns the `:VerbFeatureA` / `:VerbFeatureB` anti-pattern into
--- `:Verb feature-a` / `:Verb feature-b` with completion and validation for
--- free. See docs/ROADMAP/usrcmd_builder.md for the full design.
---
---   local composer = require("lib.nvim.usercmd.composer")
---
---   composer.verb("Replace", {
---     desc    = "Text replacement operations",
---     default = function(ctx) require("replacer").replace_prompt() end,
---     routes  = {
---       { path = { "buffer" }, desc = "Replace within the current buffer",
---         run = function(ctx) require("replacer").buffer() end },
---       { path = { "surround" },
---         args = {
---           { name = "kind",   type = "STRING", enum = { "quote", "paren", "brace" } },
---           { name = "target", type = "STRING" },
---         },
---         desc = "Wrap TARGET with KIND surroundings",
---         run  = function(ctx) require("replacer").surround(ctx.args.kind, ctx.args.target) end },
---     },
---   })
---
---   composer.document()   -- write docs/BINDINGS/Usercmds.md for every verb

require("lib.nvim.usercmd.composer.@types")

local usercmd = require("lib.nvim.usercmd")
local notify = require("lib.nvim.notify").create("[lib.nvim.usercmd.composer]")
local tree = require("lib.nvim.usercmd.composer.tree")
local parse = require("lib.nvim.usercmd.composer.parse")
local complete = require("lib.nvim.usercmd.composer.complete")
local argtypes = require("lib.nvim.usercmd.composer.argtypes")
local docgen = require("lib.nvim.usercmd.composer.docgen")
local registry = require("lib.nvim.usercmd.composer.registry")

local M = {}

-- Defer user-facing messages so a bad-argument report surfaces as a clean
-- notification instead of a raw "Vim:… command error" traceback (the same
-- technique replacer.nvim uses). parse.lua stays synchronous/testable via its
-- injected notifier; only production registration wraps it.
local deferred = {
  error = function(msg) vim.schedule(function() notify.error(msg) end) end,
  info = function(msg) vim.schedule(function() notify.info(msg) end) end,
}

--- Whether the command should accept the bang form: explicit spec.bang wins,
--- otherwise true iff any route opts into it.
---@param spec Lib.UserCmd.Composer.Spec
---@return boolean
local function wants_bang(spec)
  if spec.bang ~= nil then
    return spec.bang and true or false
  end
  for _, route in ipairs(spec.routes or {}) do
    if route.bang then
      return true
    end
  end
  return false
end

--- Whether the command should accept a range: explicit spec.range wins,
--- otherwise the first route to opt in wins (nvim_create_user_command's
--- `range` is a single command-level option, not per-route — a mix of
--- boolean `true` and an explicit count across routes can't both apply, so
--- the first non-nil route.range found is used as-is).
---@param spec Lib.UserCmd.Composer.Spec
---@return boolean|integer|nil
local function wants_range(spec)
  if spec.range ~= nil then
    return spec.range
  end
  for _, route in ipairs(spec.routes or {}) do
    if route.range ~= nil then
      return route.range
    end
  end
  return nil
end

--- Whether the command should accept a `:N Verb` count prefix: explicit
--- spec.count wins, otherwise the first route to opt in wins (same
--- single-command-level-option reasoning as wants_range — nvim_create_user_command
--- has one `count`, not one per route).
---@param spec Lib.UserCmd.Composer.Spec
---@return integer|nil
local function wants_count(spec)
  if spec.count ~= nil then
    return spec.count
  end
  for _, route in ipairs(spec.routes or {}) do
    if route.count ~= nil then
      return route.count
    end
  end
  return nil
end

--- Build a handle for a registered verb.
---@param name string
---@param spec Lib.UserCmd.Composer.Spec
---@param root Lib.UserCmd.Composer.Node
---@return Lib.UserCmd.Composer.Handle
local function make_handle(name, spec, root)
  local handle = {}

  function handle:name()
    return name
  end

  function handle:spec()
    return spec
  end

  --- Write docs for THIS verb only.
  ---@param path? string
  ---@return boolean ok, string|nil err
  function handle:document(path)
    return docgen.write(
      { { name = name, spec = spec, root = root } },
      path or registry.docs.path,
      registry.docs.mode
    )
  end

  return handle
end

--- Build the route tree, register the user command, record the verb.
---@param name string
---@param spec Lib.UserCmd.Composer.Spec
---@return Lib.UserCmd.Composer.Handle
local function register(name, spec)
  assert(type(name) == "string" and name ~= "", "composer.verb: name must be a non-empty string")
  spec.routes = spec.routes or {}

  local root = tree.build(spec.routes)

  local handler = function(opts)
    return parse.dispatch(name, spec, root, opts, deferred)
  end

  usercmd.create(name, handler, {
    nargs = "*",
    bang = wants_bang(spec),
    range = wants_range(spec),
    count = wants_count(spec),
    buffer = spec.buffer,
    complete = complete.make(function()
      return root
    end),
    desc = spec.desc or ("composer verb :" .. name),
  })

  local handle = make_handle(name, spec, root)
  registry.add(name, handle)
  return handle
end

--- Fluent builder — accumulates a spec, registers on `:build()`.
---@param name string
---@return table
local function make_builder(name)
  ---@type Lib.UserCmd.Composer.Spec
  local spec = { routes = {} }
  local builder = {}

  function builder:desc(s)
    spec.desc = s
    return self
  end

  function builder:default(fn)
    spec.default = fn
    return self
  end

  function builder:bang(v)
    spec.bang = (v ~= false)
    return self
  end

  function builder:range(v)
    spec.range = (v == nil) and true or v
    return self
  end

  --- Accept a :N Verb count prefix, defaulting to `v` (default 0) when omitted.
  function builder:count(v)
    spec.count = (v == nil) and 0 or v
    return self
  end

  --- Register buffer-locally: true = current buffer, or an explicit bufnr.
  function builder:buffer(v)
    spec.buffer = (v == nil) and true or v
    return self
  end

  --- Add a route. `path` may be a string ("surround quote") or a token array.
  ---@param path string|string[]
  ---@param opts { args?: table, run: any, desc?: string, bang?: boolean, range?: boolean|integer }
  function builder:route(path, opts)
    local tokens = path
    if type(path) == "string" then
      tokens = {}
      for tok in path:gmatch("%S+") do
        tokens[#tokens + 1] = tok
      end
    end
    spec.routes[#spec.routes + 1] = vim.tbl_extend("force", { path = tokens }, opts or {})
    return self
  end

  function builder:build()
    return register(name, spec)
  end

  return builder
end

--- Create a verb. With a `spec` it registers immediately and returns a handle;
--- without one it returns a fluent builder (call `:build()` to register).
---@param name string
---@param spec? Lib.UserCmd.Composer.Spec
---@return Lib.UserCmd.Composer.Handle|table
function M.verb(name, spec)
  if spec ~= nil then
    return register(name, spec)
  end
  return make_builder(name)
end

--- Write docs for EVERY verb registered in this process.
---@param path? string
---@return boolean ok, string|nil err
function M.document(path)
  local entries = {}
  for _, handle in ipairs(registry.all()) do
    entries[#entries + 1] = {
      name = handle:name(),
      spec = handle:spec(),
      root = tree.build(handle:spec().routes or {}),
    }
  end
  if #entries == 0 then
    return false, "composer.document: no verbs registered"
  end
  return docgen.write(entries, path or registry.docs.path, registry.docs.mode)
end

--- Configure docs defaults (output path + write mode).
---@param opts? Lib.UserCmd.Composer.SetupOpts
function M.setup(opts)
  opts = opts or {}
  registry.configure(opts.docs)
end

--- Register a custom argument type (validation + completion).
---@param name string
---@param def Lib.UserCmd.Composer.TypeDef
function M.register_type(name, def)
  argtypes.register(name, def)
end

--- The name→handle registry (a copy).
---@return table<string, Lib.UserCmd.Composer.Handle>
function M.registry()
  return registry.map()
end

---@type Lib.UserCmd.Composer
return M
