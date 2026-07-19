---@module 'lib.nvim.docmap.command'
--- `:LibMap` — regenerate or verify the module map from inside Neovim.
---
---   :LibMap          regenerate the artifacts
---   :LibMap check    verify without writing (what the hook runs)
---   :LibMap full     regenerate with LuaLS enrichment (class/alias detail,
---                    type-reference edges) — slower, opt-in per invocation
---   :LibMap open     open the generated HTML in the system browser
---
--- Opt-in: nothing here runs unless a caller invokes `setup()`, so requiring
--- `lib.nvim.docmap` in a plugin does not silently register a command in the
--- user's editor.
---
--- Built on `docmap.registry`: `setup()` ensures a live handle exists for
--- `opts.root` (reusing one from a prior `docmap.install()` call rather than
--- scanning a second time) and drives every action through it, so `:LibMap`
--- and any `on_change` subscriber another plugin registered stay in sync
--- with the same IR instead of each holding their own stale copy.
---
--- `opts.command_name` (default "LibMap") is what lets a second `setup()`
--- call — a consuming plugin generating its own map — pick a different name
--- instead of silently overwriting this one; `usercmd.create` defaults to
--- `force = true`, so two `setup()` calls with the same name is not an error,
--- just a bug that changing the name avoids.

local M = {}

---Resolve the repository root the map should be generated for.
---
---`vim.fn.getcwd()` is wrong when the user is editing lib.nvim from somewhere
---else, so this walks up from this very file instead — five levels from
---`lua/lib/nvim/docmap/command.lua` is the repo root.
---@return string
local function self_root()
  local this = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  -- docmap/ -> nvim/ -> lib/ -> lua/ -> repo root
  return vim.fn.fnamemodify(this, ":h:h:h:h:h")
end

---@param opts Lib.Docmap.Opts?
---@return Lib.Docmap.Handle
function M.setup(opts)
  local usercmd = require("lib.nvim.usercmd")
  local notify = require("lib.nvim.notify").create("[docmap]")
  local registry = require("lib.nvim.docmap.registry")
  local docmap = require("lib.nvim.docmap")

  local root = (opts and opts.root) or self_root()
  local cfg = opts or require("lib.nvim.docmap.config")(root)
  local command_name = cfg.command_name or "LibMap"

  local handle = registry.get(cfg.root) or registry.install(cfg)

  usercmd.create(command_name, function(args)
    local action = vim.trim(args.args or "")

    if action == "open" then
      local target = cfg.root .. "/" .. (cfg.out_dir or "docs/map") .. "/index.html"
      if vim.uv.fs_stat(target) == nil then
        notify.warn("No map generated yet — run :" .. command_name .. " first.")
        return
      end
      require("lib.nvim.fs.open.url.system_opener").open(target)
      return
    end

    if action == "check" then
      local ir, findings = handle.rescan()
      local tally = docmap.tally(findings)
      local summary = ("%d errors · %d warnings · %d info"):format(tally.error, tally.warn, tally.info)
      if tally.error > 0 then
        notify.warn("Module map drift: " .. summary)
      else
        notify.info("Module map: " .. summary)
      end
      -- Route the detail through the quickfix list rather than a notification
      -- so findings are navigable instead of scrolling past.
      local items = {}
      for _, f in ipairs(findings) do
        if f.severity ~= "info" then
          items[#items + 1] = {
            filename = cfg.root .. "/" .. (f.node or ""),
            text = ("[%s] %s: %s"):format(f.severity, f.check, f.message),
            type = f.severity == "error" and "E" or "W",
          }
        end
      end
      vim.fn.setqflist({}, " ", { title = "Module map drift", items = items })
      if #items > 0 then
        vim.cmd("copen")
      end
      return
    end

    if action == "full" then
      local ir, findings = handle.rescan({ luals = true })
      local written = docmap.write_artifacts(ir, findings, cfg)
      local tally = docmap.tally(findings)
      notify.info(("Wrote %d artifacts with LuaLS enrichment (%d modules, %d edges, %d errors)")
        :format(#written, ir.meta.counts.module, #(ir.edges or {}), tally.error))
      return
    end

    local ir, findings = handle.rescan()
    local written = docmap.write_artifacts(ir, findings, cfg)
    local tally = docmap.tally(findings)
    notify.info(("Wrote %d artifacts (%d modules, %d errors)")
      :format(#written, ir.meta.counts.module, tally.error))
  end, {
    nargs = "?",
    desc = "Regenerate the module map (:" .. command_name .. " [check|full|open])",
    complete = function(lead)
      return vim.tbl_filter(function(c)
        return c:find(lead, 1, true) == 1
      end, { "check", "full", "open" })
    end,
  })

  return handle
end

return M
