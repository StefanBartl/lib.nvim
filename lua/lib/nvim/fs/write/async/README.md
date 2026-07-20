# `lib.nvim.fs.write.async`

Asynchronous counterpart to [`lib.nvim.fs.write.to_file`](../to_file/init.lua).
Creates the parent directory synchronously (same `mkdir -p` semantics), then
opens, writes and closes the file through libuv so a large write never blocks
the editor.

The callback is invoked on the main loop (wrapped in `vim.schedule`), so it is
safe to call `vim.api.*` from inside it.

## Usage

```lua
local write_async = require("lib.nvim.fs.write.async")

write_async("/tmp/report.txt", "hello world\n", function(ok, err)
  if ok then
    vim.notify("written")
  else
    vim.notify("write failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end)
```

## Callback arguments

| # | Type      | Meaning                                  |
|---|-----------|------------------------------------------|
| 1 | `boolean` | `true` on success                        |
| 2 | `string?` | Error message on failure, `nil` on success |
