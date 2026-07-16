# `lib.nvim.fs.write.batch`

Write many files asynchronously and get a single callback once **all** of them
have settled — successfully or not. Built on
[`lib.nvim.fs.write.async`](../async/README.md).

`results` is index-aligned with `entries`: `results[i]` always describes
`entries[i]`, regardless of the order in which the individual writes actually
completed.

## Usage

```lua
local write_batch = require("lib.nvim.fs.write.batch")

write_batch({
  { path = "/tmp/a.txt", content = "alpha" },
  { path = "/tmp/b.txt", content = "beta" },
}, function(all_ok, results)
  if all_ok then
    vim.notify("wrote " .. #results .. " files")
  else
    for _, r in ipairs(results) do
      if not r.ok then
        vim.notify(r.path .. ": " .. tostring(r.err), vim.log.levels.ERROR)
      end
    end
  end
end)
```

## Callback arguments

| # | Type      | Meaning                                                     |
|---|-----------|-------------------------------------------------------------|
| 1 | `boolean` | `true` only if every entry was written successfully          |
| 2 | `table[]` | Per-entry `{ path, ok, err }`, index-aligned with `entries`   |
