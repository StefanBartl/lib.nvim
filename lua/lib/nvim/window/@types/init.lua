---@meta
---@module 'lib.nvim.window.@types'

---@class Lib.Window.NiceQuitOpts
---@field keys? string[] Normal-mode lhs keys that close the window (default `{ "q", "<Esc>" }`)
---@field force? boolean Discard unsaved changes when closing (default `false`)

---@class Lib.Window.SetTitleOpts
---@field pos? "left"|"center"|"right" `title_pos` for the floating window

---@class Lib.Window.CloseOnFocusLostOpts
---@field events? string[] Autocmd events that count as focus loss (default `{ "WinLeave", "BufLeave" }`)
---@field force? boolean Discard unsaved changes when closing (default `true`)

---@class Lib.Window.MakeScratchOpts
---@field lines? string[] Initial buffer content (default empty)
---@field width? integer Float width; default sizes to content, clamped to editor
---@field height? integer Float height; default is line count, clamped to editor
---@field relative? "editor"|"cursor"|"win" Anchor for the float (default `"editor"`)
---@field row? integer Explicit row; default centers on the editor
---@field col? integer Explicit column; default centers on the editor
---@field border? string|string[] Border style passed to `nvim_open_win` (default `"rounded"`)
---@field title? string Float title (only shown with a border)
---@field title_pos? "left"|"center"|"right" `title_pos` for the float title
---@field focusable? boolean Whether the float is focusable (default `true`)
---@field enter? boolean Focus the new window on creation (default `true`)
---@field zindex? integer Stacking order for the float
---@field filetype? string Buffer `filetype`
---@field modifiable? boolean Keep the buffer modifiable (default `false`, i.e. read-only)
---@field nice_quit? boolean|Lib.Window.NiceQuitOpts Attach `q`/`<Esc>` close behaviour
---@field wo? table<string, any> Window-local option overrides
---@field bo? table<string, any> Buffer-local option overrides

---Fluent wrapper returned by `require("lib.nvim.window").attach(winid)`.
---Call methods with dot syntax; `winid` is bound internally.
---@class Lib.Window.Handle
---@field winid integer
---@field nice_quit fun(opts?: Lib.Window.NiceQuitOpts): boolean
---@field set_title fun(title: string|nil, opts?: Lib.Window.SetTitleOpts): boolean
---@field close_on_focus_lost fun(opts?: Lib.Window.CloseOnFocusLostOpts): integer|nil
---@field center fun(): boolean

---@class Lib.Window
---@field nice_quit fun(winid: integer, opts?: Lib.Window.NiceQuitOpts): boolean
---@field set_title fun(winid: integer, title: string|nil, opts?: Lib.Window.SetTitleOpts): boolean
---@field make_scratch fun(opts?: Lib.Window.MakeScratchOpts): integer|nil, integer|nil
---@field close_on_focus_lost fun(winid: integer, opts?: Lib.Window.CloseOnFocusLostOpts): integer|nil
---@field center fun(winid: integer): boolean
---@field attach fun(winid: integer): Lib.Window.Handle

return {}
