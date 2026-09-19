---@module 'lib.nvim.fs.polymorphic_rootresolver'
--- Generic polymorphic root-directory resolver for Neovim LSPs.
--- Supports both buffer numbers and filenames, optional callbacks, and configurable
--- project root markers for VCS or tool-specific files.
---
--- `cfg.resolve` replaces the marker search for servers whose notion of a root
--- is more than "nearest marker", while keeping the argument normalization and
--- the callback contract shared -- that boilerplate is the same in every
--- resolver and is what gets copied when it is not available here.

local uv = vim.uv or vim.loop
local fs = vim.fs

local stdpath_config_root = require("lib.nvim.fs.stdpath_config_root")

-- Types: see @types/init.lua (RootResolverCfg).
---@type RootResolverCfg
local DEFAULT_CFG = {
  markers = { ".git", ".hg", ".svn" },
  include_stdpath_config = true,
}

---@param cfg RootResolverCfg|nil
---@return fun(arg:string|integer, cb?:fun(root:string)):string
return function(cfg)
  cfg = vim.tbl_deep_extend("force", {}, DEFAULT_CFG, cfg or {})

  --- Polymorphic resolver function
  ---@param arg string|integer  Filename or buffer number
  ---@param cb fun(root:string)|nil Optional callback
  ---@return string  Resolved root directory
  return function(arg, cb)
    ---@type string
    local fname
    if type(arg) == "number" then
      fname = vim.api.nvim_buf_get_name(arg) or ""
    else
      fname = tostring(arg or "")
    end

    if fname == "" then
      fname = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    end

    ---@type string
    local dir = fs.dirname(fs.normalize(fname))
    if not dir or dir == "" then
      dir = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    end

    ---@type string|nil
    local root
    if type(cfg.resolve) == "function" then
      local ok, resolved = pcall(cfg.resolve, dir, cfg)
      root = ok and resolved or nil
    else
      root = fs.root(dir, cfg.markers)
    end
    if not root then
      root = dir
    end

    -- `stdpath_config_root` rather than a `stdpath("config")` compare of its
    -- own: the raw value is routinely a symlink into a dotfiles repo, and a
    -- plain compare against it silently misses for every buffer whose name
    -- Neovim canonicalized on the way in.
    if cfg.include_stdpath_config then
      root = stdpath_config_root(root) or root
    end

    if cb and type(cb) == "function" then
      pcall(cb, root)
    end

    return root
  end
end
