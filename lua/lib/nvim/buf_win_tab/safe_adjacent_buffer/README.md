`M.save_last_normal_buffer()` force-saves (`:w!`) the most relevant *normal*
file buffer, without ever touching the current buffer — built for callers
whose current buffer is something like a Neo-tree sidebar that should never
itself be written.

Selection order: the alternate buffer (`#`) if it qualifies as normal,
otherwise the most recently used buffer (scanning `nvim_list_bufs()` in
reverse) that qualifies. If none qualifies, it does nothing — silently, no
error.

A buffer qualifies as "normal" here if it is valid, `buflisted`, has
`buftype == ""`, and has a non-empty name. Note this module keeps its own
private copy of that check, distinct from
`lib.nvim.buf_win_tab.normal_buffer`'s `is_normal_file_buffer`: this one does
not require the buffer to be loaded or backed by a readable file on disk, so
the two are not interchangeable.
