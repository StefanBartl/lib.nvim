# `lib.nvim.config.repo_file`

Read a repository-local JSON config file and split its keys into `allowed`
(the repository's own business) and everything else, without deciding *how*
to warn about the latter — that stays yours. Extracted after
`documentation.nvim`'s `.docmap.json` loader and `lsp.nvim`'s
`.nvim-lsp.json` loader turned out to have independently built the exact
same read/decode/split shape.

This module deliberately does **not** find the file for you: an upward walk
from cwd (`vim.fs.find`, `lib.nvim.fs.find_upward_dir`), a fixed
`<root>/.foo.json`, or a project root a caller already resolved some other
way are all legitimate and already-solved elsewhere — bake one choice in
here and the other becomes a workaround instead of a parameter.

## Usage

```lua
local repo_file = require("lib.nvim.config.repo_file")

local ALLOWED = { servers = true, formatter = true }

local result, reason, detail = repo_file.load("/repo/.nvim-lsp.json", ALLOWED)
if not result then
  if reason == "empty" then
    -- a placeholder file; nothing to say
  elseif reason == "read_failed" then
    vim.notify(("cannot be read: %s"):format(detail), vim.log.levels.WARN)
  elseif reason == "invalid_json" then
    vim.notify(("invalid JSON: %s"):format(detail), vim.log.levels.WARN)
  elseif reason == "not_object" then
    vim.notify("expected a JSON object", vim.log.levels.WARN)
  end
  return
end

-- result.data    -> { servers = ... }  (only keys ALLOWED said yes to)
-- result.refused -> { "keymaps" }      (present in the file, not allowed)
```

## Returns

| Function              | Returns                                                              |
| ---------------------- | --------------------------------------------------------------------- |
| `M.load(path, allowed)` | `Result\|nil, reason\|nil, detail\|nil` — see below |

`Result` is `{ data: table<string, any>, refused: string[] }`. `data` holds
only the keys `allowed` accepted; `refused` lists the rest (sorted), whether
`data` ends up empty or not — a caller that wants "no keys survived" to mean
the same as "no file" checks `next(result.data) == nil` itself.

`reason` is one of `"empty"` / `"read_failed"` / `"invalid_json"` /
`"not_object"`, set only when `result` is `nil`. `detail` carries the
underlying message for `"read_failed"`/`"invalid_json"` only.

## What it does not do

- **No path resolution.** Pass an already-resolved absolute path.
- **No warning text.** `reason`/`detail` are yours to format — including
  whether "refused" deserves one combined message or a split between
  "a real option, wrong owner" and "not an option at all" (two categories
  `documentation.nvim`'s loader distinguishes and `lsp.nvim`'s doesn't;
  both are legitimate call-site decisions this module has no opinion on).
- **No `null`-as-sentinel.** A JSON `null` in the file is dropped from
  `data` entirely (`vim.json.decode`'s `luanil` option), not turned into
  `lib.lua.null`'s `NULL` — right for a config file's "no opinion" reading,
  wrong for `data`-shaped values a plugin re-encodes or displays.
