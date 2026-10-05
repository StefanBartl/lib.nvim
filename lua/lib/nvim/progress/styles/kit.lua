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
local notify = require("lib.nvim.notify").create("[lib.nvim.progress]")

---@internal
---Set to `true` by `finish`/`cancel` the instant they're called (before any
---scheduling), keyed by `state` (the `surf` handle). `update`'s deferred
---render checks this before touching the surface, so a stale `update` whose
---render was already queued via `vim.schedule` can't fire *after*
---`finish`/`cancel` has rendered the final text and overwrite it for the
---rest of the 800ms close delay -- `init.lua`'s own `done` flag can't help
---here, since it only blocks a *new* `handle:update()` call, not one whose
---style-level render was already in flight when `finish`/`cancel` ran.
---Weak-keyed so an entry is collected once nothing else references `state`.
local done_states = setmetatable({}, { __mode = "k" })

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
---Runs `fn` immediately when already on the main loop, otherwise defers it
---via `vim.schedule`. `surf:is_valid()`/`nvim_win_get_width`/
---`nvim_win_set_config` are forbidden in a fast-event context (E5560:
---"nvim_win_is_valid must not be called in a fast event context"), and a
---caller's completion callback (e.g. a `vim.system` exit handler not itself
---wrapped in `vim.schedule`) isn't guaranteed to already be on the loop --
---see `lib.nvim.progress.styles.statusline`'s `request_redraw` for the same
---pattern.
---
---On the deferred path, `fn` runs after `update`/`finish`/`cancel` has
---already returned -- outside `init.lua`'s `pcall(style.*, ...)`, which only
---guards the synchronous call. Without its own `pcall` here, a throw inside
---a deferred `fn` would escape as a raw scheduled-callback error instead of
---the module's usual `notify.error`, and -- since `init.lua` never saw a
---failure -- its `schedule_cleanup` retry would never fire either, silently
---reintroducing the orphaned-chip bug this style was just fixed for.
---@param fn fun()
local function on_main_loop(fn)
  if vim.in_fast_event() then
    vim.schedule(function()
      local ok, err = pcall(fn)
      if not ok then
        notify.error(("kit style deferred render failed: %s"):format(tostring(err)))
      end
    end)
  else
    fn()
  end
end

---@internal
---@param bufnr integer
---@param spec Lib.Progress.Spec
---@param request_cancel fun()
local function bind_cancel_on_escape(bufnr, spec, request_cancel)
  vim.keymap.set("n", "<Esc>", function()
    local label = spec.title ~= "" and require("lib.lua.strings.core").rtrim(spec.title) or "This operation"
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
  on_main_loop(function()
    if done_states[state] then
      -- finish()/cancel() already rendered the final text (and scheduled
      -- its close) after this render was queued; rendering the stale
      -- in-progress line now would overwrite that for the rest of the
      -- close delay.
      return
    end
    local ok, err = pcall(function()
      maybe_resize(state, line)
      set_line(state, line)
    end)
    if not ok then
      -- Unlike a synchronous update failure, this never reaches init.lua's
      -- pcall (update() already returned by the time this deferred closure
      -- runs), so style_failed/schedule_cleanup can't engage for it. Close
      -- immediately instead of leaving a broken, unclosable chip open --
      -- afterward every further render on this `state` is a no-op via the
      -- `is_valid()` guards in `set_line`/`maybe_resize`/`close`, so this
      -- can't fire more than once per handle.
      notify.error(("kit style update render failed: %s"):format(tostring(err)))
      close(state)
    end
  end)
  return state
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function finish(state, spec)
  if not state then
    return
  end
  done_states[state] = true
  local line = render_line(spec)
  on_main_loop(function()
    -- Each render step is separately pcall'd -- a failed resize must not
    -- skip the line update -- and `close` must still get scheduled below
    -- even if both fail, or the window this handle opened would once again
    -- outlive it.
    local resize_ok, resize_err = pcall(maybe_resize, state, line)
    local line_ok, line_err = pcall(set_line, state, line)
    if not (resize_ok and line_ok) then
      notify.error(("kit style finish render failed: %s"):format(tostring(resize_err or line_err)))
    end
    vim.defer_fn(function()
      close(state)
    end, 800)
  end)
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function cancel(state, spec)
  if not state then
    return
  end
  done_states[state] = true
  local text = spec.text and spec.text ~= "" and spec.text or "cancelled"
  local line = spec.title .. text
  on_main_loop(function()
    -- Same best-effort, independently pcall'd render as `finish` above:
    -- `close` always gets scheduled, even if rendering the cancelled state
    -- fails.
    local resize_ok, resize_err = pcall(maybe_resize, state, line)
    local line_ok, line_err = pcall(set_line, state, line)
    if not (resize_ok and line_ok) then
      notify.error(("kit style cancel render failed: %s"):format(tostring(resize_err or line_err)))
    end
    vim.defer_fn(function()
      close(state)
    end, 800)
  end)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
