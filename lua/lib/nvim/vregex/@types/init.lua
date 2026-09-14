---@meta
---@module 'lib.nvim.vregex.@types'

---@class Lib.Vregex.LiteralOpts
---@field whole_word? boolean Wrap with `\<`/`\>` so the match doesn't land mid-word.
---@field case? '"ignore"'|'"match"' `"ignore"` prefixes `\c`, `"match"` prefixes `\C`; omit to respect `'ignorecase'`.

---@class Lib.Vregex
---@field escape fun(text: string): string Escape `text` for safe use inside a `\V` pattern (doubles backslashes).
---@field literal fun(text: string, opts?: Lib.Vregex.LiteralOpts): string Build a `\V`-prefixed pattern matching `text` literally.

return {}
