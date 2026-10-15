# `lib.nvim.contract.echo`

How a text of a client's request is shown in a refusal. The names in a request (a method, a field, a parameter, an
operation field) are the client's; a refusal that repeats one must not hand a control character, an invalid byte
sequence or a megabyte of text to the terminal the message ends up on.

```lua
local clip = require("lib.nvim.contract.echo").clip

clip("list")                       --> "list"
clip(string.rep("n", 500))         --> 59 characters and an ellipsis (at most `MAX` = 60, never cut inside a character)
clip("a" .. string.char(27) .. "b") --> the ESC written out as an escape, so the message prints as it is
```

`clip(text)` returns a string that is short (at most 60 characters), valid UTF-8 (invalid bytes are scrubbed) and
printable: a control character, a C1 control (U+0080..U+009F) and the Unicode line separators are written as escapes
(`\x1b`, `\u009b`, `\u2028`). Only the first 244 bytes are looked at, however long the text is.

`contract.ops` and `contract.api` both use it for what they echo (`unknown method '...'`, `unknown field '...' in the
request`, `... takes no parameter '...'`, and the operation fields of a refusal), so the rule is one.
