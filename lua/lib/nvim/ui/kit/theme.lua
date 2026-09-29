---@module 'lib.nvim.ui.kit.theme'
--- Theme / preset engine for lib.nvim.ui.kit.
---
--- A theme is a table of design tokens (border, padding, zindex, highlights, …).
--- Presets are named themes differing mainly in border strength; their highlight
--- groups link to standard groups (NormalFloat / FloatBorder / PmenuSel / …) so
--- the default look is correct in any colorscheme. Callers pass a preset name, a
--- partial override table (deep-merged over the active default), or nil.

local hl = require("lib.nvim.ui.hl")
local config = require("lib.nvim.ui.kit.config")
local autocmd = require("lib.nvim.bindings.autocmd")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit]")

local M = {}

--- Base tokens; every preset is merged over this.
---@type Lib.UI.Kit.Theme
local BASE = {
  border = "rounded",
  ascii_border = false,
  padding = { x = 1, y = 0 },
  zindex = { base = 50, popup = 50, toast = 70, menu = 60 },
  title_pos = "center",
  dims = { min_w = 20, max_w = 100, min_h = 1, max_h = 30 },
  hl = {
    normal = "NormalFloat",
    border = "FloatBorder",
    title = "FloatTitle",
    selection = "PmenuSel",
    accent = "Special",
    muted = "Comment",
    error = "DiagnosticError",
    -- The momentary "you picked this one" highlight. `IncSearch` is the group
    -- Vim already uses for "the thing you are about to act on", so every
    -- colorscheme defines it, and defines it strongly -- which is the whole
    -- requirement for a mark that is on screen for a tenth of a second.
    flash = "IncSearch",
    -- The row the mouse is hovering, painted independently of `selection`
    -- (an extmark, not the `CursorLine` window option `selection` rides on)
    -- so it renders the same regardless of `hide_cursor`/other window-local
    -- quirks a given frontend might have around cursorline repaint timing.
    -- `Visual` reads as "about to act on this" without borrowing the
    -- keyboard-selection group's own identity.
    hover = "Visual",
  },
}

--- Built-in presets (overrides layered onto BASE).
---@type table<string, table>
local BUILTIN = {
  -- Presets differ in border AND in which standard groups their highlights link
  -- to, so they look distinct under *any* colorscheme (no colours are
  -- hardcoded — everything stays theme-adaptive). `hacker` (below) is the one
  -- deliberate exception: its whole point is a fixed identity that looks the
  -- same regardless of the active colorscheme, so its `hl` entries are raw
  -- hex instead of links.
  minimal = {
    border = "none",
    hl = { selection = "Visual", accent = "NonText", muted = "NonText", title = "Comment" },
  },
  rounded = {
    border = "rounded", -- the default palette (see BASE.hl)
  },
  solid = {
    border = "single",
    hl = { selection = "PmenuSel", accent = "Statement", title = "Title" },
  },
  double = {
    border = "double",
    hl = { border = "Special", title = "Title", accent = "WarningMsg" },
  },
  ascii = {
    border = { "+", "-", "+", "|", "+", "-", "+", "|" },
    ascii_border = true,
    hl = { border = "Comment", accent = "Identifier", title = "Todo" },
  },
  -- `lib.nvim.ui.kit.chip`'s statusline-docked look: rounded everywhere except the
  -- left edge, which stays square/glyph-less -- the 8-element array is
  -- `{ top-left, top, top-right, right, bottom-right, bottom, bottom-left,
  -- left }`, so this is `rounded`'s own array with both left-side corners
  -- and the left edge itself blanked out. Meant for a chip sitting flush
  -- against the screen's left edge and a statusline row, where a rounded
  -- (or even square) left corner would visibly float free of both.
  dock_left = {
    border = { "", "─", "╮", "│", "╯", "─", "", "" },
  },
  -- `kit.menu`'s default, and its one point of difference is a *coloured*
  -- frame. `FloatBorder` is deliberately quiet in most colorschemes, which is
  -- right for a panel that was already there and wrong for a menu you just
  -- summoned. `Function` is defined and clearly tinted in every colorscheme
  -- worth the name, so this borrows the scheme's own accent instead of
  -- shipping a colour of its own.
  menu = {
    border = "rounded",
    hl = { border = "Function", title = "Function" },
  },
  -- Monochrome green-on-black terminal look, ASCII-boxed like `ascii` above
  -- but with its own fixed palette instead of that preset's colorscheme-
  -- linked groups -- picking this preset is asking for the one look that
  -- does NOT adapt to whatever colorscheme is active. `selection` carries a
  -- background (a highlighted row reads as a filled block); `accent`/
  -- `muted`/`error`/`flash`/`hover` stay foreground-only so they still
  -- compose over whatever `normal`/`selection` background they render on.
  hacker = {
    border = { "+", "-", "+", "|", "+", "-", "+", "|" },
    ascii_border = true,
    hl = {
      normal = { fg = "#33ff66", bg = "#060a06" },
      border = { fg = "#16c60c", bg = "#060a06" },
      title = { fg = "#16c60c", bg = "#060a06", bold = true },
      selection = { fg = "#060a06", bg = "#33ff66", bold = true },
      accent = { fg = "#7cffa0", bold = true },
      muted = { fg = "#1f7a1f" },
      error = { fg = "#ff5555" },
      flash = { fg = "#7cffa0", bold = true },
      hover = { fg = "#16c60c", underline = true },
    },
  },
}

-- Runtime registry (built-ins + user presets) and the active default.
local presets = vim.deepcopy(BUILTIN)
local default_name = config.defaults.default

--- Global highlight groups a theme materializes. winhighlight maps the float's
--- built-in groups onto these; components use the rest via extmarks.
local GROUPS = {
  normal = "KitNormal",
  border = "KitBorder",
  title = "KitTitle",
  selection = "KitSelection",
  accent = "KitAccent",
  muted = "KitMuted",
  error = "KitError",
  flash = "KitFlash",
  hover = "KitHover",
}

--- Resolve a theme argument to a full token table.
---@param theme? Lib.UI.Kit.ThemeArg
---@return Lib.UI.Kit.Theme
function M.resolve(theme)
  local base = vim.deepcopy(BASE)

  if type(theme) == "string" and presets[theme] then
    return vim.tbl_deep_extend("force", base, presets[theme])
  end

  local active = presets[default_name] or presets.rounded or {}
  local resolved = vim.tbl_deep_extend("force", base, active)

  if type(theme) == "table" then
    resolved = vim.tbl_deep_extend("force", resolved, theme)
  end

  return resolved
end

---@internal
--- Define the Kit* highlight groups for a resolved theme (idempotent).
---@param resolved Lib.UI.Kit.Theme
local function materialize(resolved)
  for key, group in pairs(GROUPS) do
    local spec = resolved.hl[key]
    local opts = type(spec) == "string" and { link = spec } or spec
    hl.set(group, opts)
  end
end

--- Public: define the Kit* highlight groups for a resolved theme, without
--- touching any window. Used by the preview playground to colour its buffer.
---@param resolved Lib.UI.Kit.Theme
function M.materialize(resolved)
  materialize(resolved)
end

--- Map a resolved theme's border to a box-drawing glyph set for rendering
--- static previews (tl/tr/bl/br/h/v). Falls back to `single`.
---@param resolved Lib.UI.Kit.Theme
---@return { tl:string, tr:string, bl:string, br:string, h:string, v:string }|nil  # nil for a borderless theme
function M.border_glyphs(resolved)
  local SETS = {
    rounded = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
    single = { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" },
    double = { tl = "╔", tr = "╗", bl = "╚", br = "╝", h = "═", v = "║" },
    ascii = { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|" },
  }
  if resolved.ascii_border then
    return SETS.ascii
  end
  local b = resolved.border
  if b == "none" then
    return nil
  end
  if type(b) == "string" and SETS[b] then
    return SETS[b]
  end
  -- A raw 8-element array (e.g. `dock_left`'s glyph-less left edge) -- read
  -- the actual glyphs straight out of it instead of falling back to
  -- `single`'s, which would misrepresent any preset shaped this way. Order
  -- per `:h nvim_open_win`: topleft, top, topright, right, bottomright,
  -- bottom, bottomleft, left.
  if type(b) == "table" and #b == 8 then
    return { tl = b[1], tr = b[3], br = b[5], bl = b[7], h = b[2], v = b[4] }
  end
  return SETS.single
end

---@internal
--- `M.apply`'s per-window twin of `materialize`. `KitNormal`/`KitBorder`/
--- `KitTitle` are fixed names shared by EVERY open kit surface -- fine as
--- long as every simultaneously-open surface resolves to the same colors,
--- but toasts are explicitly designed to stack (see `lib.nvim.ui.kit.toast`'s own
--- docs), and two different levels/`opts.hl` overrides resolve to different
--- colors. Whichever surface materialized last used to win for every window
--- still pointing `winhighlight` at those fixed names -- a still-visible
--- toast (e.g. a yellow WARN "pulling…") would change color live the
--- instant a differently-themed one opened next to it (e.g. a green
--- `notify.success` toast), since both windows' `winhighlight` referenced
--- the SAME group name and only the latest materialize() call's colors
--- exist for that name at any given moment.
---
--- The replacement group is keyed by a fingerprint of the role's resolved
--- spec, not by `winid`: two surfaces that happen to resolve to the same
--- colors share one group (no reason for two identical ones to exist), and
--- -- since Neovim has no API to delete a highlight group once defined --
--- keying by `winid` instead would mint three brand new, permanent groups
--- for every surface that ever opens, growing this without bound for the
--- life of the session; keying by content instead bounds the total to
--- however many DISTINCT colors are ever actually used (a handful of
--- presets/`opts.hl` overrides), independent of how many surfaces open over
--- time.
---
--- `KitSelection`/`KitAccent`/`KitMuted`/`KitError`/`KitFlash`/`KitHover`
--- stay global/fixed, unaffected by this: nothing draws two of those roles
--- at once with different colors the way toasts do with border/title.
--- `lib.nvim.ui.kit.menu` and `lib.nvim.ui.kit.shortlist` paint their OWN border/title
--- decoration via extmarks (group frames, titled rules) rather than relying
--- on `winhighlight` alone -- they call `M.window_groups(resolved)` below
--- for the same reason `M.apply` does, so their extmarks reference the
--- right scoped names too, not the fixed globals.
---@type table<string, string>
local window_group_cache = {}
local window_group_counter = 0

---@param resolved Lib.UI.Kit.Theme
---@return { normal: string, border: string, title: string }
local function materialize_window_groups(resolved)
  local names = {}
  for _, role in ipairs({ "normal", "border", "title" }) do
    local spec = resolved.hl[role]
    local cache_key = role .. ":" .. vim.inspect(spec)
    local name = window_group_cache[cache_key]
    if not name then
      window_group_counter = window_group_counter + 1
      name = ("Kit%s_%d"):format(role:sub(1, 1):upper() .. role:sub(2), window_group_counter)
      local opts = type(spec) == "string" and { link = spec } or spec
      hl.set(name, opts)
      window_group_cache[cache_key] = name
    end
    names[role] = name
  end
  return names
end

--- Public: the same window-scoped `KitNormal_N`/`KitBorder_N`/`KitTitle_N`
--- group names `M.apply` materializes for `resolved`, for a caller that
--- paints its OWN decoration via extmarks referencing these names directly
--- (`lib.nvim.ui.kit.menu`'s group frames, `lib.nvim.ui.kit.shortlist`'s border) instead of
--- relying solely on `winhighlight`. Safe to call before the surface that
--- will use them even opens, and safe to call more than once for the same
--- `resolved` (the cache above returns the same name both times): Neovim
--- resolves an extmark's highlight group by name at redraw time, not when
--- the extmark is created, so it doesn't matter whether this or `M.apply`
--- materializes the group first, as long as both resolve the same theme.
---@param resolved Lib.UI.Kit.Theme
---@return { normal: string, border: string, title: string }
function M.window_groups(resolved)
  return materialize_window_groups(resolved)
end

--- Apply a resolved theme to an open window: materialize its groups and point
--- the float's built-in groups at them via winhighlight.
---@param winid integer
---@param resolved Lib.UI.Kit.Theme
function M.apply(winid, resolved)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  materialize(resolved)
  local names = materialize_window_groups(resolved)
  local winhl = table.concat({
    "NormalFloat:" .. names.normal,
    "FloatBorder:" .. names.border,
    "FloatTitle:" .. names.title,
  }, ",")
  pcall(vim.api.nvim_set_option_value, "winhighlight", winhl, { win = winid })
end

--- Register user presets / change the active default.
---
--- Both fields are validated before anything is applied: an unknown top-level
--- key, a non-table `presets`, or a `default` that names no registered preset
--- are reported rather than dropped silently -- a typo'd preset name (e.g.
--- `default = "drak"`) would otherwise leave the active default unchanged
--- with nothing to say the call had no effect.
---@param opts? Lib.UI.Kit.SetupOpts
function M.setup(opts)
  opts = opts or {}

  for key in pairs(opts) do
    if key ~= "presets" and key ~= "default" then
      notify.warn(("kit.setup: unknown option %q ignored"):format(tostring(key)))
    end
  end

  if opts.presets ~= nil then
    if type(opts.presets) == "table" then
      for name, spec in pairs(opts.presets) do
        presets[name] = spec
      end
    else
      notify.warn(
        ("kit.setup: opts.presets must be a table, got %s — ignored"):format(type(opts.presets))
      )
    end
  end

  if opts.default ~= nil then
    if type(opts.default) == "string" and presets[opts.default] then
      default_name = opts.default
    else
      notify.warn(
        ("kit.setup: unknown default preset %q — keeping %q"):format(
          tostring(opts.default),
          default_name
        )
      )
    end
  end

  -- Re-materialize the active default so links refresh after a colorscheme
  -- change (set up once).
  if not M._colorscheme_hook then
    M._colorscheme_hook = true
    -- Raw nvim_create_augroup on purpose, not autocmd.group(): its name ->
    -- id cache would survive a hot-reload of just this module (which resets
    -- _colorscheme_hook and re-enters this branch) without re-clearing,
    -- leaving a stale duplicate callback registered.
    local group = vim.api.nvim_create_augroup("lib_ui_kit_theme", { clear = true })
    autocmd.create("ColorScheme", function()
      pcall(materialize, M.resolve(nil))
    end, {
      group = group,
      desc = "lib.nvim.ui.kit: refresh theme highlight groups",
    })
  end
end

--- Names of all registered presets.
---@return string[]
function M.presets()
  local out = {}
  for name in pairs(presets) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

--- Name of the currently active default preset.
---@return string
function M.default()
  return default_name
end

return M
