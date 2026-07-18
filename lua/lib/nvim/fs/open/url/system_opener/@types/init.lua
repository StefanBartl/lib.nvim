---@meta
---@module 'lib.nvim.fs.open.url.system_opener.@types'

---@class AutoCmds.General.MD.GotoFile.Cfg
---@field prefer_ui_open? boolean Try `vim.ui.open` (Neovim 0.10+) before the per-OS argv dispatch (default true). Ignored when `on_exit` is set.
---@field enable_windows_opener? boolean Enable the Windows `cmd.exe /c start` opener (default true)
---@field open_cmd_mac? string[] Override the macOS open command (default `{ "open", url }`)
---@field open_cmd_unix? string[] Override the Linux open command (default `{ "xdg-open", url }`)
---@field open_cmd_wsl? string[] Override the WSL open command (default `{ "wslview", url }`, used only when `wslview` is executable)
---@field on_exit? fun(code: integer) Observe the opener's exit code. Runs the job attached and skips `vim.ui.open`.

---@class Lib.Fs.Open.Url.SystemOpener
---@field open fun(url: string, cfg?: AutoCmds.General.MD.GotoFile.Cfg): boolean
---@field is_like fun(s: string): boolean
---@field is_ike fun(s: string): boolean Deprecated alias of `is_like`.
