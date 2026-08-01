---@module 'lib.nvim.telemetry.command'
--- The `:LibTelemetry` control command.
---
--- Opt-in on purpose: requiring this module registers nothing. Call
--- `require("lib.nvim.telemetry.command").setup()` from your config if you want
--- the command — a library that silently claims a user-command name is a
--- library that collides with someone's own mapping.
---
---   :LibTelemetry                 report across every live instance
---   :LibTelemetry lsp.nvim        report for one namespace
---   :LibTelemetry start [ns]      start every instance, or just one
---   :LibTelemetry stop [ns]       stop every instance, or just one
---   :LibTelemetry reset [ns]      drop collected data, every instance or just one
---   :LibTelemetry disable [ns]    stop + persist "off" across restarts
---   :LibTelemetry enable [ns]     clear a persisted disable, resume now
---   :LibTelemetry disabled        list namespaces currently disabled
---   :LibTelemetry coverage        which wrapped functions were never called
---   :LibTelemetry export [path]   write a JSON snapshot

local usercmd = require("lib.nvim.usercmd")
local notify = require("lib.nvim.notify").create("[lib.nvim.telemetry]")

local M = {}

local SUBCOMMANDS =
  { "report", "start", "stop", "reset", "disable", "enable", "disabled", "coverage", "export" }

---@return Lib.Telemetry
local function telemetry()
  return require("lib.nvim.telemetry")
end

---@param lines string[]
---@param title string
local function show(lines, title)
  local ok, kit = pcall(require, "lib.nvim.ui.kit")
  if ok then
    kit.viewer({
      lines = lines,
      title = (" %s "):format(title),
      width = math.min(110, math.max(60, vim.o.columns - 8)),
    })
    return
  end
  -- No kit (a stripped runtimepath, a headless session): the data still has to
  -- be reachable, so fall back to the message area rather than failing.
  notify.info(table.concat(lines, "\n"))
end

---@param opts Lib.Telemetry.ReportOpts
---@param namespace string|nil
---@return string[]
local function report_lines(opts, namespace)
  local mod = telemetry()
  local out = {}

  local list = mod.instances()
  if namespace then
    local inst = mod.get(namespace)
    list = inst and { inst } or {}
    if #list == 0 then
      return { ("no telemetry instance for namespace %q"):format(namespace) }
    end
  end

  if #list == 0 then
    return {
      "no telemetry instances.",
      "",
      'Create one with require("lib.nvim.telemetry").new({ namespace = "…" }).',
    }
  end

  for i, inst in ipairs(list) do
    if i > 1 then
      out[#out + 1] = ""
      out[#out + 1] = ("─"):rep(60)
      out[#out + 1] = ""
    end
    vim.list_extend(out, inst.lines(opts))
  end
  return out
end

---@param path string|nil
---@return string|nil written
local function export(path)
  local mod = telemetry()
  local payload = { exported_at = os.time(), reports = mod.report_all() }

  local target = path
  if not target or target == "" then
    target = ("%s/lib.nvim-telemetry-%s.json"):format(
      vim.fn.stdpath("cache"),
      os.date("%Y%m%d-%H%M%S")
    )
  end

  local ok, encoded = pcall(vim.json.encode, payload)
  if not ok then
    return nil
  end

  local file = io.open(target, "w")
  if not file then
    return nil
  end
  file:write(encoded)
  file:close()
  return target
end

---Register `:LibTelemetry`. Idempotent (`usercmd.create` defaults to `force`).
function M.setup()
  usercmd.create("LibTelemetry", function(args)
    local mod = telemetry()
    local first = args.fargs[1]
    local rest = args.fargs[2]

    if first == "start" or first == "stop" or first == "reset" then
      -- A bare `rest` is a namespace, e.g. `:LibTelemetry stop markdown.nvim`
      -- — every other subcommand that takes one puts it in the same slot, so
      -- this stays consistent with `:LibTelemetry <namespace>` (report).
      if rest and rest ~= "" then
        local inst = mod.get(rest)
        if not inst then
          notify.warn(("no telemetry instance for namespace %q"):format(rest))
          return
        end
        if first == "start" then
          inst.start()
          notify.info(("started %s"):format(rest))
        elseif first == "stop" then
          inst.stop()
          notify.info(("stopped %s"):format(rest))
        else
          inst.reset()
          notify.info(("collected data cleared for %s"):format(rest))
        end
        return
      end

      if first == "start" then
        local n = 0
        for _, inst in ipairs(mod.instances()) do
          if inst.start() then
            n = n + 1
          end
        end
        notify.info(("started %d instance(s)"):format(n))
      elseif first == "stop" then
        notify.info(("stopped %d instance(s)"):format(mod.stop_all()))
      else
        for _, inst in ipairs(mod.instances()) do
          inst.reset()
        end
        notify.info("collected data cleared")
      end
    elseif first == "disable" or first == "enable" then
      -- Unlike start/stop/reset, a namespace here does NOT need a live
      -- instance to exist — disabling something before it has ever loaded
      -- this session is the common case, not an edge case.
      if rest and rest ~= "" then
        mod[first](rest)
        notify.info(("%sd %s"):format(first, rest))
        return
      end

      local n = 0
      for _, inst in ipairs(mod.instances()) do
        mod[first](inst.namespace)
        n = n + 1
      end
      notify.info(("%sd %d instance(s)"):format(first, n))
    elseif first == "disabled" then
      local list = mod.disabled()
      show(
        #list > 0 and list or { "no namespace is currently disabled." },
        "lib.nvim.telemetry — disabled"
      )
    elseif first == "coverage" then
      local lines = {}
      for _, inst in ipairs(mod.instances()) do
        local cov = inst.coverage()
        lines[#lines + 1] = ("%s — %d called, %d never called"):format(
          inst.namespace,
          #cov.called,
          #cov.uncalled
        )
        for _, key in ipairs(cov.uncalled) do
          lines[#lines + 1] = "  · " .. key
        end
        lines[#lines + 1] = ""
      end
      show(#lines > 0 and lines or { "no telemetry instances." }, "lib.nvim.telemetry coverage")
    elseif first == "export" then
      local written = export(rest)
      if written then
        notify.info("wrote " .. written)
      else
        notify.error("export failed")
      end
    else
      -- "report" (explicit or implied) — a bare namespace is the common case.
      local namespace = first
      if first == nil or first == "report" then
        namespace = rest
      end
      show(report_lines({ sort = "calls", top = 40 }, namespace), "lib.nvim.telemetry")
    end
  end, {
    nargs = "*",
    desc = "lib.nvim.telemetry: report|start|stop|reset|disable|enable|disabled|coverage|export [namespace]",
    complete = function(arg_lead, cmd_line)
      -- Second token of `start`/`stop`/`reset` is always a namespace, never
      -- another subcommand — narrow completion there instead of offering
      -- "start"/"stop"/... again as if it were a third grammar position.
      local before = cmd_line:sub(1, #cmd_line - #arg_lead)
      local sub = before:match("^%S+%s+(%S+)%s+%S*$")

      local out = {}
      if sub == "start" or sub == "stop" or sub == "reset" or sub == "disable" or sub == "enable" then
        for _, inst in ipairs(telemetry().instances()) do
          out[#out + 1] = inst.namespace
        end
      else
        for _, s in ipairs(SUBCOMMANDS) do
          out[#out + 1] = s
        end
        for _, inst in ipairs(telemetry().instances()) do
          out[#out + 1] = inst.namespace
        end
      end

      return vim.tbl_filter(function(c)
        return c:find(arg_lead or "", 1, true) == 1
      end, out)
    end,
  })
end

M.SUBCOMMANDS = SUBCOMMANDS

return M
