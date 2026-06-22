---@module 'lib.nvim.buf_win_tab.capture.@types'

---@class BufWinCapture.Tag
---@field buf string|nil  -- Persistent buffer-local tag
---@field win string|nil  -- Ephemeral window-local tag

---@class BufWinCapture.Results
---@field bufs integer[]  -- Newly detected buffers
---@field wins integer[]  -- Newly detected windows

---@class BufWinCapture.Opts
---@field tag BufWinCapture.Tag|nil
---@field timeout integer|nil      -- Timeout in milliseconds
---@field interval integer|nil     -- Polling interval in milliseconds
---@field emit_event boolean|nil   -- Emit User event after capture

---@class Lib.BufWinTab.Capture
--- Deterministic capture of buffers and windows created by Ex commands.
--- Supports async creation, timeouts, multi-object capture, and User events.
---
--- Problem:
---   After executing Ex commands, there's no reliable way to know which
---   buffer/window was created. Current buffer/window may not be the new one.
---   Plugins create UI asynchronously, windows have no stable identifiers.
---
--- Solution:
---   • Snapshot state before command execution
---   • Compute delta after execution (with optional polling)
---   • Filter to focusable content windows only
---   • Tag captured objects for later retrieval
---
--- Design:
---   • Delta detection via state snapshots
---   • Async polling with configurable timeout/interval
---   • Filters non-focusable windows (borders, titles)
---   • Optional User autocommand emission
---
---@field capture fun(cmd: string, opts?: BufWinCapture.Opts, cb?: fun(result: BufWinCapture.Results)): BufWinCapture.Results|nil # Main API: capture buffers/windows created by Ex command. Synchronous if no callback provided (blocks until timeout). Asynchronous if callback provided (returns nil immediately). Returns BufWinCapture.Results with lists of new buffers and windows.

return {}
