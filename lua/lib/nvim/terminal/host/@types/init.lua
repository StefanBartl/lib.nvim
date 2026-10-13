---@meta
---@module 'lib.nvim.terminal.host.@types'

---@class Lib.Terminal.Host
---@field name string|nil          WezTerm, iTerm2, Konsole, Kitty, Windows Terminal; nil when unknown
---@field osc1337 boolean          The terminal is known to draw OSC 1337 (inline images, user vars)
---@field in_tmux boolean          `$TMUX` is set: sequences need tmux's passthrough envelope
---@field hint string|nil          What to configure when `in_tmux`

---@class Lib.Terminal.HostModule
---@field detect fun(env?: table): Lib.Terminal.Host
---@field in_tmux fun(env?: table): boolean

return {}
