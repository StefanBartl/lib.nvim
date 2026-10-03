# `lib.nvim.markdown.frontmatter`

Read and surgically update the **flat-YAML frontmatter block** at the top of a
Markdown text or file.

```
lib.nvim.markdown.frontmatter/
├── init.lua       -- the whole module (parse, patch, serialize, file helpers)
└── @types/        -- LuaLS types (Lib.Markdown.Frontmatter.*)
```

Entry point is `require("lib.nvim.markdown.frontmatter")`.

## The contract

A cheap, predictable reading beats a general one. The module understands one
shape and keeps everything else verbatim.

* **A block** is a leading `---` line (after an optional UTF-8 BOM), `key: value`
  lines, and the next `---` line. The first line of the text must be the
  opening delimiter; a `---` later in the body is body. A block that is never
  closed is *not* a block (`parsed.unterminated`).
* **Values:** a plain or quoted (`"..."` / `'...'`) string, `true`/`false`
  (returned as booleans), or an inline list `[a, b, "c, d"]` (returned as
  `string[]`). Number-looking and date-looking values stay **strings**
  (`prio: 2` reads as `"2"`); `{ numbers = true }` turns number-looking plain
  values into numbers, dates are always strings. An empty value reads as `""`.
* **Not supported:** nesting, multi-line values, block scalars (`|`, `>`),
  flow maps (`{...}`), anchors/aliases/tags. A key with such a value is listed
  in `parsed.opaque` (key -> reason), is **not** in `meta`, and a patch that
  touches it is refused. Its lines are never altered.
* **Comments:** a `# comment` line is kept as-is. A trailing comment needs
  whitespace before the `#` (as in YAML): `status: open # why` reads
  `"open"`, and `title: Fix #12` reads `"Fix"` -- quote the value
  (`title: "Fix #12"`) when the `#` is part of it. A rewritten line keeps its
  trailing comment.
* **Roundtrip:** `serialize(parse(text)) == text`, byte for byte, for *any*
  string (BOM, LF, CRLF, mixed endings, no trailing newline, junk).
* **Never throws on text.** `parse` returns a result with `warnings` for lines
  it did not understand; only a non-string argument gives `nil, err`.

## Usage

```lua
local fm = require("lib.nvim.markdown.frontmatter")

local parsed = fm.parse(text)            -- never raises on malformed text
fm.get(parsed, "status")                 -- "open"
parsed.meta.tags                         -- { "ui", "pickers" }
parsed.order                             -- keys in file order
parsed.warnings                          -- lines kept verbatim but not understood

-- Change only what is named; every other byte comes back identical.
local new_text, err = fm.update_text(text, {
  status = "doing",                      -- rewrite in place
  created = "2026-10-03",                -- new key: appended before the closing ---
  prio = fm.REMOVE,                      -- delete the key's line(s)
  tags = { "ui", "release" },            -- written as [ui, release]
})

-- On a file (atomic: temp file + rename; nothing is written when nothing changes).
local ok, err2 = fm.update("/vault/tasks/x.md", { status = "done" })
local parsed2, err3 = fm.read("/vault/tasks/x.md")

-- A text without a block.
fm.update_text(text, { title = "T" }, { create = true })  -- block added in front
fm.add_block(text, { title = "T" })                      -- same, fails if a block exists
```

## API

| Function | Returns | Notes |
|---|---|---|
| `parse(text, opts?)` | `parsed` or `nil, err` | `opts.numbers`. `err` only for non-string input |
| `get(parsed, key, default?)` | value | a stored `false` is returned as `false` |
| `patch(parsed, patch, opts?)` | `ok, err` | in place, all-or-nothing |
| `set(parsed, key, value, opts?)` | `ok, err` | one-key `patch` |
| `serialize(parsed)` | `string` | the text the parse describes |
| `update_text(text, patch, opts?)` | `string` or `nil, err` | parse + patch + serialize |
| `add_block(text, meta?, opts?)` | `string` or `nil, err` | `meta` empty gives an empty block |
| `read(path, opts?)` | `parsed` or `nil, err` | via `lib.nvim.fs.read` |
| `update(path, patch, opts?)` | `ok, err` | atomic, byte-exact, skips an unchanged write |
| `REMOVE` | `vim.NIL` | patch value that deletes a key |

`parsed` fields: `has_block`, `unterminated`, `bom`, `eol` (`"\n"`/`"\r\n"`),
`meta`, `order`, `body`, `warnings`, `raw_lines`, `opaque`. (`entries`,
`by_key`, `numbers`, `open`/`close` are the machinery behind `serialize`; use
the functions rather than editing them.)

### Patches

A patch is a **map** `{ key = value }` (applied in sorted key order, so the
output is deterministic) or a **list of pairs** `{ { "key", value }, ... }`
(applied in the given order -- use it when the order of new keys matters).

* A **value** sets the key. An existing line is rewritten in place (the key
  keeps its position); a new key is appended after the last block line. An
  equal value touches nothing, not even its quote style.
* **`fm.REMOVE`** (`vim.NIL`) deletes every line of that key; removing an
  absent key is a no-op. Because `nil` cannot live in a Lua table, this is the
  only way to say "delete". `false` is a boolean value, never a removal.
* Strings are written bare when they read back as the same string, otherwise
  double-quoted (`a: b`, `x #y`, `true`, leading `[`, empty, ...). Newlines and
  tabs become `\n`/`\t`. Other control characters are refused.
* List items are strings; numbers and booleans in a list are written as text.
* Keys match `[%w_][%w_.-]*`; anything else is refused.
* A bad entry anywhere in the patch fails the whole patch and changes nothing.

### Line endings and layout

New lines use the line ending of the opening `---` (CRLF files stay CRLF). A
block created by `create = true` / `add_block` goes in front of the text (after
a BOM), its line ending taken from the text's first line. The body is never
touched.

## What it is not

No notifications and no UI: errors come back as `nil, err` / `false, err` and
the caller decides how loud to be. Not a YAML parser; if you need nesting, use
a real one (or `vim.json` for JSON files, see `lib.nvim.fs.json`).
