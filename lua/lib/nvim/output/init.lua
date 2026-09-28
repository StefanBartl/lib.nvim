---@module 'lib.nvim.output'
---@brief Channel-agnostic output facade over notify/popup/echo.
---@description
--- One notifier shape (`info`/`warn`/`error`/`debug`/`notify`, plus `dump`)
--- regardless of which delivery channel a caller picks:
---
---   local out = require("lib.nvim.output").create("[myplugin]")
---   out.info("started")                 -- popup toast + history (the default)
---   out.dump({ "line 1", "line 2" }, "results") -- viewer, on every channel
---
---   local echo_out = require("lib.nvim.output").create("[p]", { channel = "echo" })
---   echo_out.info("12/128")             -- transient cmdline line, no history
---
--- The default channel is always explicitly `"popup"` -- never guessed from
--- context (e.g. "am I in a fast loop" or "is a UI attached") -- so a
--- caller's behavior does not change out from under it. `register_channel`
--- lets a caller add its own channel by name, resolved the same way as the
--- three built in here.
---
--- Headless (no UI attached, `#vim.api.nvim_list_uis() == 0`): every channel
--- falls back to `io.stderr:write` regardless of what was requested, so
--- library/CI code that happens to call through this facade does not error
--- or block waiting on a UI that will never appear.

require("lib.nvim.output.@types")

local M = {}

---@type table<string, Lib.Output.ChannelFactory>
local channels = {}

---Registers (or overrides) a channel factory under `name`, resolvable via
---`create(prefix, { channel = name })` afterwards.
---@param name string
---@param factory Lib.Output.ChannelFactory
---@return nil
function M.register_channel(name, factory)
  channels[name] = factory
end

---@return boolean
local function is_headless()
  return #vim.api.nvim_list_uis() == 0
end

---Normalizes `prefix` the same way `lib.nvim.notify.create` does, for
---channels (namely "echo") that do not delegate to it directly.
---@param prefix string
---@return string
local function normalize_prefix(prefix)
  if type(prefix) ~= "string" then
    prefix = ""
  end
  if prefix ~= "" and not prefix:match("%s$") then
    prefix = prefix .. " "
  end
  return prefix
end

---Builds the `dump(lines, title)` every non-headless channel shares
---verbatim: always the viewer, regardless of the channel's own delivery path.
---@param display_name string Fallback title when `dump` is called without one
---@return fun(lines: string[], title?: string): Lib.UI.Kit.Surface|nil
local function make_dump(display_name)
  return function(lines, title)
    return require("lib.nvim.output.viewer").show_lines(title or display_name, lines)
  end
end

---@param prefix string
---@return Lib.Output.Notifier
local function headless_notifier(prefix)
  prefix = normalize_prefix(prefix)

  local function line(msg)
    io.stderr:write(prefix, tostring(msg), "\n")
  end

  local notifier = {}
  function notifier.notify(msg, _level, _opts)
    line(msg)
  end
  function notifier.info(msg, _opts)
    line(msg)
  end
  function notifier.warn(msg, _opts)
    line(msg)
  end
  function notifier.error(msg, _opts)
    line(msg)
  end
  function notifier.debug(msg, _opts)
    line(msg)
  end
  function notifier.dump(lines, title)
    if title then
      line(title)
    end
    for _, l in ipairs(lines) do
      io.stderr:write(l, "\n")
    end
  end
  return notifier
end

channels.popup = function(prefix, create_opts)
  local notifier = require("lib.nvim.notify").create(prefix, {
    popup = true,
    source = create_opts.source,
    messages = create_opts.messages,
  }) --[[@as Lib.Output.Notifier]]
  notifier.dump = make_dump(prefix)
  return notifier
end

channels.vim_notify = function(prefix, _create_opts)
  local notifier = require("lib.nvim.notify").create(prefix) --[[@as Lib.Output.Notifier]]
  notifier.dump = make_dump(prefix)
  return notifier
end

channels.echo = function(prefix, _create_opts)
  local echo = require("lib.nvim.echo")
  local normalized = normalize_prefix(prefix)

  local notifier = {}
  function notifier.notify(msg, level, opts)
    opts = opts or {}
    level = level or vim.log.levels.INFO
    echo.write(normalized .. tostring(msg), { level = level, history = opts.history })
  end
  function notifier.info(msg, opts)
    notifier.notify(msg, vim.log.levels.INFO, opts)
  end
  function notifier.warn(msg, opts)
    notifier.notify(msg, vim.log.levels.WARN, opts)
  end
  function notifier.error(msg, opts)
    notifier.notify(msg, vim.log.levels.ERROR, opts)
  end
  function notifier.debug(msg, opts)
    notifier.notify(msg, vim.log.levels.DEBUG, opts)
  end
  notifier.dump = make_dump(normalized)
  return notifier
end

---Creates a notifier for `prefix` on the given (or default) channel.
---@param prefix string
---@param opts? Lib.Output.CreateOpts
---@return Lib.Output.Notifier
function M.create(prefix, opts)
  opts = opts or {}
  if is_headless() then
    return headless_notifier(prefix)
  end

  local name = opts.channel or "popup"
  local factory = channels[name]
  if not factory then
    error(("lib.nvim.output.create: unknown channel %q"):format(tostring(name)), 2)
  end
  return factory(prefix, opts)
end

---@type Lib.Output
return M
