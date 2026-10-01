---@meta
---@module 'lib.nvim.messages.@types'

---@class Lib.Messages.Entry
---@field time_ms number `vim.uv.hrtime() / 1e6` -- monotonic, not wall-clock
---@field level integer vim.log.levels value
---@field kind string Neovim's `msg_show` kind (`""`, `lua_error`, `echomsg`, ...), or `"notify"` for entries pushed via `M.push` from `lib.nvim.notify`
---@field content string The message text, chunk highlights already stripped
---@field source? string Optional tag (e.g. a `lib.nvim.notify.create()` prefix)
---@field replace_last boolean Whether this entry replaced the previous one instead of appending (Neovim's own `msg_show` signal, e.g. a search count after the pattern echo)

---@class Lib.Messages.PushEntry
---@field time_ms? number Default: `vim.uv.hrtime() / 1e6`
---@field level? integer Default: `vim.log.levels.INFO`
---@field kind? string Default: `"notify"`
---@field content? string Default: `""`
---@field source? string
---@field replace_last? boolean Default: `false`

---@class Lib.Messages.SnapshotOpts
---@field since_ms? number Inclusive lower bound (same clock as `Entry.time_ms`)
---@field until_ms? number Inclusive upper bound
---@field kinds? string[] Allow-list; omit for no kind filtering
---@field levels? integer[] Allow-list of `vim.log.levels` values; omit for no level filtering

---@class Lib.Messages.Config
---@field ring_size? integer Max entries kept. Default 1000 (~0.3MB, measured negligible -- see the TUI spike report)
---@field kinds? table<string, boolean> `history=false` `msg_show` kinds to keep anyway (e.g. `{ list_cmd = true }`). Default `{}` -- only `history=true` entries are kept
---@field renderer_override? boolean Force `has_renderer()`'s answer instead of checking `package.loaded["noice"]`. Default `nil` (auto-detect)

--- `lib.nvim.messages` module surface.
---@class Lib.Messages
---@field setup fun(opts?: Lib.Messages.Config): nil
---@field notify_renderer_changed fun(): nil
---@field wrap_noice fun(): nil
---@field push fun(entry: Lib.Messages.PushEntry): nil
---@field snapshot fun(opts?: Lib.Messages.SnapshotOpts): Lib.Messages.Entry[]
---@field on_message fun(fn: fun(entry: Lib.Messages.Entry)): fun(entry: Lib.Messages.Entry)
---@field off_message fun(fn: fun(entry: Lib.Messages.Entry)): nil

return {}
