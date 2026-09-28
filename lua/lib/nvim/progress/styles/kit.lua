---@module 'lib.nvim.progress.styles.kit'
---Themed floating-window renderer built on `lib.nvim.ui.kit`'s `surface`
---primitive. Same interaction model as the "float" style — never steals
---focus, focus it deliberately and press <Esc> for a cancel confirm — but
---visually coordinated with the caller's configured ui.kit theme/preset
---(border, highlight groups) instead of a fixed look.
---
---Pass `opts.kit_theme` (a preset name or partial override table, see
---`lib.nvim.ui.kit.theme`) to pick a specific preset for this handle;
---omitted, the active default preset applies.

require("lib.nvim.progress.@types")

local max_float_width = require("lib.nvim.window").max_float_width

---@internal
---@param spec Lib.Progress.Spec
---@return string
local function render_suffix(spec)
  if type(spec.current) == "number" then
    if type(spec.total) == "number" and spec.total > 0 then
      return string.format(" (%d/%d)", spec.current, spec.total)
    end
    return string.format(" (%d)", spec.current)
  end
  return ""
end

---@internal
---@param spec Lib.Progress.Spec
---@return string
local function render_line(spec)
  local text = spec.text and spec.text ~= "" and spec.text or "working…"
  return spec.title .. text .. render_suffix(spec)
end

---@internal
---@param surf any lib.nvim.ui.kit surface handle
---@param line string
local function set_line(surf, line)
  if surf and surf:is_valid() then
    surf:set_lines({ line })
  end
end

---@internal
---@param surf any lib.nvim.ui.kit surface handle
local function close(surf)
  if surf and surf:is_valid() then
    surf:close()
  end
end

---@internal
---The width `line` needs -- a floor for a short/bare render, otherwise its
---own display width, clamped to the same ceiling `make_scratch` clamps the
---actually-opened window to.
---@param line string
---@return integer
local function fit_width(line)
  return math.min(math.max(20, vim.fn.strdisplaywidth(line) + 2), max_float_width())
end

---@internal
---Grow (never shrink) `surf` to fit `line` when it no longer does, up to the
---same ceiling `start()` clamps to. A one-way ratchet, not a full resync on
---every render: row/height stay exactly what `start()` opened with (pinned
---near the bottom, one line tall) -- only width/col ever need to move, and
---shrinking back down would make the float visibly jitter as
---`current`/`total` tick between fewer and more digits. `nvim_win_set_config`
---direct rather than a `Surface` method: `lib.nvim.ui.kit` is a frozen
---mirror of `ui.kit` (see ui.nvim's TESTS/kit_drift_spec.lua) that takes bug
---fixes but not new features, same as every other resize/reposition call
---site in this tree (toast.lua, chip.lua, chooser.lua, ...).
---@param surf any lib.nvim.ui.kit surface handle
---@param line string
local function maybe_resize(surf, line)
  if not surf or not surf:is_valid() then
    return
  end
  local needed = fit_width(line)
  if needed <= vim.api.nvim_win_get_width(surf.winid) then
    return
  end
  pcall(vim.api.nvim_win_set_config, surf.winid, {
    relative = "editor",
    row = vim.o.lines - 4,
    col = math.max(0, vim.o.columns - needed - 2),
    width = needed,
    height = 1,
  })
end

---@internal
---@param bufnr integer
---@param spec Lib.Progress.Spec
---@param request_cancel fun()
local function bind_cancel_on_escape(bufnr, spec, request_cancel)
  vim.keymap.set("n", "<Esc>", function()
    local label = spec.title ~= "" and spec.title:gsub("%s+$", "") or "This operation"
    local choice = vim.fn.confirm(label .. " is still running. Abort it?", "&Yes\n&No", 2)
    if choice == 1 then
      request_cancel()
    end
  end, { buffer = bufnr, nowait = true, silent = true, desc = "lib.nvim.progress: cancel" })
end

---@param spec Lib.Progress.Spec
---@param opts Lib.Progress.Opts
---@param request_cancel fun()
---@return any|nil surf
local function start(spec, opts, request_cancel)
  local ok, kit = pcall(require, "lib.nvim.ui.kit")
  if not ok then
    return nil
  end

  -- Sized to the actual first render, not a fixed 40: a caller that seeds
  -- text/current/total before this style even starts -- gitsuite's dashboard
  -- scan calls update() synchronously, ahead of the 150ms start delay, so
  -- start() never sees the bare "working…" fallback -- can already render a
  -- line past 40 cells. This style has no wrapping, so the (n/total) counter
  -- it exists to show would be the first thing silently clipped by a fixed
  -- width. update()/finish()/cancel() each grow the float in place
  -- (maybe_resize) when a later render outgrows this one, so the fix isn't
  -- limited to whatever start() happened to see first.
  local line = render_line(spec)
  local width = fit_width(line)
  local surf = kit.surface.open({
    lines = { line },
    theme = opts.kit_theme,
    width = width,
    height = 1,
    relative = "editor",
    row = vim.o.lines - 4,
    col = math.max(0, vim.o.columns - width - 2),
    title = spec.title ~= "" and spec.title or "progress",
    focusable = true,
    enter = false,
    modifiable = false,
    filetype = "replacer-progress",
  })

  if surf then
    bind_cancel_on_escape(surf.bufnr, spec, request_cancel)
  end

  return surf
end

---@param state any|nil
---@param spec Lib.Progress.Spec
---@return any|nil
local function update(state, spec)
  local line = render_line(spec)
  maybe_resize(state, line)
  set_line(state, line)
  return state
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function finish(state, spec)
  if not state then
    return
  end
  local line = render_line(spec)
  maybe_resize(state, line)
  set_line(state, line)
  vim.defer_fn(function()
    close(state)
  end, 800)
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function cancel(state, spec)
  if not state then
    return
  end
  local text = spec.text and spec.text ~= "" and spec.text or "cancelled"
  local line = spec.title .. text
  maybe_resize(state, line)
  set_line(state, line)
  vim.defer_fn(function()
    close(state)
  end, 800)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
