# `lib.lua.strings`

Aggregates every string helper under `lib.lua.strings.*` onto one flat table.
Pure Lua throughout — no `vim` API — so it works outside Neovim too.
`init.lua` does the flattening itself (eager `require`s, not lazy), unlike
`lib.lua.tables`/`lib.lua.json` which go through `lib.lua.lazy`.

```lua
local strings = require("lib.lua.strings")
```

## Core: trim / split / case / pad ([`core.lua`](core.lua))

```lua
strings.trim("  hi  ")                  --> "hi"
strings.starts_with("hello", "he")      --> true
strings.ends_with("hello", "lo")        --> true
strings.contains("hello", "ell")        --> true
strings.split("a,b,,c", ",")            --> { "a", "b", "", "c" }
strings.join({ "a", "b" }, "-")         --> "a-b"
strings.replace_all("aXaXa", "X", "-")  --> "a-a-a"
strings.normalize_ws("  a   b  ")       --> "a b"
strings.capitalize("foo")               --> "Foo"
strings.uncapitalize("Foo")             --> "foo"
strings.slugify("Hello, World!")        --> "hello-world"
strings.kebab_case("Hello World")       --> "hello-world"
strings.snake_case("Hello World")       --> "hello_world"
strings.camel_case("foo bar-baz")       --> "fooBarBaz"
strings.pad_start("7", 3)               --> "  7"
strings.pad_end("7", 3)                 --> "7  "
strings.pad_center("7", 3)              --> " 7 "
strings.indent("a\nb", 2)               --> "  a\n  b"
strings.is_empty_or_space("  ")         --> true
strings.count_lines("a\nb\nc")          --> 3
```

`trim`/`is_empty_or_space` tolerate non-string input (`trim(nil) == ""`,
`is_empty_or_space(nil) == true`); the rest assume a real string.

**Gotcha:** `kebab_case`/`snake_case` only insert a separator at an existing
word boundary (start of string, or right after whitespace/`_`/`-`) that is
followed by an uppercase letter — they do **not** split a contiguous
camelCase/PascalCase run. `kebab_case("FooBar baz")` is `"foobar-baz"`, not
`"foo-bar-baz"`, and `kebab_case("fooBarBaz")` (no separators at all) is
`"foobarbaz"` with no dashes inserted. The underlying pattern is
`s:gsub("%f[%w]%u", "-%1")`: the frontier `%f[%w]` only fires on a transition
*into* a word character, so an uppercase letter preceded by another word
character (as in the `B` of `FooBar`) never matches.

`strings.dedent("  a\n  b")` strips the common leading whitespace shared by
every non-blank line (`"a\nb"`); `strings.dedent("  a\n    b")` only strips
the smaller common indent, preserving relative nesting (`"a\n  b"`). A string
with no common leading whitespace is returned unchanged.

## Patterns ([`patterns.lua`](patterns.lua))

```lua
strings.escape_lua_magic("a.b*c")      --> "a%.b%*c"
strings.find_plain("a.b", ".")         --> 2, 2   (plain find, no pattern magic)
strings.replace_plain("a.b.c", ".", "-")  --> "a-b-c"
strings.surround("x", "[", "]")        --> "[x]"
strings.strip_ansi("\27[31mred\27[0m") --> "red"
```

`strip_ansi` strips SGR color codes, OSC sequences terminated by BEL, stray
NUL bytes, and a broader CSI-like catch-all — tuned for raw subprocess relay
output, not just simple colored text.

## Links ([`links.lua`](links.lua))

```lua
strings.uri_decode("a%20b")              --> "a b"
strings.normalize_anchor("# Hello, World!")  --> "hello-world"
strings.has_scheme("mailto:x@y.com")     --> true
strings.is_web_url("https://x.com")      --> true (also ftp://, mailto:)
strings.url_under_cursor(line, col)      --> URL string under `col`, or nil
```

`url_under_cursor` matches `<https://...>` autolinks first, then bare
`https?://` URLs, trimming trailing punctuation (`)`, `]`, `.`, `,`, `;`,
`:`) off a bare-URL match.

## UTF-8 ([`utf8.lua`](utf8.lua))

Pure arithmetic (no bitwise ops) — works unmodified on Lua 5.1/LuaJIT.

```lua
strings.utf8_char_len(0xE2)     --> 3   (byte length implied by the lead byte)
strings.utf8_encode(0x1F600)    --> "😀" (4-byte UTF-8 string)
strings.utf8_decode("é", 1)     --> 233, 3   (codepoint, next byte index)
for cp, i in strings.utf8_iter("héllo") do ... end
```

## Encoding ([`encoding.lua`](encoding.lua))

```lua
strings.url_encode("a b/c")     --> "a%20b%2Fc"
strings.url_decode("a%20b")     --> "a b"
strings.base64_encode("hi")     --> "aGk="
strings.base64_decode("aGk=")   --> "hi"
```

## Distance ([`distance.lua`](distance.lua))

```lua
strings.levenshtein("kitten", "sitting")  --> 3
strings.similarity("kitten", "sitting")   --> 0.571... (1 - distance/max_len)
```

## Format ([`format.lua`](format.lua))

```lua
strings.format_bytes(1536)          --> "1.5 KB"
strings.format_bytes(1536, 0)       --> "2 KB"
strings.format_number(1234567)      --> "1,234,567"
strings.format_number(-42, ".")     --> "-42"
```

## Location parsing ([`location.lua`](location.lua))

```lua
strings.parse_location("src/a.lua:10:4")   --> { path = "src/a.lua", line = 10, col = 4 }
strings.parse_location("src/a.lua:10")     --> { path = "src/a.lua", line = 10, col = nil }
strings.parse_location("src/a.lua(10:4)")  --> same, "(line:col)" form
strings.parse_location("src/a.lua +10")    --> "path +line" form (grep/compiler-style)
strings.parse_location("nonsense")         --> nil
```

## Case shape ([`case.lua`](case.lua))

Complements `core.lua`'s case-*format* helpers: this is about detecting and
reapplying a word's existing shape, and about sentence-/title-casing whole
strings, not reformatting identifiers.

```lua
strings.case_shape("HELLO")          --> "upper"
strings.case_shape("Hello")          --> "capital"
strings.case_shape("hello")          --> "lower"
strings.case_shape("hELLo")          --> "mixed"
strings.apply_shape("world", "capital")  --> "World"
strings.change_case("hello world", "title")     --> "Hello World"
strings.change_case("Hello World", "sentence")  --> "Hello world"
```

## Wrap ([`wrap.lua`](wrap.lua))

```lua
strings.center_text("hi", 6)                --> "  hi  "
strings.center_text_lines({ "a", "bb" }, 4) --> { " a  ", " bb " }
```

## Display width ([`width.lua`](width.lua))

Everything above measures strings in **bytes**, which is correct for ASCII
and wrong for everything else: `#"日本"` is 6, but it occupies 4 terminal
columns. `width.lua` is the column-aware counterpart.

```lua
strings.display_width("日本")           --> 4  (6 bytes, 2 chars, 4 columns)
strings.display_width("a\tb")           --> 9  (tab advances to the next stop)
strings.display_width("a\tb", { tabstop = 4 }) --> 5
strings.char_width(0x65E5)              --> 2  (CJK)
strings.char_width(0x0301)              --> 0  (combining accent)
strings.truncate("日本語テキスト", 6)    --> "日本語", 6
strings.truncate("abcdefgh", 5, { ellipsis = "..." })  --> "ab...", 5
```

Padding lives on the submodule rather than the aggregator, because
`pad_start`/`pad_end`/`pad_center` on the aggregator are already taken by
the byte-based `core.lua` versions and silently swapping their semantics
would change existing callers' output:

```lua
strings.width.pad_end("日本", 6)    --> "日本  "   (column-aware)
strings.pad_end("日本", 6)          --> "日本"      (byte-based: 6 bytes already)
```

`truncate` never splits a character, and fits its `ellipsis` *inside* the
budget rather than overflowing it. A double-width character that would
straddle the limit is dropped whole, so a result can come out one column
narrower than requested.

**Inside Neovim, prefer `vim.fn.strdisplaywidth()`** — it is authoritative
and handles `'ambiwidth'`, `'listchars'` and the complete Unicode tables.
This module exists because `lib.lua.*` is editor-independent by definition
and cannot call `vim.fn`, and because `vim.fn` is unavailable in a
fast-event context where a pure-Lua helper still works. Its width tables
are a hand-maintained approximation covering the ranges that actually turn
up in source, filenames and UI strings; a codepoint outside them is
measured as single-width rather than raising.

## Remove prefix ([`remove_prefix.lua`](remove_prefix.lua))

```lua
strings.remove_prefix("vim.api.nvim_buf_set_lines", { "vim.api.", "vim.fn." })
  --> "nvim_buf_set_lines"
strings.remove_prefix("vim.fn.expand(...)")  -- list arg omitted -> {} -> no-op
```

Called with no second argument (or a non-table), it is a no-op — the default
blacklist (`vim.api.`, `vim.fn.`, `vim.uv.`) only applies when the caller
passes it explicitly, unlike most other helpers in this module which apply
their own defaults.

## Also see

`lib.lua.strings.transform` ([`transform/README.md`](transform/README.md))
re-exports a smaller subset of the functions above (casing/padding/trim only)
for callers that want just text transforms without the rest of this surface.
