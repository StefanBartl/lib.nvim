Moves the current buffer out of the current tab and into a new (or the next)
tab, leaving the original tab showing something else instead of closing.

Steps, in order:

1. Records the current buffer, cursor position, and tab number.
2. Picks a replacement buffer for the original tab: the alternate buffer
   (`#`) if it exists and isn't the buffer being moved, otherwise the first
   other *loaded, listed* buffer found via `getbufinfo`; if none exists, a
   fresh empty buffer is created.
3. Replaces the moved buffer with that replacement in every window of the
   current tab that was showing it.
4. Switches to the next tab if one already exists after the current position,
   otherwise opens a new tab at the end (`:$tabnew`) — then sets the moved
   buffer as current there.
5. Restores the original cursor position in the new tab (best-effort, via
   `pcall`).
6. Schedules (`vim.schedule`) a sweep of every tab that deletes any
   now-unmodified, unnamed, empty buffer left behind — cleaning up the
   `[No Name]` buffers that `nvim_win_set_buf` can leave in emptied windows.

Takes no arguments and returns nothing; it acts on the current buffer/window/tab.
