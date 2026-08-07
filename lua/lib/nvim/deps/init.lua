---@module 'lib.nvim.deps'
--- External-tool detection, declared-dependency spec parsing, and an opt-in
--- `:Lib deps` surface, for plugins that degrade gracefully without optional
--- CLI tools (pandoc, ImageMagick, tesseract, poppler-utils, …). See
--- docs/ROADMAP/dependency-installer.md in this repo for the full design and
--- the `docs/INSTALL.md` / `docs/install.json` spec formats.
---
--- Requiring this module registers nothing and touches nothing. `setup()`
--- registers the `:Lib deps` routes and still executes no install command —
--- only `:Lib deps install`, invoked by hand and confirmed, ever puts a
--- command in front of the user (and even then, in a terminal they submit
--- themselves; see `lib.nvim.deps.install`).

local M = {}

M.spec = require("lib.nvim.deps.spec")
M.health = require("lib.nvim.deps.health")
M.pm = require("lib.nvim.deps.pm")
M.install = require("lib.nvim.deps.install")
M.view = require("lib.nvim.deps.view")

---Every plugin on `runtimepath` shipping a deps spec. Convenience re-export
---of `lib.nvim.deps.spec.plugins`.
---@return string[]
function M.plugins()
  return M.spec.plugins()
end

---@internal
---Resolve and parse `plugin_name`'s spec, notifying on the two ways that
---fails (no spec shipped / spec file unreadable).
---@param plugin_name string
---@return Lib.Deps.ParseResult|nil
local function resolve(plugin_name)
  local notify = require("lib.nvim.notify").create("[lib.nvim.deps]")

  local path = M.spec.find(plugin_name)
  if not path then
    notify.warn(
      ("%s ships no docs/install.json or docs/INSTALL.md (or isn't on runtimepath)."):format(
        plugin_name
      )
    )
    return nil
  end

  local result, err = M.spec.load(path)
  if not result then
    notify.error(err or ("could not read " .. path))
    return nil
  end
  return result
end

---Show `plugin_name`'s declared tools, each with its `why` and its status on
---this host, in a scratch split.
---@param plugin_name string
---@return boolean shown
function M.show(plugin_name)
  local result = resolve(plugin_name)
  if not result then
    return false
  end
  M.view.show(plugin_name, result)
  return true
end

---Offer to install whatever `plugin_name` declares and this host is missing.
---Confirmation-gated; see `lib.nvim.deps.install.run`.
---@param plugin_name string
---@return boolean started
function M.install_for(plugin_name)
  local result = resolve(plugin_name)
  if not result then
    return false
  end
  return M.install.run(M.install.plan(result.tools))
end

---@internal
---Argument type completing plugin names that actually ship a deps spec.
---Registered lazily by `setup()` rather than at require time — registering a
---composer type is a side effect, and this module's contract is that
---requiring it has none.
local function register_argtype()
  require("lib.nvim.usercmd.composer").register_type("DEPS_PLUGIN", {
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(lead)
      return vim.tbl_filter(function(name)
        return name:sub(1, #lead) == lead
      end, M.plugins())
    end,
  })
end

---The `:Lib deps …` routes, for `lib.nvim_usrcmds` to merge into the `:Lib`
---verb it already builds. Exposed as data rather than registered here so
---there is exactly one place that owns the `:Lib` verb.
---@return table[] routes
function M.routes()
  register_argtype()
  return {
    {
      path = { "deps", "show" },
      args = { { name = "plugin", type = "DEPS_PLUGIN", optional = true } },
      desc = "List a plugin's declared external tools, why each matters, and what's missing",
      run = function(ctx)
        if ctx.args.plugin then
          M.show(ctx.args.plugin)
        else
          local names = M.plugins()
          local notify = require("lib.nvim.notify").create("[lib.nvim.deps]")
          if #names == 0 then
            notify.info("No plugin on runtimepath ships a deps spec.")
          else
            notify.info("Plugins with a deps spec: " .. table.concat(names, ", "))
          end
        end
      end,
    },
    {
      path = { "deps", "install" },
      args = { { name = "plugin", type = "DEPS_PLUGIN" } },
      desc = "Offer to install a plugin's missing external tools (asks first)",
      run = function(ctx)
        M.install_for(ctx.args.plugin)
      end,
    },
  }
end

---@type Lib.Deps
return M
