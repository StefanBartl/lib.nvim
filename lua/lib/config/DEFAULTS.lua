---@module 'lib.config.DEFAULTS'
--- Default values for lib.nvim's own configuration. See @types/init.lua for
--- the `Lib.Config.Options` shape and lib/config/init.lua for how these are
--- merged with user-supplied options.

---@type Lib.Config.Options
return {
  strategy = "metatable",
}
