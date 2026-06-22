---@module 'lib.nvim.map'
-- =========================================================
-- Keymap helper utilities.
--
-- Convenience wrapper around vim.keymap.set with defaults
-- and deferred debug diagnostics for invalid argument types.
-- - optional buffer scoping
-- =========================================================


-- ---@param flags Lib.Map.ErrorFlags
-- ---@param modes? string|string[]
-- ---@param lhs? string
-- ---@param rhs? string|function
-- ---@param opts? Lib.Map.Opts
-- ---@return nil

local notify = require("lib.nvim.notify").create("[lib.nvim.map]")

local function notify_caller(flags, modes, lhs, rhs, opts)
  -- Stack layout:
  -- 1: debug.getinfo
  -- 2: notify_caller
  -- 3: lib.nvim.map wrapper
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
    errors[#errors + 1] = string.format(
      "invalid modes (expected string|string[], got %s)",
      type(modes)
    )
  end

  if flags.lhs then
    errors[#errors + 1] = string.format(
      "invalid lhs (expected string, got %s)",
      type(lhs)
    )
  end

  if flags.rhs then
    errors[#errors + 1] = string.format(
      ("invalid rhs (expected function or string, got %s)"),
      type(rhs)
    )
  end

  if flags.buffer then
    errors[#errors + 1] = string.format(
      "invalid buffer option (expected boolean|integer, got %s)",
      type(opts and opts.buffer)
    )
  end

  notify.error(string.format( "[lib.nvim.map] argument validation failed:\n %s\n caller: %s", table.concat(errors, "\n "), caller ))
end

---Convenience wrapper for vim.keymap.set with defaults.
---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts Lib.Map.Opts|nil
---@param desc string?
---@type Lib.Map
return function(modes, lhs, rhs, opts, desc)
  opts = opts or {}

  ---@type Lib.Map.ErrorFlags
  local flags = {
    modes  = not (type(modes) == "string" or type(modes) == "table"),
    lhs    = type(lhs) ~= "string",
    rhs    = type(rhs) ~= "function" and type(rhs) ~= "string",
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

  vim.keymap.set(modes, lhs, rhs, opts)
end

