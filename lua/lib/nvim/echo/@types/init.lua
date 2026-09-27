---@meta
---@module 'lib.nvim.echo.@types'

--- A single `nvim_echo` chunk: text plus an optional highlight group name.
---@alias Lib.Echo.Chunk [string, string?]

---@class Lib.Echo.WriteOpts
---@field level? integer vim.log.levels value; only used to pick a default highlight group when `text_or_chunks` is a plain string (default: INFO, no highlight)
---@field history? boolean Record in `:messages` (`nvim_echo(..., true, {})`). Default `false` -- most calls are transient progress/status lines, not history-worthy events (use `lib.nvim.notify` for those)

--- `lib.nvim.echo` module surface.
---@class Lib.Echo
---@field write fun(text_or_chunks: string|Lib.Echo.Chunk[], opts?: Lib.Echo.WriteOpts): nil

return {}
