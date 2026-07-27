---@meta
---@module 'lib.nvim.ui.statusline.@types'

---How a badge is drawn.
---@alias Lib.UI.Statusline.Mode
---| "auto"       Pick per `laststatus`: "statusline", or "float" once it is 3.
---| "statusline" Window-local `&statusline`; invisible under `laststatus = 3`.
---| "float"      One-line unfocusable float over the window's last row.

---Horizontal placement within the line.
---@alias Lib.UI.Statusline.Align "left"|"center"|"right"

---@class Lib.UI.Statusline.Opts
---@field mode   Lib.UI.Statusline.Mode?  Drawing strategy. Default "auto".
---@field align  Lib.UI.Statusline.Align? Placement within the line. Default "left".
---@field hl     string?                  Highlight group for the badge text; overridable per `set`.
---@field zindex integer?                 Float mode only: stacking order. Default 30.

---A live badge. Dot syntax — the state lives in a closure, there is no `self`.
---@class Lib.UI.Statusline.Segment
---@field mode    fun(): "statusline"|"float" # The resolved strategy (never "auto").
---@field text    fun(): string # Current badge text ("" when cleared).
---@field set     fun(text: string, hl?: string) # Show plain `text`; statusline items are escaped, not interpreted.
---@field clear   fun() # Hide the badge without detaching.
---@field refresh fun() # Redraw in place (e.g. after the window moved).
---@field detach  fun() # Remove the badge and restore the previous `&statusline`.

---@class Lib.UI.Statusline
---@field attach       fun(winid: integer, opts?: Lib.UI.Statusline.Opts): Lib.UI.Statusline.Segment?, string?
---@field is_global    fun(): boolean # True when `laststatus = 3` (no per-window statusline exists).
---@field resolve_mode fun(mode?: Lib.UI.Statusline.Mode): "statusline"|"float"
