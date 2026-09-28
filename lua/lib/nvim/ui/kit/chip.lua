---@module 'lib.nvim.ui.kit.chip'
--- Persistent, editor-corner status chip. Unlike `kit.toast` (auto-dismissing,
--- stacks, one-shot), a chip is mounted once under a stable `id` and stays on
--- screen -- updated in place -- until the consumer unmounts it or its own
--- `text`/`visible` says there is nothing to show right now. Built for a
--- plugin's own always-on indicator (an active session name, an ambient
--- container count, ...) that today only gets a one-shot `vim.notify` toast
--- nobody remembers five seconds later.
---
--- `mount(opts)` registers (or re-configures, if `opts.id` already exists) a
--- chip and draws it once. From then on the consumer calls `refresh(id)`
--- whenever its own state changed -- there is no polling timer here, same
--- reasoning `ui.context` gives for driving its overlay off events rather
--- than a clock: a boolean/string read on every keystroke would cost nothing,
--- but nothing here needs to be *that* fresh, and a timer is one more thing
--- to leak.
---
--- `text`/`visible` may be a plain value or a zero-arg function, re-read on
--- every `refresh`. An empty resolved text hides the chip even when
--- `visible` (or its default) says otherwise -- mirrors the "return '' when
--- there's nothing to show" convention `sessions.statusline.component()`
--- already uses, so wiring one straight into `text` just works.
---
--- `text` may embed `\n` to stack several lines in one box (casedesk.nvim's
--- case pin does this for "case number, title on the line below") -- the
--- box's height follows the line count, and its width follows the widest
--- line, not a fixed one-row assumption.
---
--- Colour has two independent modes, both accepted as `opts.color`: a
--- highlight-group name (its `fg` is tinted into the window background --
--- `CHIP_TINT`, the same mix `ui.context`'s chip style uses, so it reads as
--- the same family and re-tints itself on `ColorScheme`), or an explicit
--- `{ fg, bg }` pair (`"#rrggbb"` strings or 24-bit numbers) that stays fixed
--- across colorschemes. `nil` uses `DEFAULT_HL_GROUP` ("Special").
---
--- Each mounted chip gets its own highlight group (`UiKitChip_<id>`) rather
--- than the shared `Kit*` groups `lib.nvim.ui.kit.theme` materializes -- several
--- chips, or a chip and a modal kit popup, can be on screen at once with
--- independently coloured chips instead of fighting over one shared group.
---
--- `opts.shape` picks the box: `"rounded"` (the default, a bordered
--- capsule), `"rect"` (borderless, a flat coloured block), or `"text"`
--- (borderless AND background-less -- just the coloured text floating over
--- whatever is behind it, no box at all; any `color.bg` is ignored for this
--- one since the whole point is having no visible background).
---
--- A floating window belongs to the tabpage it was opened in and simply does
--- not appear on any other tab -- so a chip that should follow the user
--- across tabs is re-opened (same text/colour) on `TabEnter` rather than
--- moved; see `ensure_current_tab`.

local surface = require("lib.nvim.ui.kit.surface")
local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

local DEFAULT_HL_GROUP = "Special"
local CHIP_TINT = 0.18
local MARGIN = 1

---@type table<string, { v: "top"|"bottom", h: "left"|"right" }>
local ANCHORS = {
  ["bottom-left"] = { v = "bottom", h = "left" },
  ["bottom-right"] = { v = "bottom", h = "right" },
  ["top-left"] = { v = "top", h = "left" },
  ["top-right"] = { v = "top", h = "right" },
}

--- Live chips, keyed by consumer-chosen id.
---@type table<string, table>
local chips = {}
local next_order = 0
local hooks_installed = false

-- ---------------------------------------------------------------- colour

---@internal
---@param name string
---@return { fg?: integer, bg?: integer }
local function resolve_hl(name)
  local ok, h = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  return ok and h or {}
end

---@internal
---`"#rrggbb"` or a 24-bit number -> a 24-bit number; anything else -> nil.
---@param v string|integer|nil
---@return integer|nil
local function as_color_number(v)
  if type(v) == "number" then
    return v
  end
  if type(v) == "string" then
    local hex = v:match("^#(%x%x%x%x%x%x)$")
    return hex and tonumber(hex, 16) or nil
  end
  return nil
end

---@internal
---@param fg integer
---@param bg integer
---@param amount number
---@return integer
local function mix(fg, bg, amount)
  local out = 0
  for _, unit in ipairs({ 65536, 256, 1 }) do
    local f = math.floor(fg / unit) % 256
    local b = math.floor(bg / unit) % 256
    out = out * 256 + math.floor(b + (f - b) * amount + 0.5)
  end
  return out
end

---@internal
---@return integer
local function window_bg()
  for _, name in ipairs({ "NormalFloat", "Normal" }) do
    local bg = resolve_hl(name).bg
    if bg then
      return bg
    end
  end
  return vim.o.background == "light" and 0xeff1f5 or 0x1f2335
end

---@internal
---`transparent` (shape = "text"): the resolved background is always the
---window's own, whatever `color.bg` says -- "text" means no visible box, a
---custom bg would put one back.
---@param color Lib.UI.Kit.ChipColor|nil
---@param transparent boolean|nil
---@return { fg: integer, bg: integer, themed: boolean }
local function resolve_colors(color, transparent)
  if type(color) == "table" then
    local fg = as_color_number(color.fg) or resolve_hl(DEFAULT_HL_GROUP).fg or 0xc0caf5
    local bg = transparent and window_bg() or (as_color_number(color.bg) or window_bg())
    return { fg = fg, bg = bg, themed = false }
  end
  local group = type(color) == "string" and color or DEFAULT_HL_GROUP
  local fg = resolve_hl(group).fg or resolve_hl("Normal").fg or 0xc0caf5
  local bg = transparent and window_bg() or mix(fg, window_bg(), CHIP_TINT)
  return { fg = fg, bg = bg, themed = true }
end

---@internal
---Every non-alphanumeric byte -- including a literal `_`, so the escape
---marker itself can never appear unescaped -- becomes `_xx` (its hex byte).
---Unlike a lossy "replace with `_`" pass, this is unambiguous: two distinct
---ids (e.g. `"a.b"` and `"a_b"`, both of which used to sanitize to the same
---`"a_b"`) can never collide onto the same derived group name, so refreshing
---one mounted chip can never bleed its colour into an unrelated one.
---@param id string
---@return string
local function hl_group_name(id)
  local encoded = id:gsub("[^%w]", function(c)
    return ("_%02x"):format(c:byte())
  end)
  return "UiKitChip_" .. encoded
end

---@internal
---@param entry table
---@param colors { fg: integer, bg: integer, themed: boolean }
local function apply_colors(entry, colors)
  entry.applied_colors = colors
  local group = hl_group_name(entry.id)
  pcall(api.nvim_set_hl, 0, group, { fg = colors.fg, bg = colors.bg })
  if entry.win and api.nvim_win_is_valid(entry.win) then
    pcall(
      api.nvim_set_option_value,
      "winhighlight",
      "NormalFloat:" .. group .. ",FloatBorder:" .. group,
      { win = entry.win }
    )
  end
end

-- ---------------------------------------------------------------- resolution

---@internal
---@param v string|fun():string|nil
---@return string
local function resolve_text(v)
  if type(v) == "function" then
    local ok, out = pcall(v)
    return (ok and type(out) == "string") and out or ""
  end
  return type(v) == "string" and v or ""
end

---@internal
---A chip's resolved text may embed `\n` to stack several lines in one box
---(casedesk.nvim's pin does this for "case number, title on the line
---below") -- split into the list `nvim_buf_set_lines` wants. Always at
---least one line, even for `""`, so a caller never has to special-case an
---empty chip's line count.
---@param text string
---@return string[]
local function split_lines(text)
  if text == "" then
    return { "" }
  end
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

---@internal
---@param v boolean|fun():boolean|nil
---@return boolean|nil  nil = "not set", let the caller derive it from the text instead
local function resolve_visible(v)
  if type(v) == "function" then
    local ok, out = pcall(v)
    return ok and out and true or (ok and false or nil)
  end
  if type(v) == "boolean" then
    return v
  end
  return nil
end

---@internal
---@param shape "rounded"|"rect"|"text"|nil
---@return "rounded"|"minimal"  # a lib.nvim.ui.kit.theme preset name: "rounded" border, or borderless
local function preset_for_shape(shape)
  return shape == "rounded" and "rounded" or "minimal"
end

---@internal
---@param shape "rounded"|"rect"|"text"|nil
---@return boolean  # "text": no visible box, just coloured text over the window behind it
local function is_transparent_shape(shape)
  return shape == "text"
end

-- ---------------------------------------------------------------- window lifecycle

---@internal
---Closing this window fires `WinClosed` synchronously (and `open_window`
---below fires `WinNew`) -- a consumer wiring its own bookkeeping to those
---events for every window (e.g. sessions.nvim's dirty-tracking) re-enters
---`M.refresh(id)` mid-transition, before `entry.win`/`entry.surf` have
---settled. `entry.busy` makes that reentrant call a no-op instead of
---racing `open_window`/`close_window`: without it, the reentrant refresh
---used to open (and then immediately orphan) a second, untracked window --
---see the "reopen" regression test.
---@param entry table
local function close_window(entry)
  if entry.surf then
    entry.busy = true
    entry.surf:close()
    entry.busy = false
  end
  entry.surf = nil
  entry.win = nil
  entry.buf = nil
end

---@internal
---Open (or re-open, e.g. on a tab switch) the float for `entry` on the
---current tabpage, at a throwaway position -- `reflow()` places it for real.
---@param entry table
local function open_window(entry)
  entry.busy = true
  local surf = surface.open({
    lines = entry.lines,
    theme = preset_for_shape(entry.shape),
    width = entry.width,
    height = entry.height,
    relative = "editor",
    row = 0,
    col = 0,
    enter = false,
    focusable = false,
    zindex = entry.zindex,
  })
  entry.busy = false
  if not surf then
    return
  end
  entry.surf = surf
  entry.win = surf.winid
  entry.buf = surf.bufnr
  entry.applied_border = entry.border
  entry.applied_text = entry.text
  entry.applied_width = entry.width
  entry.applied_height = entry.height
  surf:on_close(function()
    if chips[entry.id] == entry then
      entry.surf = nil
      entry.win = nil
      entry.buf = nil
    end
  end)
  -- Always resolved fresh from `entry.color` -- never `entry.applied_colors`,
  -- which (re-)opening this window is a bad time to trust: a still-pending
  -- `pulse()` leaves it holding the *pulse* colour, and reusing that here
  -- (e.g. on the `ensure_current_tab` reopen below) left a chip stuck showing
  -- its pulse colour forever once the pending revert's captured window
  -- handle stopped matching the newly (re)opened one.
  apply_colors(entry, resolve_colors(entry.color, is_transparent_shape(entry.shape)))
end

---@internal
---Re-open on the active tabpage any visible chip whose window belongs to a
---different one -- a floating window never appears outside the tabpage it was
---created in, so "follow the user across tabs" means recreating it there.
local function ensure_current_tab()
  local current = api.nvim_get_current_tabpage()
  for _, entry in pairs(chips) do
    if entry.win and api.nvim_win_is_valid(entry.win) then
      local ok, tab = pcall(api.nvim_win_get_tabpage, entry.win)
      if ok and tab ~= current then
        close_window(entry)
        open_window(entry)
      end
    end
  end
end

---@internal
---Whether the editor's bottom-most content row (the one just above the
---cmdline) is occupied by a window's statusline -- the row a bottom-anchored
---chip must leave alone rather than draw over.
---
---`laststatus`, not a fixed assumption: `0` never shows one, `1` only once
---there is more than one REAL window (so a lone-window session has no
---reserved row at all), `2`/`3` always do. Getting this wrong is exactly the
---bug this function exists to fix -- a bottom-right chip used to land ON the
---statusline row (only `cmdheight` was reserved), invisible over it or
---clipping its rightmost cells rather than sitting above it.
---
---`nvim_tabpage_list_wins` counts EVERY window on the tabpage, floats
---included -- a mounted chip's own floating window (or any other float:
---a hover doc, a picker) would otherwise make `laststatus == 1` see "more
---than one window" and reserve a row Neovim itself never draws for a
---genuinely single-real-window session, since real Neovim only counts
---splits for that decision, not floats (verified: opening a float never
---changes a real window's own height). Filtered to `relative == ""` so
---only actual splits count.
---@return integer 0 or 1
local function bottom_statusline_rows()
  local laststatus = vim.o.laststatus
  if laststatus == 0 then
    return 0
  end
  if laststatus == 1 then
    local real_wins = 0
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if api.nvim_win_get_config(win).relative == "" then
        real_wins = real_wins + 1
      end
    end
    return real_wins > 1 and 1 or 0
  end
  return 1
end

---@internal
---Reposition every visible chip, grouped by anchor corner and stacked away
---from the edge in mount order. Border rows are approximated the same way
---`lib.nvim.ui.kit.toast`'s own stacking does (one extra row of gap, not exact
---border-box arithmetic) -- close enough for a corner indicator.
local function reflow()
  ---@type table<string, table[]>
  local groups = {}
  for _, entry in pairs(chips) do
    if entry.win and api.nvim_win_is_valid(entry.win) then
      groups[entry.anchor] = groups[entry.anchor] or {}
      table.insert(groups[entry.anchor], entry)
    end
  end

  for anchor, list in pairs(groups) do
    table.sort(list, function(a, b)
      return a.order < b.order
    end)
    local edge = ANCHORS[anchor] or ANCHORS["bottom-left"]
    local status_rows = edge.v == "bottom" and bottom_statusline_rows() or 0
    local offset = MARGIN
    for _, entry in ipairs(list) do
      local content_h = entry.height or 1
      local box_h = entry.border == "none" and content_h or (content_h + 2)
      local row = edge.v == "top" and offset
        or math.max(0, vim.o.lines - vim.o.cmdheight - status_rows - offset - box_h + 1)
      -- Flush against the left edge (col 0), not inset by MARGIN -- a
      -- bordered float's `col` is where its own border starts, so 0 already
      -- sits exactly at the screen edge without clipping anything. The right
      -- edge keeps its MARGIN inset so a right-anchored chip isn't flush
      -- against the terminal's own right border.
      local col = edge.h == "left" and 0
        or math.max(0, vim.o.columns - entry.width - MARGIN - (entry.border == "none" and 0 or 2))
      pcall(api.nvim_win_set_config, entry.win, {
        relative = "editor",
        row = row,
        col = col,
        width = entry.width,
      })
      offset = offset + box_h + MARGIN
    end
  end
end

---@internal
local function ensure_hooks()
  if hooks_installed then
    return
  end
  hooks_installed = true
  local group = autocmd.group("UiKitChip", true)
  autocmd.create("VimResized", reflow, {
    group = group,
    desc = "lib.nvim.ui.kit.chip: keep chips pinned to their corner",
  })
  autocmd.create("TabEnter", function()
    ensure_current_tab()
    reflow()
  end, {
    group = group,
    desc = "lib.nvim.ui.kit.chip: follow the user onto the new tabpage",
  })
  autocmd.create("ColorScheme", function()
    for _, entry in pairs(chips) do
      if
        entry.win
        and api.nvim_win_is_valid(entry.win)
        and entry.applied_colors
        and entry.applied_colors.themed
      then
        apply_colors(entry, resolve_colors(entry.color, is_transparent_shape(entry.shape)))
      end
    end
  end, {
    group = group,
    desc = "lib.nvim.ui.kit.chip: re-tint theme-linked chips",
  })
end

-- ---------------------------------------------------------------- public API

---Mount (or re-configure) a chip under `opts.id`. Draws nothing by itself
---until the resolved text is non-empty -- an idle chip (no active session,
---no running container, ...) stays invisible, not a placeholder.
---
---A field `opts` omits (nil) keeps the entry's current value rather than
---clearing it -- re-mounting an existing id to change just one thing (e.g.
---`shape`, to switch rounded/rect/text live) must not wipe out `text`/
---`color`/... nobody re-passed. `visible` needs its own nil check rather
---than the `opts.x or entry.x` idiom the other fields use: `false` is a
---legitimate value there, and `and/or` treats a falsy `false` the same as a
---missing one.
---@param opts Lib.UI.Kit.ChipOpts
---@return string id
function M.mount(opts)
  opts = opts or {}
  local id = opts.id
  if type(id) ~= "string" or id == "" then
    error("lib.nvim.ui.kit.chip.mount: opts.id (non-empty string) is required", 2)
  end

  local entry = chips[id]
  if not entry then
    entry = { id = id, order = next_order }
    next_order = next_order + 1
    chips[id] = entry
  end

  if opts.text ~= nil then
    entry.text_src = opts.text
  end
  if opts.visible ~= nil then
    entry.visible_src = opts.visible
  end
  entry.anchor = ANCHORS[opts.anchor] and opts.anchor or entry.anchor or "bottom-left"
  entry.shape = opts.shape or entry.shape or "rounded"
  if opts.color ~= nil then
    entry.color = opts.color
  end
  entry.zindex = opts.zindex or entry.zindex or 60

  ensure_hooks()
  M.refresh(id)
  return id
end

---Re-read `text`/`visible` for `id` and redraw (or hide/show) accordingly.
---A no-op for an id that was never mounted (or already unmounted), or while
---`open_window`/`close_window` is already mid-transition for it (`entry.busy`
----- see that function's own comment for why a reentrant call here would
---otherwise leak a window).
---@param id string
function M.refresh(id)
  local entry = chips[id]
  if not entry or entry.busy then
    return
  end

  local text = resolve_text(entry.text_src)
  local visible = resolve_visible(entry.visible_src)
  if visible == nil then
    visible = text ~= ""
  end

  if not visible or text == "" then
    close_window(entry)
    reflow()
    return
  end

  entry.text = text
  entry.lines = split_lines(text)
  entry.height = #entry.lines
  local width = 0
  for _, line in ipairs(entry.lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  entry.width = width + 2
  entry.border = preset_for_shape(entry.shape) == "minimal" and "none" or "rounded"

  if not entry.win or not api.nvim_win_is_valid(entry.win) then
    open_window(entry)
  else
    -- `refresh()` runs off editing-rate autocmds (sessions.nvim wires it into
    -- BufAdd/BufDelete/WinNew/WinClosed/TabNewEntered/TabClosed), so most
    -- calls find nothing about the chip itself actually changed. Text,
    -- width, border and colour are each only re-applied to the live window
    -- when they differ from what is already showing -- otherwise every one
    -- of those events would repaint a chip whose rendered output never moved.
    if entry.applied_text ~= text then
      entry.surf:set_lines(entry.lines)
      entry.applied_text = text
    end

    local wconfig = nil
    if entry.applied_width ~= entry.width then
      wconfig = wconfig or {}
      wconfig.width = entry.width
      entry.applied_width = entry.width
    end
    if entry.applied_height ~= entry.height then
      wconfig = wconfig or {}
      wconfig.height = entry.height
      entry.applied_height = entry.height
    end
    if entry.applied_border ~= entry.border then
      wconfig = wconfig or {}
      wconfig.border = entry.border
      entry.applied_border = entry.border
    end
    if wconfig then
      pcall(api.nvim_win_set_config, entry.win, wconfig)
    end

    local colors = resolve_colors(entry.color, is_transparent_shape(entry.shape))
    local applied = entry.applied_colors
    -- `themed` is compared too, not just the rendered fg/bg: switching
    -- `entry.color` between a table and a highlight-group name can resolve
    -- to identical pixels (e.g. a custom fg that happens to match a group's
    -- fg on a transparent chip, where bg is always `window_bg()` either
    -- way). Comparing fg/bg alone would then skip `apply_colors` and leave
    -- `applied_colors.themed` stale -- and the `ColorScheme` handler above
    -- gates its re-tint on exactly that field, so a chip that just became
    -- (or stopped being) theme-linked would silently keep the wrong
    -- behaviour on every future colorscheme change.
    if
      not applied
      or applied.fg ~= colors.fg
      or applied.bg ~= colors.bg
      or applied.themed ~= colors.themed
    then
      apply_colors(entry, colors)
    end
  end

  reflow()
end

---Briefly override a mounted chip's colour (e.g. on a save/load event),
---reverting to its configured colour after `opts.duration_ms` (default
---300). A no-op while the chip is hidden -- there is nothing to pulse.
---@param id string
---@param opts? Lib.UI.Kit.ChipPulseOpts
function M.pulse(id, opts)
  local entry = chips[id]
  if not entry or not entry.win or not api.nvim_win_is_valid(entry.win) then
    return
  end
  opts = opts or {}
  local duration = tonumber(opts.duration_ms) or 300
  local transparent = is_transparent_shape(entry.shape)
  apply_colors(entry, resolve_colors(opts.color or "DiagnosticWarn", transparent))

  local win = entry.win
  vim.defer_fn(function()
    local e = chips[id]
    if e and e.win == win and api.nvim_win_is_valid(win) then
      apply_colors(e, resolve_colors(e.color, is_transparent_shape(e.shape)))
    end
  end, duration)
end

---Unmount `id`: closes its window (if any) and forgets its configuration.
---@param id string
function M.unmount(id)
  local entry = chips[id]
  if not entry then
    return
  end
  close_window(entry)
  chips[id] = nil
  reflow()
end

---Ids of every currently *visible* mounted chip (hidden-but-mounted ids are
---not included). Mainly for tests/introspection.
---@return string[]
function M.active()
  local out = {}
  for id, entry in pairs(chips) do
    if entry.win and api.nvim_win_is_valid(entry.win) then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

return M
