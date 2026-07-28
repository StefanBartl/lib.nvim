Validates a bare *filename* (not a full path) for filesystem safety, returning
`ok, err` — `err` is `nil` when `ok` is `true`, otherwise a short reason
string.

Rejects: `nil` (`"filename is nil"`), any non-string (`"filename must be a
string"`), the empty string (`"filename is empty"`), a whitespace-only string
(`"filename is only whitespace"`), and a name containing any of
`` \ / : * ? " < > | `` or an embedded NUL byte (`"filename contains invalid
characters"`).

The rejected character set is exactly what Windows forbids in a filename.
That set is also rejected on POSIX, even though POSIX itself only forbids `/`
and NUL — staying cross-platform-safe here is worth more than allowing the
few extra bytes POSIX would technically permit.

Upstreamed from reposcope.nvim's `utils.protection.is_valid_filename` (same
rules), to close a gap in `lib.nvim.fs.create_entry`: that module previously
only checked for a non-empty string, so a name containing one of these
characters failed at the raw `mkdirp`/`io.open` syscall instead of with a
clean message before attempting it.
