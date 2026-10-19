---@module 'lib.nvim.fs.etag'
--- The version tag of some bytes: what a later write compares against (compare-and-set).
---
--- `etag(text)` is `sha256:` and the first 16 hex digits of the SHA-256, the same for the same bytes on every
--- machine. `vim.fn.sha256` refuses a string with a NUL byte (it takes a Blob), so such a text is hashed with each NUL
--- replaced by two other bytes: still a function of the bytes, which is all a version tag and a content digest have
--- to be. (Two texts that differ only by a NUL versus `\255\254` hash equal; a version tag tolerates that.)
---
--- Not for a fast-event context: `vim.fn.sha256` raises E5560 there (`vim.schedule` first).
---
--- Moved here from `tasks_nvim.fsio.etag` / `fsio.sha256` (tasks.nvim@6bc8d99).
---
---```lua
--- local etag = require("lib.nvim.fs.etag")
--- etag.of("hello")      --> "sha256:2cf24dba5fb0a30e"
--- etag.sha256("hello")  --> 64 hex digits
---```

require("lib.nvim.fs.etag.@types")

local M = {}

---@param text string
---@return string  # 64 hex digits
function M.sha256(text)
  -- the guard is a plain byte search (memchr speed): the `%z` pattern class would run the pattern matcher once per
  -- byte and cost more than the hash itself on a text that has no NUL, which is nearly every text
  if text:find("\0", 1, true) then
    text = text:gsub("%z", "\255\254")
  end
  return vim.fn.sha256(text)
end

---@param text string
---@return string  # `sha256:` and 16 hex digits
function M.of(text)
  return "sha256:" .. M.sha256(text):sub(1, 16)
end

---@type Lib.Fs.Etag
return M
