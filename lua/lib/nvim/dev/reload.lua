---@module 'lib.nvim.dev.reload'
--- Reload one Lua module: drop it from `package.loaded`, `require` it again.
---@description
--- Promoted out of a host config's own NvChad-shadow file
--- (`lua/nvchad/au.lua`, which existed only so a `BufWritePost` autocmd could
--- override NvChad's own eager version -- see `M.watch`'s doc comment). The
--- reload itself never had anything to do with NvChad, only the autocmd
--- wiring around it did.

local M = {}

---Reload `name`: clear its cache entry, `require` it fresh.
---@param name string dotted module path, e.g. "plugins.ui"
---@return boolean ok
function M.module(name)
  package.loaded[name] = nil
  local ok, err = pcall(require, name)
  if not ok then
    -- `require()` does not leave `package.loaded[name]` as `nil` when its
    -- loader errors -- reproducibly, it ends up some truthy non-table,
    -- non-`true` value (observed: a denormalized float). Lua's own
    -- `require()` treats any truthy `package.loaded[name]` as "already
    -- loaded" and returns it as-is without re-running the loader -- so
    -- without this second clear, the NEXT plain `require(name)` anywhere in
    -- the running session would silently hand back that garbage value
    -- instead of either the real module or a fresh, clear error.
    package.loaded[name] = nil
    require("lib.nvim.notify")
      .create("[lib.nvim.dev.reload]")
      .error(("failed to reload %q: %s"):format(name, tostring(err)))
  end
  return ok
end

---Register a `BufWritePost` autocmd that reloads whichever config module was
---just saved, matched lazily per save rather than pre-globbing every file at
---startup -- the eager version this replaced (a stock NvChad file, globbing
---and `vim.uv.fs_realpath`-resolving every `*.lua` under the config root
---unconditionally at startup) cost ~600ms on a config with ~450 files,
---whether or not a file was ever even saved.
---@param opts { lua_dir?: string, pattern?: string, group?: string }|nil
---  `lua_dir` -- the config's Lua root; default `stdpath("config")/lua`.
---@return nil
function M.watch(opts)
  opts = opts or {}
  local autocmd = require("lib.nvim.bindings.autocmd")
  local lua_dir = vim.fs.normalize(opts.lua_dir or (vim.fn.stdpath("config") .. "/lua")) .. "/"

  autocmd.create("BufWritePost", function(args)
    local abs = vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf))
    if abs:sub(1, #lua_dir) ~= lua_dir then
      return
    end
    local name = abs:sub(#lua_dir + 1):gsub("%.lua$", ""):gsub("/", ".")
    M.module(name)
  end, {
    group = autocmd.group(opts.group or "lib_nvim_dev_reload", true),
    pattern = opts.pattern or "*.lua",
    desc = "lib.nvim.dev.reload: reload a config module after saving it",
  })
end

return M
