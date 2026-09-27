---@meta
---@module 'lib.nvim.output.@types'

--- The three channels `lib.nvim.output` registers out of the box. Not the
--- full set of valid `channel` values -- `register_channel` can add more --
--- so `Lib.Output.CreateOpts.channel` itself stays typed as plain `string`.
---@alias Lib.Output.Channel "popup"|"echo"|"vim_notify"

---@class Lib.Output.CreateOpts
---@field channel? string Delivery channel: one of `Lib.Output.Channel`, or a name previously registered via `register_channel` (default: "popup", always explicit -- never guessed from context)
---@field source? string Forwarded to the "popup" channel's history/title tagging
---@field messages? boolean Forwarded to the "popup" channel's `:messages` write

--- Same shape as `Lib.Notify.Notifier`, plus `dump` -- the `print()`
--- replacement, identical across every channel: always opens the viewer,
--- never the channel's own delivery path.
---@class Lib.Output.Notifier
---@field notify fun(msg: string, level?: integer, opts?: table)
---@field info fun(msg: string, opts?: table)
---@field warn fun(msg: string, opts?: table)
---@field error fun(msg: string, opts?: table)
---@field debug fun(msg: string, opts?: table)
---@field dump fun(lines: string[], title?: string): Lib.UI.Kit.Surface|nil

--- A channel factory, as registered via `register_channel`: builds a notifier
--- for one prefix. `create_opts` is whatever `M.create`'s caller passed,
--- minus `channel` itself.
---@alias Lib.Output.ChannelFactory fun(prefix: string, create_opts: Lib.Output.CreateOpts): Lib.Output.Notifier

--- `lib.nvim.output` module surface.
---@class Lib.Output
---@field register_channel fun(name: string, factory: Lib.Output.ChannelFactory): nil
---@field create fun(prefix: string, opts?: Lib.Output.CreateOpts): Lib.Output.Notifier

return {}
