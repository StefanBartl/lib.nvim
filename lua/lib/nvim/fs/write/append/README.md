Appends `content` to a file, creating the parent directory (via `vim.fn.mkdir(dir,
"p")`) if needed. Sibling of [`lib.nvim.fs.write.to_file`](../to_file/README.md),
which truncates (`"w"`); this opens in append mode (`"a"`) instead.

A trailing newline is appended to `content` when it doesn't already end with
one, so callers can append line-oriented records without tracking separators
themselves. Returns `ok, err`: `err` is `nil` on success; on failure it names
the reason (`"Invalid directory for path: …"`, `"mkdir failed: …"`, or `"open
failed: …"`).

Opens in **binary** mode (`"ab"`), matching `to_file`'s fix: text mode (`"a"`)
silently rewrites every `\n` in `content` to `\r\n` on Windows.
