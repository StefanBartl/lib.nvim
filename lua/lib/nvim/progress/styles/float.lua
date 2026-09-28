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
---@param fn fun()
local function on_main_loop(fn)
  if vim.in_fast_event() then
    vim.schedule(fn)
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
    local label = spec.title ~= "" and spec.title:gsub("%s+$", "") or "This operation"
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
      set_line(state.bufnr, line)
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
  local line = render_line(spec)
  on_main_loop(function()
    set_line(state.bufnr, line)
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
  local text = spec.text and spec.text ~= "" and spec.text or "cancelled"
  local line = spec.title .. text
  on_main_loop(function()
    set_line(state.bufnr, line)
    vim.defer_fn(function()
      close(state.winid)
    end, 800)
  end)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
