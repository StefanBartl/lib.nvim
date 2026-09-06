---@module 'lib.nvim.bindings.keymap.set'
--- The single-keymap wrapper: `vim.keymap.set` with defaults, optional buffer
--- scoping, and deferred debug diagnostics for invalid argument types. Reached
--- as `keymap(...)` (the module is callable) or `keymap.set(...)`;
--- `keymap.register()` builds on this.

local notify = require("lib.nvim.notify").create("[lib.nvim.bindings.keymap]")

---@internal
local function notify_caller(flags, modes, lhs, rhs, opts)
  -- Stack layout:
  -- 1: debug.getinfo
  -- 2: notify_caller
  -- 3: lib.nvim.bindings.keymap wrapper
  -- 4: actual user call site
  local info = debug.getinfo(4, "Slfn")

  local caller = "<unknown>"
  if info then
    caller = string.format(
      "%s:%d (%s)",
      info.source or "?",
      info.currentline or -1,
      info.name or "<anonymous>"
    )
  end

  ---@type string[]
  local errors = {}

  if flags.modes then
    errors[#errors + 1] =
      string.format("invalid modes (expected string|string[], got %s)", type(modes))
  end

  if flags.lhs then
    errors[#errors + 1] = string.format("invalid lhs (expected string, got %s)", type(lhs))
  end

  if flags.rhs then
    errors[#errors + 1] =
      string.format("invalid rhs (expected function or string, got %s)", type(rhs))
  end

  if flags.buffer then
    errors[#errors + 1] = string.format(
      "invalid buffer option (expected boolean|integer, got %s)",
      type(opts and opts.buffer)
    )
  end

  notify.error(
    string.format(
      "[lib.nvim.bindings.keymap] argument validation failed:\n %s\n caller: %s",
      table.concat(errors, "\n "),
      caller
    )
  )
end

---Convenience wrapper for vim.keymap.set with defaults.
---
---Records what it bound, unless `opts.record` is `false`. `registry.register()`
---passes that, because it writes its own richer entry -- without it every
---registered action would be listed twice.
---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts Lib.Map.Opts|nil
---@param desc string?
---@type Lib.Map
return function(modes, lhs, rhs, opts, desc)
  -- A COPY, never the caller's own table. Everything below writes into
  -- `opts` -- `desc`, `noremap`, `silent`, the normalised `buffer` -- and
  -- writing that back into the table the caller handed over means one options
  -- table reused across several calls silently carries the previous binding's
  -- `desc` into the next one. documentation.nvim hit exactly that: every key
  -- in its browser showed up in which-key labelled "close", and it had to
  -- build a fresh table per binding to work around it.
  opts = opts and vim.tbl_extend("force", {}, opts) or {}

  ---@type Lib.Map.ErrorFlags
  local flags = {
    modes = not (type(modes) == "string" or type(modes) == "table"),
    lhs = type(lhs) ~= "string",
    rhs = type(rhs) ~= "function" and type(rhs) ~= "string",
    buffer = opts.buffer ~= nil
      and type(opts.buffer) ~= "boolean"
      and type(opts.buffer) ~= "number",
  }

  if flags.modes or flags.lhs or flags.rhs or flags.buffer then
    notify_caller(flags, modes, lhs, rhs, opts)
    return
  end

  -- Apply description
  if type(desc) == "string" then
    opts.desc = desc
  end

  if opts.desc == nil then
    opts.desc = ""
  end

  -- Default keymap behavior
  if opts.noremap == nil then
    opts.noremap = true
  end

  if opts.silent == nil then
    opts.silent = true
  end

  -- Normalize buffer scoping:
  -- buffer = true  -> current buffer (0)
  -- buffer = n     -> explicit buffer number
  if opts.buffer == true then
    opts.buffer = 0
  end

  -- A lib option, not a native one: strip it before nvim sees it.
  local record = opts.record ~= false
  opts.record = nil

  vim.keymap.set(modes, lhs, rhs, opts)

  -- After the real call, so a keymap that nvim refused is not recorded as
  -- bound. `vim.keymap.set` raises rather than returning a verdict, so an
  -- error here means no record either -- which is the honest outcome.
  if record then
    require("lib.nvim.bindings.keymap.records").add(modes, lhs, rhs, opts)
  end
end
