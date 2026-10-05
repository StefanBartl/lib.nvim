---@module 'lib.nvim.progress.styles.float'
---Interactive floating-window renderer.
---
---Unlike "notify"/"statusline"/"fidget", this style owns a small window the
---user can deliberately focus. It never steals focus itself (`enter = false`,
---bottom-right corner) — the running operation never interrupts whatever the
---user is doing. Only while that window IS the current buffer does `<Esc>`
---(normal mode) ask for cancellation; the keymap is buffer-local, so nothing
---happens at all while any other window is focused.

require("lib.nvim.progress.@types")

local window = require("lib.nvim.window")
local notify = require("lib.nvim.notify").create("[lib.nvim.progress]")

---@internal
---Set to `true` by `finish`/`cancel` the instant they're called (before any
---scheduling), keyed by `state` (the `{winid, bufnr}` table `start` handed
---back). `update`'s deferred render checks this before touching the window,
---so a stale `update` whose render was already queued via `vim.schedule`
---can't fire *after* `finish`/`cancel` has rendered the final text and
---overwrite it for the rest of the 800ms close delay -- `init.lua`'s own
---`done` flag can't help here, since it only blocks a *new*
---`handle:update()` call, not one whose style-level render was already in
---flight when `finish`/`cancel` ran. Weak-keyed so an entry is collected
---once nothing else references `state`.
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
---@param bufnr integer|nil
---@param line string
local function set_line(bufnr, line)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
  vim.bo[bufnr].modifiable = false
end

---@internal
---@param winid integer|nil
local function close(winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

---@internal
---Runs `fn` immediately when already on the main loop, otherwise defers it
---via `vim.schedule`. `nvim_buf_is_valid`/`nvim_buf_set_lines`/
---`nvim_win_is_valid`/`nvim_win_close` are forbidden in a fast-event context
---(E5560), and a caller's completion callback (e.g. a `vim.system` exit
---handler not itself wrapped in `vim.schedule`) isn't guaranteed to already
---be on the loop -- see `lib.nvim.progress.styles.kit` for the same pattern.
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
        notify.error(("float style deferred render failed: %s"):format(tostring(err)))
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
    local label = spec.title ~= "" and require("lib.lua.strings.core").rtrim(spec.title)
      or "This operation"
    local choice = vim.fn.confirm(label .. " is still running. Abort it?", "&Yes\n&No", 2)
    if choice == 1 then
      request_cancel()
    end
  end, { buffer = bufnr, nowait = true, silent = true, desc = "lib.nvim.progress: cancel" })
end

---@param spec Lib.Progress.Spec
---@param _opts Lib.Progress.Opts
---@param request_cancel fun()
---@return { winid: integer|nil, bufnr: integer|nil }
local function start(spec, _opts, request_cancel)
  -- Clamped to make_scratch's own ceiling: `col` below is computed from
  -- `width` to keep the float right-anchored, so it has to match what
  -- `nvim_open_win` actually ends up using. On a narrow editor
  -- (`vim.o.columns - 4 < 40`) an unclamped 40 here would compute `col` for
  -- a wider float than the one that actually opens, pinning it to the wrong
  -- edge instead of near the right.
  local width = math.min(40, window.max_float_width())
  local winid, bufnr = window.make_scratch({
    lines = { render_line(spec) },
    width = width,
    height = 1,
    relative = "editor",
    row = vim.o.lines - 4,
    col = math.max(0, vim.o.columns - width - 2),
    border = "rounded",
    focusable = true,
    enter = false,
    modifiable = false,
    filetype = "replacer-progress",
  })

  if winid and bufnr then
    bind_cancel_on_escape(bufnr, spec, request_cancel)
  end

  return { winid = winid, bufnr = bufnr }
end

---@param state { winid: integer|nil, bufnr: integer|nil }
---@param spec Lib.Progress.Spec
---@return { winid: integer|nil, bufnr: integer|nil }
local function update(state, spec)
  if state then
    local line = render_line(spec)
    on_main_loop(function()
      if done_states[state] then
        -- finish()/cancel() already rendered the final text (and scheduled
        -- its close) after this render was queued; rendering the stale
        -- in-progress line now would overwrite that for the rest of the
        -- close delay.
        return
      end
      local ok, err = pcall(set_line, state.bufnr, line)
      if not ok then
        -- Unlike a synchronous update failure, this never reaches
        -- init.lua's pcall (update() already returned by the time this
        -- deferred closure runs), so style_failed/schedule_cleanup can't
        -- engage for it. Close immediately instead of leaving a broken,
        -- unclosable chip open -- afterward every further render on this
        -- `state` is a no-op via the `nvim_*_is_valid` guards in
        -- `set_line`/`close`, so this can't fire more than once per handle.
        notify.error(("float style update render failed: %s"):format(tostring(err)))
        close(state.winid)
      end
    end)
  end
  return state
end

---@param state { winid: integer|nil, bufnr: integer|nil }
---@param spec Lib.Progress.Spec
local function finish(state, spec)
  if not state then
    return
  end
  done_states[state] = true
  local line = render_line(spec)
  on_main_loop(function()
    -- pcall'd separately from the `close` scheduling below: a failed render
    -- must not skip closing the window this handle opened.
    local ok, err = pcall(set_line, state.bufnr, line)
    if not ok then
      notify.error(("float style finish render failed: %s"):format(tostring(err)))
    end
    vim.defer_fn(function()
      close(state.winid)
    end, 800)
  end)
end

---@param state { winid: integer|nil, bufnr: integer|nil }
---@param spec Lib.Progress.Spec
local function cancel(state, spec)
  if not state then
    return
  end
  done_states[state] = true
  local text = spec.text and spec.text ~= "" and spec.text or "cancelled"
  local line = spec.title .. text
  on_main_loop(function()
    -- Same best-effort render as `finish` above: `close` always gets
    -- scheduled, even if rendering the cancelled state fails.
    local ok, err = pcall(set_line, state.bufnr, line)
    if not ok then
      notify.error(("float style cancel render failed: %s"):format(tostring(err)))
    end
    vim.defer_fn(function()
      close(state.winid)
    end, 800)
  end)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
