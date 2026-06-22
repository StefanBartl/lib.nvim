---@meta
---@module 'lib.nvim.ui.hl.@types'

---@class Lib.Highlight.Opts
---@field fg string|integer|nil Foreground color (name or RGB integer)
---@field bg string|integer|nil Background color (name or RGB integer)
---@field sp string|integer|nil Special color (name or RGB integer)
---@field bold boolean|nil Enable bold text
---@field underline boolean|nil Enable underline
---@field undercurl boolean|nil Enable undercurl
---@field italic boolean|nil Enable italic
---@field reverse boolean|nil Enable reverse
---@field nocombine boolean|nil Prevent combining with other highlights
---@field link string|nil Link this highlight group to another

---@class Lib.UI.HL
---@field namespace fun(name: string): integer
---@field set fun(group: string, opts: Lib.Highlight.Opts, ns: string|integer|nil)

return {}
