# `lib.nvim.vregex`

Build Vim-regex (`/`, `:s`, `matchadd`, `vim.fn.search`) patterns that match
a piece of text **literally** — no character in it is ever interpreted as a
metacharacter.

Security-relevant, not just convenience: any plugin that drops raw
user/arbitrary text into a search or replace pattern (a bookmark
highlighter, a find-under-cursor command, a "jump to this exact string"
feature) is one `.`/`*`/`[` in that text away from matching something the
user never asked for — a regex-injection bug, not just a cosmetic one.

## How it works

`\V` (very-nomagic) turns off every Vim-regex metacharacter except
backslash itself, so making a string match-safe only requires escaping one
character (`\` → `\\`) rather than the whole magic/nomagic/very-magic
table. Word-boundary atoms (`\<`, `\>`) still work under `\V` because they
are backslash-led — `\V` only strips meaning from *unescaped* characters.

## Usage

```lua
local vregex = require("lib.nvim.vregex")

vim.fn.search(vregex.literal(user_input))
--> matches user_input literally, wherever it occurs

vim.fn.matchadd("Search", vregex.literal(user_input, { whole_word = true }))
--> only matches user_input as a whole word

vim.fn.search(vregex.literal(user_input, { case = "ignore" }))
--> case-insensitive literal match, regardless of 'ignorecase'
```

`escape(text)` is the lower-level building block — just the backslash
escaping, no `\V` prefix — for composing a literal fragment into a larger
hand-built pattern.

## API

| Function | Meaning |
| --- | --- |
| `vregex.escape(text)` | Escape `text` for safe use inside a `\V` pattern (doubles backslashes) |
| `vregex.literal(text, opts?)` | Build a ready-to-use `\V`-prefixed pattern matching `text` literally |

`opts` for `literal`:

| Field | Default | Meaning |
| --- | --- | --- |
| `whole_word` | `false` | Wrap with `\<`/`\>` so the match doesn't land mid-word |
| `case` | respects `'ignorecase'` | `"ignore"` prefixes `\c`, `"match"` prefixes `\C` |
