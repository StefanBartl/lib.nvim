Computes `path` relative to `base`, treating `base` as a directory.

Both arguments are first made absolute (`vim.fn.fnamemodify(_, ":p")`) and
normalized to forward slashes, so mixed `/`/`\` input works on Windows. When
`path` lives under `base`, the `base` prefix (and its separating slash) is
stripped. When `path` equals `base`, the result is `"."`. When `path` does
not live under `base`, `..` segments climb from `base` to the nearest common
ancestor and back down to `path` (POSIX-style `relpath` behaviour) — unless
the two paths don't share a root at all (e.g. different Windows drive letters,
or differing UNC hosts), in which case there is no relative form and the
absolute, normalized `path` is returned unchanged.
