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

---@param spec Lib.Progress.Spec
---@return string
local function render_line(spec)
  local text = spec.text and spec.text ~= "" and spec.text or "working…"
  return spec.title .. text .. render_suffix(spec)
end

---@param surf any lib.nvim.ui.kit surface handle
---@param line string
local function set_line(surf, line)
  if surf and surf:is_valid() then
    surf:set_lines({ line })
  end
end

---@param surf any lib.nvim.ui.kit surface handle
local function close(surf)
  if surf and surf:is_valid() then
    surf:close()
  end
end

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

  local width = 40
  local surf = kit.surface.open({
    lines = { render_line(spec) },
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
  set_line(state, render_line(spec))
  return state
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function finish(state, spec)
  if not state then
    return
  end
  set_line(state, render_line(spec))
  vim.defer_fn(function() close(state) end, 800)
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function cancel(state, spec)
  if not state then
    return
  end
  local text = spec.text and spec.text ~= "" and spec.text or "cancelled"
  set_line(state, spec.title .. text)
  vim.defer_fn(function() close(state) end, 800)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
