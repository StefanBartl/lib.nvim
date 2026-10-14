# `lib.nvim.fs.etag`

The **version tag of some bytes**: what a later write compares against
(compare-and-set). Moved here from `tasks_nvim.fsio.etag` / `sha256`
(tasks.nvim@921a0c4).

```lua
local etag = require("lib.nvim.fs.etag")

etag.of("hello")      --> "sha256:2cf24dba5fb0a30e"   (the first 16 hex digits)
etag.sha256("hello")  --> "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
```

The same bytes give the same tag on every machine, so a tag read by one process
can be checked by another (an app shows a file, the engine refuses the write if
the file changed since).

`vim.fn.sha256` refuses a string with a NUL byte (it takes a Blob). A text with
NUL is hashed with each NUL replaced by the two bytes `\255\254`: still a
function of the bytes, which is all a version tag has to be. (Two texts that
differ only by a NUL versus `\255\254` hash equal; a tag tolerates that.)

Not for a fast-event context (a uv timer or another libuv callback):
`vim.fn.sha256` raises `E5560` there, so `etag.of` and `etag.sha256` do too
(`vim.schedule` first).

| | |
|---|---|
| `sha256(text)` | 64 lowercase hex digits. |
| `of(text)` | `sha256:` and the first 16 digits. |
