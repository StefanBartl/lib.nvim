---@meta
---@module 'lib.nvim.patterns.throttle.@types'

---@class Lib.Patterns.Throttle.Opts
---@field leading boolean|nil     # Run the first call of a burst at once (default true).
---@field trailing boolean|nil    # Run once more with the latest arguments after the pause (default true).

---@class Lib.Patterns.Throttle.Handle
---@field call fun(...: any)
---@field cancel fun()            # Drop the pending call and end the pause.
---@field flush fun()             # Run the pending call now and end the pause.
