---@meta
---@module 'lib.nvim.debounce.@types'

---Handle returned by `require("lib.nvim.debounce").new(fn, ms)`.
---@class Lib.Debounce.Handle
---@field call fun(...:any) Reset the timer; fires `fn` with these args after `ms`
---@field cancel fun() Stop and close the pending timer, if any (safe to repeat)

---Options for `require("lib.nvim.debounce.buffer").new(fn, opts)`.
---@class Lib.Debounce.BufferOpts
---@field ms? integer Base delay in milliseconds (default `200`)
---@field adaptive? boolean Scale delay by buffer line count (default `false`)
---@field cleanup_events? string[] Autocmd events that cancel+forget a buffer's timer (default `{ "BufDelete", "BufWipeout" }`)

---Handle returned by `require("lib.nvim.debounce.buffer").new(fn, opts)`.
---@class Lib.Debounce.BufferHandle
---@field call fun(bufnr:integer, ...:any) Reset `bufnr`'s timer; fires `fn(bufnr, ...)` after the (possibly adaptive) delay
---@field cancel fun(bufnr:integer) Stop and close `bufnr`'s pending timer, if any
---@field cancel_all fun() Stop and close every tracked timer
