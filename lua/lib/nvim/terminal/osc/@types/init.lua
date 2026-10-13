---@meta
---@module 'lib.nvim.terminal.osc.@types'

---@class Lib.Terminal.Osc
---@field sanitize fun(s: any, max?: integer): string # Control characters become `?`, cut to `max` bytes (default 200) on a character boundary
---@field user_var fun(name: string, value: string): string|nil, string|nil # `OSC 1337 SetUserVar` sequence; the name is validated, the value base64-encoded
---@field wrap_tmux fun(seq: string): string # tmux DCS passthrough envelope
---@field wrap fun(seq: string, in_tmux?: boolean): string # Wrap when in tmux (default: `$TMUX` set)
---@field available fun(): boolean # `nvim_ui_send` exists (Neovim 0.12+)
---@field send fun(payload: string): boolean, string|nil # Write to the host terminal in one call

return {}
