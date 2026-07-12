---@meta
---@module 'lib.nvim.ui.kit.@types'

--- Semantic highlight groups of a theme. Each is either a highlight-group name
--- to link to (string) or an explicit highlight spec (Lib.Highlight.Opts).
---@class Lib.UI.Kit.ThemeHighlights
---@field normal    string|Lib.Highlight.Opts # body            (default: link NormalFloat)
---@field border    string|Lib.Highlight.Opts # border          (default: link FloatBorder)
---@field title     string|Lib.Highlight.Opts # title           (default: link FloatTitle)
---@field selection string|Lib.Highlight.Opts # current item    (default: link PmenuSel)
---@field accent    string|Lib.Highlight.Opts # focused/active  (default: link Special)
---@field muted     string|Lib.Highlight.Opts # hints/secondary (default: link Comment)
---@field error     string|Lib.Highlight.Opts # error/destructive (default: link DiagnosticError)

--- A resolved theme: design tokens read by every component.
---@class Lib.UI.Kit.Theme
---@field border string|string[]                 # nvim_open_win border
---@field ascii_border boolean                   # true when the border uses ASCII glyphs
---@field padding { x: integer, y: integer }
---@field zindex { base: integer, popup: integer, toast: integer, menu: integer }
---@field title_pos "left"|"center"|"right"
---@field dims { min_w: integer, max_w: integer, min_h: integer, max_h: integer }
---@field hl Lib.UI.Kit.ThemeHighlights

--- A theme argument accepted by surfaces/components: a preset name, a partial
--- override table (deep-merged over the active default), or nil (active default).
---@alias Lib.UI.Kit.ThemeArg string|table|nil

--- Options for `kit.surface.open`.
---@class Lib.UI.Kit.SurfaceOpts
---@field lines? string[]        # initial content
---@field theme? Lib.UI.Kit.ThemeArg
---@field title? string
---@field title_pos? "left"|"center"|"right"  # overrides the theme
---@field width? integer
---@field height? integer
---@field relative? "editor"|"cursor"|"win"
---@field row? integer
---@field col? integer
---@field zindex? integer        # overrides the theme's popup zindex
---@field enter? boolean         # focus the new window (default true)
---@field focusable? boolean
---@field nice_quit? boolean|Lib.Window.NiceQuitOpts  # bind q/<Esc> to close
---@field filetype? string
---@field modifiable? boolean
---@field on_close? fun()        # called once when the window closes (any cause)
---@field wo? table<string, any>
---@field bo? table<string, any>

--- Handle returned by `kit.surface.open` — a themed float + lifecycle.
---@class Lib.UI.Kit.Surface
---@field winid integer
---@field bufnr integer
---@field set_lines fun(self: Lib.UI.Kit.Surface, lines: string[])
---@field set_title fun(self: Lib.UI.Kit.Surface, title: string|nil)
---@field focus fun(self: Lib.UI.Kit.Surface)
---@field on_close fun(self: Lib.UI.Kit.Surface, cb: fun())
---@field is_valid fun(self: Lib.UI.Kit.Surface): boolean
---@field close fun(self: Lib.UI.Kit.Surface)

--- Options for the `note` component / `kit.popup({ type = "note" })`.
---@class Lib.UI.Kit.NoteOpts
---@field title? string
---@field message string|string[]
---@field theme? Lib.UI.Kit.ThemeArg
---@field timeout? integer        # auto-close after N ms (0/nil = stay)
---@field width? integer
---@field height? integer
---@field relative? "editor"|"cursor"|"win"

--- Options for `kit.setup`.
---@class Lib.UI.Kit.SetupOpts
---@field default? string                       # active preset name
---@field presets? table<string, table>         # user-registered presets

--- The `lib.nvim.ui.kit` module.
---@class Lib.UI.Kit
---@field setup fun(opts?: Lib.UI.Kit.SetupOpts)
---@field popup fun(opts: table): any            # dispatch on opts.type ("note" in Phase 1)
---@field note fun(opts: Lib.UI.Kit.NoteOpts): Lib.UI.Kit.Surface
---@field surface Lib.UI.Kit.SurfaceModule
---@field theme Lib.UI.Kit.ThemeModule

---@class Lib.UI.Kit.SurfaceModule
---@field open fun(opts?: Lib.UI.Kit.SurfaceOpts): Lib.UI.Kit.Surface|nil

---@class Lib.UI.Kit.ThemeModule
---@field resolve fun(theme?: Lib.UI.Kit.ThemeArg): Lib.UI.Kit.Theme
---@field apply fun(winid: integer, resolved: Lib.UI.Kit.Theme)
---@field setup fun(opts?: Lib.UI.Kit.SetupOpts)
---@field presets fun(): string[]

return {}
