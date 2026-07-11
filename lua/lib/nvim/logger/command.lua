---@module 'lib.nvim.logger.command'
--- Registers the `:LibLogger` control command so a developer can flip logging
--- on/off, change the level, inspect recent records, and dump/clear at runtime
--- without restarting Neovim. Installed once, on first `logger.new()`.

local M = {}

local usercmd = require("lib.nvim.usercmd")
local make_scratch = require("lib.nvim.window.make_scratch")
local serialize = require("lib.nvim.logger.serialize")

---Collect recent records across all loggers, newest last, capped at `limit`.
---@param mod Lib.Logger
---@param limit integer
---@return string[]
local function recent_lines(mod, limit)
  local all = {}
  for _, inst in ipairs(mod.loggers()) do
    for _, rec in ipairs(inst.snapshot()) do
      all[#all + 1] = rec
    end
  end
  table.sort(all, function(a, b)
    return (a.mono or 0) < (b.mono or 0)
  end)

  local lines = {}
  local from = math.max(1, #all - limit + 1)
  for i = from, #all do
    lines[#lines + 1] = serialize.human(all[i])
  end
  if #lines == 0 then
    lines[1] = "(no records)"
  end
  return lines
end

---@param mod Lib.Logger
function M.install(mod)
  usercmd.create("LibLogger", function(args)
    local sub = args.fargs[1] or "show"
    local rest = args.fargs[2]

    if sub == "on" then
      mod.set_enabled(true)
      vim.notify("[lib.nvim.logger] enabled", vim.log.levels.INFO)
    elseif sub == "off" then
      mod.set_enabled(false)
      vim.notify("[lib.nvim.logger] disabled (zero-cost)", vim.log.levels.INFO)
    elseif sub == "level" then
      mod.set_level(rest)
      vim.notify(
        ("[lib.nvim.logger] global level -> %s"):format(tostring(rest)),
        vim.log.levels.INFO
      )
    elseif sub == "dump" then
      local n = 0
      for _, inst in ipairs(mod.loggers()) do
        if inst.flush() then
          n = n + 1
        end
      end
      vim.notify(("[lib.nvim.logger] flushed %d file sink(s)"):format(n), vim.log.levels.INFO)
    elseif sub == "clear" then
      for _, inst in ipairs(mod.loggers()) do
        inst.clear()
      end
      vim.notify("[lib.nvim.logger] cleared ring buffers", vim.log.levels.INFO)
    elseif sub == "tags" then
      local t = mod.tags()
      vim.notify(
        ("[lib.nvim.logger] disabled=%s only=%s"):format(
          vim.inspect(t.disabled),
          vim.inspect(t.only)
        ),
        vim.log.levels.INFO
      )
    else -- "show"
      local limit = tonumber(rest) or 50
      make_scratch({
        lines = recent_lines(mod, limit),
        title = " lib.nvim.logger ",
        filetype = "log",
        nice_quit = true,
        width = math.min(120, math.max(60, vim.o.columns - 8)),
      })
    end
  end, {
    nargs = "*",
    desc = "lib.nvim.logger control: show|on|off|level <l>|dump|clear|tags",
    complete = function()
      return { "show", "on", "off", "level", "dump", "clear", "tags" }
    end,
  })
end

return M
