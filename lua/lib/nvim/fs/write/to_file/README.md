Writes `content` to `path`, creating the parent directory (via `vim.fn.mkdir(dir,
"p")`) if needed. Truncates any existing file (`"wb"` mode) — for appending
instead, see `lib.nvim.fs.write.append`.

A trailing newline is appended to `content` when it doesn't already end with
one, so callers writing line-oriented text don't need to track that
themselves. Returns `ok, err`: `err` is `nil` on success; on failure it names
the reason (`"Invalid directory for path: …"`, `"mkdir failed: …"`, or `"open
failed: …"`).

Opens the file in **binary** mode deliberately: Lua's `io.open` in text mode
(`"w"`) silently rewrites every `\n` in `content` to `\r\n` on Windows, which
would make writes inconsistent with the libuv-based async counterpart
(`lib.nvim.fs.write.async`). Binary mode keeps writes byte-exact and
consistent across platforms.
