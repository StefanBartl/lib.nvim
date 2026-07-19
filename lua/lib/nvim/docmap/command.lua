---@module 'lib.nvim.docmap.command'
--- `:LibMap` — regenerate or verify the module map from inside Neovim.
---
---   :LibMap          regenerate the artifacts
---   :LibMap check    verify without writing (what the hook runs)
---   :LibMap open     open the generated HTML in the system browser
---
--- Opt-in: nothing here runs unless a caller invokes `setup()`, so requiring
--- `lib.nvim.docmap` in a plugin does not silently register a command in the
--- user's editor.

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
function M.setup(opts)
  local usercmd = require("lib.nvim.usercmd")
  local notify = require("lib.nvim.notify").create("[docmap]")

  usercmd.create("LibMap", function(args)
    local docmap = require("lib.nvim.docmap")
    local root = (opts and opts.root) or self_root()
    local cfg = opts or require("lib.nvim.docmap.config")(root)
    local action = vim.trim(args.args or "")

    if action == "open" then
      local target = cfg.root .. "/" .. (cfg.out_dir or "docs/map") .. "/index.html"
      if vim.uv.fs_stat(target) == nil then
        notify.warn("No map generated yet — run :LibMap first.")
        return
      end
      require("lib.nvim.fs.open.url.system_opener").open(target)
      return
    end

    local ir = docmap.scan(cfg)
    local findings = docmap.check(ir, cfg)
    local tally = docmap.tally(findings)

    if action == "check" then
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

    local _, _, written = docmap.generate(cfg)
    notify.info(("Wrote %d artifacts (%d modules, %d errors)")
      :format(#written, ir.meta.counts.module, tally.error))
  end, {
    nargs = "?",
    desc = "Regenerate the lib.nvim module map (:LibMap [check|open])",
    complete = function(lead)
      return vim.tbl_filter(function(c)
        return c:find(lead, 1, true) == 1
      end, { "check", "open" })
    end,
  })
end

return M
