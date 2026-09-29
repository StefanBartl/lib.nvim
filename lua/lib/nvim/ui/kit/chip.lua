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
--- across colorschemes. `nil` uses `DEFAULT_HL_GROUP` ("Special"). `color`
--- may also be a zero-arg function returning either shape, re-called fresh
--- on every `refresh` (same as `text`/`visible`) -- for a colour with no
--- single stable source, e.g. a host statusline that switches *which*
--- highlight group it references as the mode changes rather than one group
--- whose own colour changes. Pair with `opts.track_mode = true` so the chip
--- actually repaints *when* the mode changes, not just at the next
--- incidental `refresh()`.
---
--- Each mounted chip gets its own highlight group (`UiKitChip_<id>`) rather
--- than the shared `Kit*` groups `lib.nvim.ui.kit.theme` materializes -- several
--- chips, or a chip and a modal kit popup, can be on screen at once with
--- independently coloured chips instead of fighting over one shared group.
---
--- `opts.shape` picks the box, from the shared vocabulary in
--- `lib.nvim.ui.kit.presets`
--- (also used by `ui.context`, `ui.tabline`,
--- `ui.statusline` and third-party consumers like
--- sessions.nvim/casedesk.nvim): `"rounded_chip"` (the default, a bordered
--- capsule), `"chip"` (borderless, a flat coloured block), or `"classic"`
--- (borderless AND background-less -- just the coloured text floating over
--- whatever is behind it, no box at all; any `color.bg` is ignored for this
--- one since the whole point is having no visible background). The old
--- names (`"rounded"`/`"rect"`/`"text"`) still work, normalized on the way
--- in -- see
--- `lib.nvim.ui.kit.presets.normalize()`.
---
--- A floating window belongs to the tabpage it was opened in and simply does
--- not appear on any other tab -- so a chip that should follow the user
--- across tabs is re-opened (same text/colour) on `TabEnter` rather than
--- moved; see `ensure_current_tab`.

local surface = require("lib.nvim.ui.kit.surface")
local autocmd = require("lib.nvim.bindings.autocmd")
local presets = require("lib.nvim.ui.kit.presets")
local theme = require("lib.nvim.ui.kit.theme")

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
---`transparent` (shape = "classic"): the resolved background is always the
---window's own, whatever `color.bg` says -- "classic" means no visible box, a
---custom bg would put one back.
---
---`color` may be a zero-arg function, re-called fresh here every time --
---same "always live, never cached" shape `resolve_text`/`resolve_visible`
---already use. What this is actually for: a consumer that wants the chip to
---track something with no single stable highlight group of its own (e.g.
---this host's statusline, which switches *which* `St_<Mode>Mode` group it
---references as the mode changes, rather than one group whose own colour
---changes) can compute the group name (or an explicit `{fg,bg}`) itself, on
---every call, instead of picking one fixed source up front.
---@param color Lib.UI.Kit.ChipColor|fun():Lib.UI.Kit.ChipColor|nil
---@param transparent boolean|nil
---@return { fg: integer, bg: integer, themed: boolean }
local function resolve_colors(color, transparent)
  local resolved_color = color
  if type(color) == "function" then
    local ok, out = pcall(color)
    resolved_color = ok and out or nil
  end
  if type(resolved_color) == "table" then
    local fg = as_color_number(resolved_color.fg) or resolve_hl(DEFAULT_HL_GROUP).fg or 0xc0caf5
    local bg = transparent and window_bg() or (as_color_number(resolved_color.bg) or window_bg())
    return { fg = fg, bg = bg, themed = false }
  end
  local group = type(resolved_color) == "string" and resolved_color or DEFAULT_HL_GROUP
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
    -- Not `ok and out and true or (ok and false or nil)`: that "a and b or
    -- c" idiom breaks the moment `out` is itself `false` -- `ok and out`
    -- then evaluates to `false` regardless of `ok`, so the expression
    -- always falls through to the `or` branch and returns `nil` ("not
    -- set") instead of the caller's actual `false`. In practice this made
    -- a `visible = function() return X end` provider that returns `false`
    -- indistinguishable from one returning `nil`/erroring: M.refresh()'s
    -- `if visible == nil then visible = text ~= "" end` fallback then took
    -- over and re-showed a chip with non-empty text regardless -- e.g.
    -- sessions.nvim's own auto-hide timer flips its `visible` closure to
    -- `false` and calls refresh(), and the chip never actually hid.
    local ok, out = pcall(v)
    if not ok or type(out) ~= "boolean" then
      return nil
    end
    return out
  end
  if type(v) == "boolean" then
    return v
  end
  return nil
end

---@internal
---lib.nvim.ui.kit.chip shape -> lib.nvim.ui.kit.theme preset name, for every bordered shape.
---Anything not listed here (`"chip"`, `"classic"`, an unrecognized value)
---falls back to `"minimal"` (borderless) below.
---@type table<string, string>
local SHAPE_THEME_PRESET = {
  rounded_chip = "rounded",
  dock_left = "dock_left",
}

---@param shape Lib.UI.Kit.Preset|"dock_left"|nil
---@return string  # a lib.nvim.ui.kit.theme preset name
local function preset_for_shape(shape)
  return SHAPE_THEME_PRESET[shape] or "minimal"
end

---@internal
---@param shape Lib.UI.Kit.Preset|nil
---@return boolean  # "classic": no visible box, just coloured text over the window behind it
local function is_transparent_shape(shape)
  return shape == "classic"
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
    -- pcall, not a bare call: a raised error would otherwise skip the
    -- `entry.busy = false` below and leave it stuck true forever, silently
    -- turning every future M.refresh(id) for this chip into a no-op with no
    -- recovery short of an explicit unmount()+mount(). Re-raised once busy
    -- is safely cleared, so error visibility is unchanged. Method + self
    -- passed directly (not wrapped in a closure) -- same style as
    -- open_window()'s pcall below, no per-call closure allocation.
    local ok, err = pcall(entry.surf.close, entry.surf)
    entry.busy = false
    if not ok then
      error(err, 0)
    end
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
  -- pcall for the same reason close_window() above uses one: a raised error
  -- must still clear `entry.busy` before propagating, or it gets stuck true.
  local ok, surf = pcall(surface.open, {
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
  if not ok then
    error(surf, 0)
  end
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
  -- `entry.pulse_active = false` alongside this: opening a (re-)created
  -- window always paints the *steady* colour, never a still-pending pulse's
  -- override (see below), which ends that pulse's visual effect right here
  -- -- so the flag that tells M.refresh()/the ColorScheme/VimEnter handlers
  -- "leave colour alone, a pulse owns it" must end with it, too. Found by
  -- adversarial review, live-reproduced: leaving it `true` past this point
  -- let a still-pending pulse's now-stale `pulse_active` keep blocking any
  -- *unrelated* colour change (a plain M.mount(id, {color=...}), or a
  -- ColorScheme re-tint) for up to the rest of the original pulse's
  -- `duration_ms`, even though the window it was guarding had already moved
  -- on to the steady colour.
  entry.pulse_active = false
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
      local row, col
      local docked = entry.dock and edge.v == "bottom" and status_rows > 0
      if docked then
        -- Sit flush ON the statusline row itself, fused with it, instead of
        -- floating in this corner's normal separate-box-with-a-gap stack.
        -- Degrades to the `else` branch below (unchanged) when there is no
        -- statusline row to dock against at all (`laststatus = 0`, or no
        -- statusline plugin active) -- `dock` is never a hard requirement
        -- on one being there.
        row = vim.o.lines - vim.o.cmdheight - 1
        -- Flush at col 0, same as the `else` branch below -- see that
        -- branch's own comment for why `col = 0` is correct even for
        -- `dock_left`'s blank-left-edge border array. (History: `96e695d`/
        -- `305e49b` briefly used `col = -1` here on the theory that Neovim
        -- reserves a screen column for that border position even though
        -- nothing is drawn there. That theory is correct in isolation
        -- (confirmed via a headless `nvim_open_win` probe) but did not
        -- explain the actual symptom: live screenshots before and after
        -- that change showed the chip's first visible pixel at the exact
        -- same screen column, proving `col` was never the cause. The real
        -- source was this user's own WezTerm `window_padding = "1cell"`
        -- setting -- set deliberately, for `images.nvim`'s OSC-1337 image
        -- placement, see `terminals/wezterm/config/experimental.lua` in
        -- their `Configs` repo -- which insets WezTerm's entire terminal
        -- grid by one cell on every side, outside of and unreachable by
        -- anything Neovim draws. No `col` value can compensate for padding
        -- applied by the terminal emulator around its own grid. Reverted
        -- rather than left in as a no-op: it also made `entry.border`
        -- overrides via `theme.setup()` a live footgun for no actual
        -- benefit.)
        col = 0
      else
        row = edge.v == "top" and offset
          or math.max(0, vim.o.lines - vim.o.cmdheight - status_rows - offset - box_h + 1)
        -- Flush against the left edge (col 0), not inset by MARGIN -- a
        -- bordered float's `col` is where its own border starts, so 0 already
        -- sits exactly at the screen edge without clipping anything. The right
        -- edge keeps its MARGIN inset so a right-anchored chip isn't flush
        -- against the terminal's own right border.
        col = edge.h == "left" and 0
          or math.max(0, vim.o.columns - entry.width - MARGIN - (entry.border == "none" and 0 or 2))
      end
      -- A plain per-chip nudge on top of the anchor/dock placement above,
      -- for a caller that needs to fine-tune this one chip's position for
      -- reasons local to their own setup (a specific font/cell size, a
      -- deliberate visual offset from a neighbouring UI element, ...) --
      -- entirely generic, no awareness of any particular reason baked in
      -- here. Does NOT reach past what Neovim can already draw into: a
      -- host terminal's own OUTER padding (applied around its whole grid,
      -- e.g. WezTerm's `window_padding`) sits outside that grid entirely,
      -- so no `row`/`col` value, offset or otherwise, can compensate for
      -- it -- confirmed live, see the `col = -1` revert above this same
      -- function went through for exactly that reason. A fractional
      -- offset is accepted but never more precise than its own
      -- `math.floor()`: `nvim_win_set_config`'s builtin (non-multigrid)
      -- implementation -- what a plain terminal client uses -- always
      -- rounds a fractional `row`/`col` down to the nearest integer
      -- (`:h nvim_open_win()`), so e.g. `col_offset = 0.5` lands on the
      -- exact same column as `0`, not "half a cell" over.
      row = row + entry.row_offset
      col = col + entry.col_offset
      pcall(api.nvim_win_set_config, entry.win, {
        relative = "editor",
        row = row,
        col = col,
        width = entry.width,
      })
      -- A docked entry doesn't occupy a slot in this corner's stack at all
      -- (it sits on the statusline row, wherever that is) -- advancing
      -- `offset` for it would only push any OTHER, non-docked chip at the
      -- same anchor further away than it needs to be.
      if not docked then
        offset = offset + box_h + MARGIN
      end
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
        and not entry.pulse_active
      then
        apply_colors(entry, resolve_colors(entry.color, is_transparent_shape(entry.shape)))
      end
    end
  end, {
    group = group,
    desc = "lib.nvim.ui.kit.chip: re-tint theme-linked chips",
  })

  -- A consumer that mounts a chip during plugin-spec loading (`lazy = false`,
  -- e.g. sessions.nvim's `bindings.autocmds.enable()`) does so *before*
  -- `VimEnter` -- before some other startup-time config (a statusline plugin
  -- setting `laststatus`, a colorscheme finishing) has necessarily run yet.
  -- `M.refresh()`'s own `reflow()`/colour resolution always reads live
  -- `vim.o.*`/highlight state, so it is correct in principle, but it only
  -- re-runs on this module's own trigger events -- none of which mean
  -- "Neovim's own startup has actually finished" -- so an early mount can sit
  -- at a stale row/col and colour until whatever unrelated later event
  -- happens to fire next.
  --
  -- `VimEnter` + `vim.schedule()`, not `UIEnter`: measured live (headless
  -- repro) that `UIEnter` never fires at all in a `--headless` run, which
  -- would make this settle pass silently skip on any headless start; `VimEnter`
  -- always fires. This mirrors the same choice this user's own nvim config
  -- already made for the identical problem (`startup.UI_READY`'s own doc
  -- comment: "does NOT use lazy.nvim's `User VeryLazy`... measured not firing
  -- at all in headless runs"). `once = true`: this is a startup settle, not a
  -- recurring resync -- `ColorScheme`/`VimResized`/`TabEnter` above stay
  -- responsible for anything that changes after startup.
  autocmd.create("VimEnter", function()
    vim.schedule(function()
      for _, entry in pairs(chips) do
        if entry.win and api.nvim_win_is_valid(entry.win) and not entry.pulse_active then
          apply_colors(entry, resolve_colors(entry.color, is_transparent_shape(entry.shape)))
        end
      end
      reflow()
    end)
  end, {
    group = group,
    once = true,
    desc = "lib.nvim.ui.kit.chip: re-settle colour/position once Neovim's own startup has finished",
  })
end

---@internal
---Opt-in `ModeChanged` tracking, scoped to the one chip that asks for it --
---an autocmd id stored on its own entry, not a blanket subscription every
---`lib.nvim.ui.kit.chip` consumer pays for regardless of whether it wants mode
---tracking (`ModeChanged` fires on every mode switch, high-frequency enough
---that this matters). Registers or tears down as `opts.track_mode` flips
---between `M.mount()` calls; already-matching state is a no-op.
---@param entry table
---@param track_mode boolean|nil
local function ensure_mode_tracking(entry, track_mode)
  if track_mode ~= nil then
    entry.track_mode = track_mode
  end
  if entry.track_mode and not entry.track_mode_autocmd_id then
    -- No `clear` argument here: `ensure_hooks()` already created (and
    -- cleared) this group once. Passing `true` again -- found by adversarial
    -- review, live-reproduced -- re-clears an ALREADY-EXISTING group
    -- (`lib.nvim.bindings.autocmd`'s own documented behaviour: re-requesting
    -- a cached group with `clear = true` re-issues `nvim_create_augroup`
    -- with `clear = true`), wiping every autocmd already in it -- not just
    -- this chip's own, but `ensure_hooks()`'s VimResized/TabEnter/
    -- ColorScheme/VimEnter and any OTHER chip's own ModeChanged tracker.
    -- Exactly the hazard `lib.nvim.ui.kit.picker` already documents for itself
    -- (its own comment on why it suffixes its group name per-window rather
    -- than reusing one shared name with `clear = true`).
    local group = autocmd.group("UiKitChip")
    local id = entry.id
    entry.track_mode_autocmd_id = autocmd.create("ModeChanged", function()
      M.refresh(id)
    end, {
      group = group,
      desc = ("lib.nvim.ui.kit.chip: track mode changes for %q"):format(id),
    })
  elseif not entry.track_mode and entry.track_mode_autocmd_id then
    autocmd.delete(entry.track_mode_autocmd_id)
    entry.track_mode_autocmd_id = nil
  end
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
  entry.shape = presets.normalize(opts.shape, "lib.nvim.ui.kit.chip")
    or entry.shape
    or "rounded_chip"
  if opts.color ~= nil then
    entry.color = opts.color
  end
  entry.zindex = opts.zindex or entry.zindex or 60
  -- `false` is as legitimate a value as `true` here (same reasoning as
  -- `visible` above), so this needs its own nil check too.
  if opts.dock ~= nil then
    entry.dock = opts.dock
  end
  -- `0` is truthy in Lua, so the plain `or` idiom (unlike `dock`/`visible`
  -- above) already does the right thing here: an explicit `opts.row_offset
  -- = 0` still overwrites a previous nonzero value instead of falling
  -- through to it.
  entry.row_offset = opts.row_offset or entry.row_offset or 0
  entry.col_offset = opts.col_offset or entry.col_offset or 0

  ensure_hooks()
  ensure_mode_tracking(entry, opts.track_mode)
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
  -- Read straight from `lib.nvim.ui.kit.theme` rather than a hardcoded "minimal" ->
  -- "none" / anything-else -> "rounded" guess: correct for any preset
  -- `preset_for_shape` maps to, including `dock_left`'s glyph array, not
  -- just the two originally hand-coded here. Deliberately NOT cached on
  -- `entry.shape` (an earlier version of this did): `lib.nvim.ui.kit.theme.setup()`
  -- lets any plugin redefine a preset's border at runtime, and a cache keyed
  -- only on the unchanged shape name would then keep showing the stale
  -- definition indefinitely for an already-mounted chip. `theme.resolve()`
  -- deep-copies a small table -- negligible next to `resolve_colors()`
  -- already running fresh on every refresh() a few lines down.
  entry.border = theme.resolve(preset_for_shape(entry.shape)).border

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

    -- Skipped entirely while a pulse is active (`entry.pulse_active`, set by
    -- M.pulse() and cleared by its own deferred revert): this reconciliation
    -- exists to keep the window's colour in step with `entry.color`, the
    -- *steady* configured colour -- exactly what a pulse is a temporary,
    -- intentional deviation from. Without this guard, `refresh()` running
    -- for any other reason at all (a consumer's own dirty-tracking autocmd,
    -- or even a second M.mount() call, which always tail-calls M.refresh())
    -- during a pulse's `duration_ms` window would see the pulse colour as
    -- "not what entry.color resolves to" and immediately snap it back,
    -- cutting the pulse short -- a straight shot around every guard
    -- M.pulse()'s own deferred callback has, since this path never goes
    -- through it. sessions.nvim wires refresh() into ordinary
    -- BufAdd/BufDelete/WinNew/WinClosed/TabNewEntered/TabClosed
    -- dirty-tracking, so this was reachable on nearly every pulse in
    -- practice (opening/closing any window, including an unrelated plugin's
    -- float, during the ~300ms default pulse window).
    if not entry.pulse_active then
      local colors = resolve_colors(entry.color, is_transparent_shape(entry.shape))
      local applied = entry.applied_colors
      -- `themed` is compared too, not just the rendered fg/bg: switching
      -- `entry.color` between a table and a highlight-group name can resolve
      -- to identical pixels (e.g. a custom fg that happens to match a
      -- group's fg on a transparent chip, where bg is always `window_bg()`
      -- either way). Comparing fg/bg alone would then skip `apply_colors`
      -- and leave `applied_colors.themed` stale -- and the `ColorScheme`
      -- handler above gates its re-tint on exactly that field, so a chip
      -- that just became (or stopped being) theme-linked would silently
      -- keep the wrong behaviour on every future colorscheme change.
      if
        not applied
        or applied.fg ~= colors.fg
        or applied.bg ~= colors.bg
        or applied.themed ~= colors.themed
      then
        apply_colors(entry, colors)
      end
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
  -- `entry.pulse_active`: read by M.refresh()'s colour reconciliation (and
  -- the ColorScheme/VimEnter handlers in ensure_hooks()) to leave this
  -- colour alone until the revert below actually runs -- otherwise any of
  -- those, triggered by anything else entirely, would immediately see the
  -- pulse colour as "not what entry.color resolves to" and snap it back.
  entry.pulse_active = true

  -- Two checks, not one, because either alone reintroduces a bug this
  -- function has already been through:
  --
  -- * A captured window handle (`e.win == win`, an earlier version of this)
  --   breaks the moment the chip's window closes and reopens while the
  --   pulse is pending (e.g. a hide/show cycle) -- the captured handle can
  --   never match again, so the revert silently never happens.
  -- * A per-entry generation counter ALONE (a later version of this) fixes
  --   that, but `M.unmount(id)` followed by `M.mount(id, ...)` for the same
  --   id allocates a brand-new `entry` table whose own counter restarts
  --   from scratch -- so a still-pending revert from a pulse on the OLD,
  --   now-orphaned entry can land on generation 1 of the NEW entry's own
  --   first pulse purely by numeric coincidence, cutting it short. The old
  --   entry's pending timer was never cancelled by unmount() either, so it
  --   still fires.
  --
  -- Capturing the entry TABLE itself (not just its id) and requiring
  -- `chips[id] == target` closes that gap: after unmount()+mount(), the new
  -- entry is a different table, so a stale callback from the old one no
  -- longer matches regardless of what its generation counter reads. The
  -- generation counter (same shape as sessions.nvim's own `hide_generation`,
  -- sessions/chip.lua) still does its own job for two overlapping pulses on
  -- the SAME entry (window replaced or not) -- entry identity alone can't
  -- tell those apart, since it's the same table both times.
  local target = entry
  target.pulse_generation = (target.pulse_generation or 0) + 1
  local generation = target.pulse_generation
  vim.defer_fn(function()
    if chips[id] == target and target.pulse_generation == generation then
      -- Cleared even if the window is gone by now: this pulse is over
      -- either way, and leaving it `true` would wrongly keep M.refresh()'s
      -- colour reconciliation switched off forever for this entry.
      target.pulse_active = false
      if target.win and api.nvim_win_is_valid(target.win) then
        apply_colors(target, resolve_colors(target.color, is_transparent_shape(target.shape)))
      end
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
  if entry.track_mode_autocmd_id then
    autocmd.delete(entry.track_mode_autocmd_id)
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
