---@meta
---@module 'lib.nvim.contract.echo.@types'

---@class Lib.Contract.Echo
---@field MAX integer  # the longest echo, in characters
---@field clip fun(text: string): string  # short (at most `MAX` characters, never cut inside one), valid UTF-8, printable; a control character is written as an escape (`\x1b`, `\u009b`)

return {}
