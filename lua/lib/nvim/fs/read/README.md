# `lib.nvim.fs.read`

Read the whole contents of a file at `path` into a string — the read-side
counterpart to `lib.nvim.fs.write.to_file`. Pure filesystem side effect only,
no `notify`; callers decide how to report failures.

## Usage

```lua
local read = require("lib.nvim.fs.read")

local content, err = read("/repo/README.md")
if not content then
  vim.notify("read failed: " .. err, vim.log.levels.ERROR)
  return
end

print(content)
```

## Returns

| # | Type       | Meaning                                    |
|---|------------|----------------------------------------------|
| 1 | `string?`  | File content on success, `nil` on failure    |
| 2 | `string?`  | `nil` on success, error message on failure   |
