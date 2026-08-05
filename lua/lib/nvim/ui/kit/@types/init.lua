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

--- Options for the `viewer` component / `kit.popup({ type = "viewer" })`.
---@class Lib.UI.Kit.ViewerOpts
---@field title? string
---@field lines? string[]                                # alias: message
---@field message? string|string[]
---@field theme? Lib.UI.Kit.ThemeArg
---@field width? integer
---@field height? integer
---@field relative? "editor"|"cursor"|"win"
---@field enter? boolean                                  # focus + allow scrolling (default true)
---@field filetype? string
---@field close_on_focus_lost? boolean                    # dismiss on WinLeave/BufLeave (default true)

--- One entry of a `kit.menu`.
---@class Lib.UI.Kit.MenuItem
---@field label string       # display text
---@field action? fun()      # callback run when the item is picked (alias: cb)

--- One `kit.select`/`kit.popup({type="select"})` item, for a multi-line entry
--- with per-column custom highlight groups (see UI-KIT-CONCEPT.md §13b). A
--- plain string item still works unchanged -- this is opt-in per item.
---@class Lib.UI.Kit.RichItem
---@field lines string[]                       # >=1 line; buffer content for this item
---@field highlights? Lib.UI.Kit.ItemHighlight[]
---@field anchor? integer                      # 0-based line (within `lines`) the cursor lands on; default 0

--- One highlight span within a `Lib.UI.Kit.RichItem`.
---@class Lib.UI.Kit.ItemHighlight
---@field line integer        # 0-based, within this item's `lines`
---@field col_start? integer  # default 0
---@field col_end? integer    # default: end of that line
---@field hl_group string

--- One field of a `kit.form`. `name` is the key its answer is stored under
--- in the result table handed to `on_submit`.
---@class Lib.UI.Kit.FormField
---@field name string                     # result table key
---@field label? string                   # alias: prompt
---@field prompt? string
---@field default? string
---@field required? boolean               # <Esc> aborts the whole form instead of skipping this field
---@field expand_env? boolean             # run the answer through lib.nvim.cross.fs.expand_path
---@field theme? Lib.UI.Kit.ThemeArg       # overrides opts.theme for this field
---@field width? integer                  # overrides opts.width for this field
---@field relative? "editor"|"cursor"|"win"  # overrides opts.relative for this field

--- Options for `kit.form` / `kit.popup({ type = "form" })`.
---@class Lib.UI.Kit.FormOpts
---@field fields Lib.UI.Kit.FormField[]
---@field theme? Lib.UI.Kit.ThemeArg
---@field width? integer
---@field relative? "editor"|"cursor"|"win"
---@field on_submit fun(values: table<string, string>)
---@field on_cancel? fun()

--- Options for `kit.input` / `kit.popup({ type = "input" })`.
---@class Lib.UI.Kit.InputOpts
---@field title? string                   # alias: prompt
---@field prompt? string
---@field default? string
---@field theme? Lib.UI.Kit.ThemeArg
---@field width? integer
---@field relative? "editor"|"cursor"|"win"
---@field expand_env? boolean              # run the submitted line through lib.nvim.cross.fs.expand_path
---@field secret? boolean                  # mask the input as you type (vim.fn.inputsecret replacement)
---@field mask? string                     # placeholder char when secret = true (default "*")
---@field completion? string               # a getcompletion() type ("file", "dir", ...); <Tab> completes (vim.fn.input's completion="file" replacement)
---@field on_submit? fun(line: string)      # <CR>
---@field on_cancel? fun()                  # <Esc>

--- Options for `kit.live_input` / `kit.popup({ type = "live_input" })`.
---@class Lib.UI.Kit.LiveInputOpts
---@field title? string                   # alias: prompt
---@field prompt? string
---@field default? string
---@field theme? Lib.UI.Kit.ThemeArg
---@field width? integer
---@field relative? "editor"|"cursor"|"win"
---@field row? integer                     # only with relative="editor"; overrides the default centered placement
---@field col? integer                     # only with relative="editor"; overrides the default centered placement
---@field debounce? integer                # ms between the last keystroke and on_change (default 80)
---@field on_change fun(query: string)      # fired debounced as the user types
---@field on_submit? fun(query: string)     # <CR>
---@field on_cancel? fun()                  # <Esc>

--- Options for `kit.compare` / `kit.popup({ type = "compare" })`. See
--- lua/lib/nvim/ui/kit/compare.lua's module doc for the SEARCH → MARKED →
--- COMPARE flow.
---@class Lib.UI.Kit.CompareOpts
---@field items any[]                                  # candidates to pick from
---@field format_item? fun(item: any): any              # results-list line; default tostring
---@field query? fun(query: string, items: any[]): any[] # custom filter; default: substring match on format_item
---@field render fun(item: any, surface: Lib.UI.Kit.Surface)  # required: paint `item` into `surface`
---@field clear? fun()                                  # called once before every state transition
---@field mark_key? string                               # marks the first pick (default "<M-c>"); <CR> also works
---@field title? string
---@field theme? Lib.UI.Kit.ThemeArg
---@field on_close? fun(a: any, b: any)                  # a/b = the two picks; b is nil on an aborted pick

--- Handle returned by `kit.compare`. `state`/`slots`/`move`/`mark`/`confirm`
--- mirror `kit.picker`'s handle shape so the state machine is directly
--- drivable/testable without simulating keypresses.
---@class Lib.UI.Kit.CompareHandle
---@field close fun()
---@field state fun(): "search"|"marked"|"compare"
---@field slots fun(): table<string, Lib.UI.Kit.Surface>
---@field move fun(delta: integer)
---@field mark fun()                                     # SEARCH only: freeze the highlighted item, enter MARKED
---@field confirm fun()                                  # SEARCH: same as mark; MARKED: pick the 2nd item, enter COMPARE

--- Options for `kit.setup`.
---@class Lib.UI.Kit.SetupOpts
---@field default? string                       # active preset name
---@field presets? table<string, table>         # user-registered presets

--- The `lib.nvim.ui.kit` module.
---@class Lib.UI.Kit
---@field setup fun(opts?: Lib.UI.Kit.SetupOpts)
---@field popup fun(opts: table): any            # dispatch on opts.type
---@field note fun(opts: Lib.UI.Kit.NoteOpts): Lib.UI.Kit.Surface|nil
---@field viewer fun(opts: Lib.UI.Kit.ViewerOpts): Lib.UI.Kit.Surface|nil  # read-only info panel, closes on focus loss
---@field toast fun(opts: table): Lib.UI.Kit.Surface|nil    # ephemeral corner message
---@field input fun(opts: Lib.UI.Kit.InputOpts): Lib.UI.Kit.Surface|nil    # single-line insert-mode prompt (secret = true masks it)
---@field live_input fun(opts: Lib.UI.Kit.LiveInputOpts): Lib.UI.Kit.Surface|nil  # debounced on_change as you type
---@field form fun(opts: Lib.UI.Kit.FormOpts): Lib.UI.Kit.Surface|nil  # sequential multi-field prompt
---@field select fun(opts: table): any                       # native themed list chooser (single/multi)
---@field prompt fun(opts: table): any                       # ask: confirm (yes/no) or text
---@field picker fun(opts: table): table|nil                 # interactive picker (prompt drives results)
---@field confirm fun(opts: table): Lib.UI.Kit.Surface|nil    # button-confirm dialog (horizontal buttons)
---@field menu fun(opts: table): Lib.UI.Kit.Surface|nil        # cursor-anchored action list (label → callback)
---@field compare fun(opts: Lib.UI.Kit.CompareOpts): Lib.UI.Kit.CompareHandle|nil  # pick two items, view them side by side
---@field progress fun(opts: table): table                     # passthrough to lib.nvim.progress.create
---@field sync fun(open_fn: fun(opts: table): any, opts: table, timeout_ms: integer|nil): any  # vim.wait bridge for on_submit/on_cancel components; full signature (incl. the two boolean returns) is on lua/lib/nvim/ui/kit/init.lua's M.sync
---@field preview fun(): integer, integer                       # open the live theme playground (also :KitPreview)
---@field surface Lib.UI.Kit.SurfaceModule
---@field theme Lib.UI.Kit.ThemeModule
---@field layout Lib.UI.Kit.LayoutModule
---@field chooser Lib.UI.Kit.ChooserModule  # low-level escape hatch behind kit.select -- see its own doc comment

---@class Lib.UI.Kit.SurfaceModule
---@field open fun(opts?: Lib.UI.Kit.SurfaceOpts): Lib.UI.Kit.Surface|nil

--- The chooser `kit.select` delegates to; see `kit.chooser`'s doc comment
--- in lua/lib/nvim/ui/kit/init.lua for when to reach for this directly.
---@class Lib.UI.Kit.ChooserModule
---@field open fun(opts: table): Lib.UI.Kit.Surface|nil
---@field close fun()
---@field is_open fun(): boolean
---@field move fun(delta: integer)
---@field toggle fun()
---@field submit fun()
---@field current_index fun(): integer|nil
---@field current_item fun(): any

--- Geometry for one slot (an nvim_open_win config).
---@class Lib.UI.Kit.Slot
---@field relative "editor"
---@field row integer
---@field col integer
---@field width integer
---@field height integer

--- A mounted layout group.
---@class Lib.UI.Kit.Group
---@field slots table<string, Lib.UI.Kit.Surface>
---@field close fun()

---@class Lib.UI.Kit.LayoutModule
---@field compute fun(spec: table): { slots: table<string, Lib.UI.Kit.Slot>, outer: table }
---@field mount fun(spec: table, opts?: table): Lib.UI.Kit.Group
---@field template fun(name: string, opts?: table): Lib.UI.Kit.Group|nil
---@field templates table<string, { spec: table }>

---@class Lib.UI.Kit.ThemeModule
---@field resolve fun(theme?: Lib.UI.Kit.ThemeArg): Lib.UI.Kit.Theme
---@field apply fun(winid: integer, resolved: Lib.UI.Kit.Theme)
---@field materialize fun(resolved: Lib.UI.Kit.Theme)   # define the Kit* highlight groups (no window)
---@field border_glyphs fun(resolved: Lib.UI.Kit.Theme): table|nil  # box-drawing glyph set, or nil (borderless)
---@field setup fun(opts?: Lib.UI.Kit.SetupOpts)
---@field presets fun(): string[]

return {}
