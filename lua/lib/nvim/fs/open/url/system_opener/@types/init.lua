---@meta
---@module 'lib.nvim.fs.open.url.system_opener.@types'

---@class AutoCmds.General.MD.GotoFile.Cfg
---@field enable_windows_opener? boolean Enable the Windows `cmd.exe /c start` opener (default true)
---@field open_cmd_mac? string[] Override the macOS open command (default `{ "open", url }`)
---@field open_cmd_unix? string[] Override the Linux open command (default `{ "xdg-open", url }`)

---@class Lib.Fs.Open.Url.SystemOpener
---@field open fun(url: string, cfg?: AutoCmds.General.MD.GotoFile.Cfg): boolean
---@field is_ike fun(s: string): boolean
