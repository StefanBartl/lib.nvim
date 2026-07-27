---@meta
---@module 'lib.nvim.fs.chdir.@types'

---Which directory scope a change applies to.
---@alias Lib.Fs.Chdir.Scope
---| "global"  `:cd`  — the global cwd (also clears a window-local one).
---| "tab"     `:tcd` — tab-local, for the current or `opts.tab` tabpage.
---| "win"     `:lcd` — window-local, for the current or `opts.win` window.

---Options for a scope-aware directory change.
---@class Lib.Fs.Chdir.Opts
---@field scope Lib.Fs.Chdir.Scope? Scope of the change. Default "global".
---@field win   integer?            Window to run the change in (`nvim_win_call`). Default: the current window.
---@field tab   integer?            Tabpage whose current window is borrowed to run the change; ignored when `win` is set.

---Change the working directory in an explicit scope. Never throws; returns
---`false, err` for an unusable path, scope, window or tabpage.
---@alias Lib.Fs.Chdir fun(path: string, opts?: Lib.Fs.Chdir.Opts): boolean, string?
