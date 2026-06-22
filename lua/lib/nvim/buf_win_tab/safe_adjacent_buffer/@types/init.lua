---@meta
---@module 'lib.nvim.buf_win_tab.safe_adjacent_buffer.@types'
-- =========================================================
-- Safe Adjacent Buffer Types
-- =========================================================

---@class Lib.BufWinTab.SafeAdjacentBuffer
--- Helper to force-save the last usable file buffer via :w!
--- Useful for plugin UIs (neo-tree) that need to save adjacent editor buffer.
---
--- Use Case:
---   When in neo-tree/plugin buffer and want to save the "real" file buffer
---   without switching windows or changing focus.
---
--- Strategy:
---   1. Try alternate buffer (#)
---   2. Fallback: iterate buffers in last-used order
---   3. Skip current buffer, special buftypes, unlisted, unnamed
---
---@field save_last_normal_buffer fun(): nil # Force-save last relevant file buffer using :w! Never saves current buffer. Silently does nothing if no suitable buffer found. Uses nvim_buf_call to execute in buffer context without changing focus.

return {}
