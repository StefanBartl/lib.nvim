---@meta
---@module 'lib.config.@types'

---@class Lib.Config.Options
---@field strategy "metatable"|"lazy"|"eager"

---`require("lib.config")` itself.
---@class Lib.Config
---@field options Lib.Config.Options
---@field setup fun(opts?: Lib.Config.Options): nil
---@field get fun(): Lib.Config.Options
---@field strategy_module fun(): string
