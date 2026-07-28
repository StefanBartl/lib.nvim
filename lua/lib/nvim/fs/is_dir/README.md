`vim.uv.fs_stat(p)` and check `st.type == "directory"`. Returns `true` only
when `p` exists and is a directory; returns `false` for a missing path, a
regular file, a symlink to a file, or any `fs_stat` failure — the stat error
is silently discarded, never raised.
