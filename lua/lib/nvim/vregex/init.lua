---@module 'lib.nvim.vregex'
--- Build Vim-regex ("`/`", `:s`, `matchadd`, `vim.fn.search`) patterns that
--- match a piece of user/arbitrary text *literally* — no character in it is
--- ever interpreted as a metacharacter.
---
--- Security-relevant, not just convenience: any plugin that drops raw user
--- text into a search/replace pattern (a bookmark highlighter, a
--- find-under-cursor command) is one `.`/`*`/`[` in that text away from
--- matching something the user never asked for. `\V` (very-nomagic) turns
--- off every metacharacter except backslash itself, so escaping only has to
--- handle one character rather than the whole magic/nomagic/very-magic
--- table.
---
--- Usage:
--- ```lua
--- local vregex = require("lib.nvim.vregex")
---
--- vim.fn.search(vregex.literal(user_input))
--- vim.fn.matchadd("Search", vregex.literal(user_input, { whole_word = true }))
--- vim.fn.search(vregex.literal(user_input, { case = "ignore" }))
--- ```

require("lib.nvim.vregex.@types")

local M = {}

---Escape `text` so it has no special meaning under `\V` (very-nomagic) —
---i.e. every literal backslash in it. Does not add `\V` itself; use
---`M.literal` for a ready-to-use pattern.
---@nodiscard
---@param text string
---@return string
function M.escape(text)
  return (text:gsub("\\", "\\\\"))
end

---Build a `\V`-prefixed Vim-regex pattern that matches `text` literally.
---@nodiscard
---@param text string
---@param opts? Lib.Vregex.LiteralOpts
---@return string pattern
function M.literal(text, opts)
  opts = opts or {}

  local body = M.escape(text)
  if opts.whole_word then
    -- `\<`/`\>` (word-boundary atoms) stay meaningful under `\V`: it only
    -- strips meaning from *unescaped* characters, and these are backslash-led.
    body = "\\<" .. body .. "\\>"
  end

  local pattern = "\\V" .. body
  if opts.case == "ignore" then
    pattern = "\\c" .. pattern
  elseif opts.case == "match" then
    pattern = "\\C" .. pattern
  end

  return pattern
end

---@type Lib.Vregex
return M
