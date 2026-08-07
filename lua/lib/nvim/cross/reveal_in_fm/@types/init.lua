---@meta
---@module 'lib.nvim.cross.reveal_in_fm.@types'

---Options for `lib.nvim.cross.reveal_in_fm`.
---@class Lib.Cross.RevealInFm.Opts
---@field reveal boolean?               Select a file target inside its parent directory (default true). false → open the parent directory without selecting. Directories are always navigated into.
---@field command (string|string[])?    Launcher override (e.g. "thunar" or { "dolphin", "--select" }). The resolved path is appended as the last argument and platform dispatch is skipped.
---@field reuse boolean?                Windows/WSL only: navigate an already-open Explorer window to the target instead of opening another one (default false). Ignored when `command` is set, and a file target cannot be selected this way — Explorer's Navigate2 takes a folder.

return {}
