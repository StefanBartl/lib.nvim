---@module 'lib.nvim.fs.polymorphic_rootresolver'
--- Generic polymorphic root-directory resolver for Neovim LSPs.
--- Supports both buffer numbers and filenames, optional callbacks, and configurable
--- project root markers for VCS or tool-specific files.

local uv = vim.uv or vim.loop
local fs = vim.fs

local is_subpath = require("lib.nvim.fs.is_subpath")

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
    local root = fs.root(dir, cfg.markers)
    if not root then
      root = dir
    end

    if cfg.include_stdpath_config then
      local stdconfig = vim.fn.stdpath("config")
      if is_subpath(root, stdconfig) then
        root = stdconfig
      end
    end

    if cb and type(cb) == "function" then
      pcall(cb, root)
    end

    return root
  end
end
