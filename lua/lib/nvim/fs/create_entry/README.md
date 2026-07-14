# `lib.nvim.fs.create_entry`

Create a file or directory relative to a parent directory — the shared core
behind "create file/folder" picker actions (Telescope, fzf-lua, snacks).

A trailing separator on `name` selects directory creation (`mkdir -p`);
otherwise a new empty file is created, creating parent directories as needed.
Pure filesystem side effect only — no `notify`, no buffer opening. Callers
decide how to report the result and whether to open the created file.

## Usage

```lua
local create_entry = require("lib.nvim.fs.create_entry")

local ok, kind, path = create_entry("/repo/src", "new_file.lua")
-- ok=true, kind="file", path="/repo/src/new_file.lua"

local ok2, kind2, path2 = create_entry("/repo/src", "sub/dir/")
-- ok2=true, kind2="directory", path2="/repo/src/sub/dir"

local ok3, kind3, err = create_entry("/repo/src", "new_file.lua")
-- ok3=false, kind3=nil, err="file already exists: ..."
```

## Returns

| # | Type                   | Meaning                                              |
|---|-------------------------|-------------------------------------------------------|
| 1 | `boolean`               | `true` on success                                     |
| 2 | `"file"\|"directory"?`  | What was created, `nil` on failure                    |
| 3 | `string?`                | Absolute path on success, error message on failure    |
