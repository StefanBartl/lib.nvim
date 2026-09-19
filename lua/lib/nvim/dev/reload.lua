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
---
---With no `opts.lua_dir`, the config root is resolved through
---`lib.nvim.fs.stdpath_config_root` -- per save, not once at registration.
---This module used to bake `stdpath("config")/lua` in as a single spelling
---when `watch()` was called, which is exactly the two-spelling comparison
---`stdpath_config_root` exists to fix: on the common dotfiles setup where
---`stdpath("config")` is a symlink into a repo, that baked-in spelling never
---matched a buffer name in the *other* spelling, and a save silently reloaded
---nothing. `opts.lua_dir`, when given, is an explicit override with no
---connection to `stdpath("config")` and is honoured literally, as before.
---@param opts { lua_dir?: string, pattern?: string, group?: string }|nil
---  `lua_dir` -- the config's Lua root; default: resolved per save through
---  `lib.nvim.fs.stdpath_config_root`, which is `stdpath("config")/lua` for a
---  plain (non-symlinked) config and the buffer's own spelling of it
---  otherwise -- not a single fixed value, see the paragraph above.
---@return nil
function M.watch(opts)
  opts = opts or {}
  local autocmd = require("lib.nvim.bindings.autocmd")
  local stdpath_config_root = require("lib.nvim.fs.stdpath_config_root")
  local explicit_lua_dir = opts.lua_dir and (vim.fs.normalize(opts.lua_dir) .. "/") or nil

  autocmd.create("BufWritePost", function(args)
    local abs = vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf))

    local lua_dir = explicit_lua_dir
    if not lua_dir then
      -- `vim.fs.dirname(abs)` is already normalized (`abs` is, and dirname is
      -- a pure string split), so `stdpath_config_root` re-normalizing it
      -- internally is redundant on this call specifically -- deliberately
      -- left in rather than optimized away: `BufWritePost` fires once per
      -- explicit save, not per keystroke or per LSP request, so the cost is
      -- unmeasurable here, and `stdpath_config_root` keeping its own
      -- defensive normalize means it stays correct for any future caller
      -- that does not already guarantee a normalized `dir`.
      local root = stdpath_config_root(vim.fs.dirname(abs))
      if not root then
        return
      end
      lua_dir = root .. "/lua/"
    end

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
