---@module 'lib.nvim.ui.kit.preview'
--- Live theme playground. Opens a new tab split in two: a left window with an
--- editable Lua config (a theme preset name or an override table) and a right
--- window that re-renders a gallery of kit widgets with that theme as you type.
---
---   :KitPreview            -- or require("lib.nvim.ui.kit").preview()
---
--- The gallery is a static, faithful rendering (borders + KitSelection /
--- KitAccent / KitTitle / KitMuted highlights) rather than live interactive
--- floats, so editing the config never fights the components for focus.

local theme = require("lib.nvim.ui.kit.theme")

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("lib_kit_preview")

--- Starting content of the config buffer.
local TEMPLATE = {
  "-- lib.nvim.ui.kit — live theme playground.",
  "-- Edit the value below; the preview on the right updates as you type.",
  '-- Return a preset name ("minimal"|"rounded"|"solid"|"double"|"ascii")',
  "-- or an override table merged over the active default. Press q to close.",
  "",
  "return {",
  '  border = "rounded",',
  "  hl = {",
  '    selection = "PmenuSel",',
  '    accent    = "Special",',
  '    title     = "FloatTitle",',
  "  },",
  "}",
}

--- Evaluate the config buffer to a theme argument.
---@param bufnr integer
---@return boolean ok, any theme_arg_or_error
local function eval_config(bufnr)
  local src = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local chunk, load_err = loadstring(src, "kit-preview-config")
  if not chunk then
    return false, load_err
  end
  local ok, result = pcall(chunk)
  if not ok then
    return false, result
  end
  return true, result
end

--- Build the gallery: returns lines and a list of highlights
--- ({ row, group } for whole-line, or { row, col0, col1, group }).
---@param resolved Lib.UI.Kit.Theme
---@return string[] lines, table[] hls
local function render_gallery(resolved)
  local g = theme.border_glyphs(resolved)
  local W = 34 -- inner width of the demo boxes

  local lines, hls = {}, {}
  local function push(text, group)
    lines[#lines + 1] = text or ""
    if group then
      hls[#hls + 1] = { row = #lines - 1, group = group }
    end
  end

  -- One bordered box with a title and pre-built body rows. `body` entries are
  -- { text, group? }; the box edges are drawn with the theme's glyphs.
  local function box(title, body)
    if g then
      local top = g.tl .. string.rep(g.h, W) .. g.tr
      push(top, "KitBorder")
      -- title row
      local t = " " .. title .. " "
      local pad = math.max(0, W - vim.fn.strdisplaywidth(t))
      push(g.v .. t .. string.rep(" ", pad) .. g.v, "KitTitle")
      for _, row in ipairs(body) do
        local text = row[1]
        local w = math.max(0, W - vim.fn.strdisplaywidth(text) - 1)
        push(g.v .. " " .. text .. string.rep(" ", w) .. g.v, row[2])
      end
      push(g.bl .. string.rep(g.h, W) .. g.br, "KitBorder")
    else
      -- borderless theme: indent, no box
      push("  " .. title, "KitTitle")
      for _, row in ipairs(body) do
        push("    " .. row[1], row[2])
      end
    end
    push("")
  end

  push("Theme preview — border=" .. tostring(resolved.border), "KitMuted")
  push("")

  box("note", {
    { "A themed message float." },
    { "second line, muted hint.", "KitMuted" },
  })

  box("select", {
    { "first item" },
    { "selected item (current)", "KitSelection" },
    { "marked item (multi)", "KitAccent" },
    { "another item" },
  })

  -- confirm: a button row with the focused button highlighted (precise cols)
  if g then
    push(g.tl .. string.rep(g.h, W) .. g.tr, "KitBorder")
    push(g.v .. " confirm" .. string.rep(" ", W - 8) .. g.v, "KitTitle")
  else
    push("  confirm", "KitTitle")
  end
  local prefix = g and (g.v .. "   ") or "    "
  local btns = "[ Yes ]  [ No ]  [ Cancel ]"
  local line = prefix .. btns
  push(line)
  do
    -- highlight "[ No ]" (the focused button) with KitSelection
    local start = #prefix + #"[ Yes ]  "
    hls[#hls + 1] =
      { row = #lines - 1, col0 = start, col1 = start + #"[ No ]", group = "KitSelection" }
  end
  if g then
    push(g.bl .. string.rep(g.h, W) .. g.br, "KitBorder")
  end
  push("")
  push("q = close · edit the left buffer to restyle", "KitMuted")

  return lines, hls
end

--- Re-render the preview buffer from the config buffer.
---@param config_buf integer
---@param preview_buf integer
function M.render(config_buf, preview_buf)
  if not api.nvim_buf_is_valid(preview_buf) then
    return
  end

  local ok, arg = eval_config(config_buf)

  local lines, hls
  if not ok then
    lines = { "⚠ config error:", "", tostring(arg) }
    hls = { { row = 0, group = "KitError" } }
  else
    local resolved = theme.resolve(arg)
    theme.materialize(resolved)
    lines, hls = render_gallery(resolved)
  end

  api.nvim_set_option_value("modifiable", true, { buf = preview_buf })
  api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = preview_buf })

  api.nvim_buf_clear_namespace(preview_buf, NS, 0, -1)
  for _, h in ipairs(hls) do
    if h.col0 then
      pcall(api.nvim_buf_set_extmark, preview_buf, NS, h.row, h.col0, {
        end_col = h.col1,
        hl_group = h.group,
      })
    else
      pcall(api.nvim_buf_set_extmark, preview_buf, NS, h.row, 0, { line_hl_group = h.group })
    end
  end
end

--- Open the live theme playground in a new tab.
---@return integer config_buf, integer preview_buf
function M.open()
  vim.cmd("tabnew")
  local config_win = api.nvim_get_current_win()
  local config_buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("bufhidden", "wipe", { buf = config_buf })
  api.nvim_set_option_value("filetype", "lua", { buf = config_buf })
  api.nvim_buf_set_lines(config_buf, 0, -1, false, TEMPLATE)
  api.nvim_win_set_buf(config_win, config_buf)

  vim.cmd("vsplit")
  local preview_win = api.nvim_get_current_win()
  local preview_buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf })
  api.nvim_set_option_value("modifiable", false, { buf = preview_buf })
  api.nvim_win_set_buf(preview_win, preview_buf)
  api.nvim_set_option_value("wrap", false, { win = preview_win })

  -- Live re-render as the config changes.
  local group = api.nvim_create_augroup("lib_kit_preview_" .. config_buf, { clear = true })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = config_buf,
    callback = function()
      M.render(config_buf, preview_buf)
    end,
    desc = "lib.nvim.ui.kit.preview: live re-render",
  })

  -- q closes the whole playground tab from either window.
  local function close()
    pcall(vim.cmd, "tabclose")
  end
  for _, b in ipairs({ config_buf, preview_buf }) do
    vim.keymap.set("n", "q", close, { buffer = b, nowait = true })
  end

  M.render(config_buf, preview_buf)
  api.nvim_set_current_win(config_win)

  return config_buf, preview_buf
end

return M
