---@module 'lib.nvim.hover.float'
---@brief The hover window itself: a small, cursor-relative, unfocused float.
---@description
--- Deliberately *not* `lib.nvim.image_preview`'s float: that one is a
--- centred 80% window the user enters and closes with `q`. A hover must be
--- small, appear next to the cursor, never steal focus, and disappear on the
--- next cursor move — otherwise it fights the editing it is supposed to
--- annotate.
---
--- Exactly one hover window exists at a time; opening a second closes the
--- first.

local M = {}

local api = vim.api
local autocmd = require("lib.nvim.bindings.autocmd")

---@type integer|nil
local _win = nil
---@type integer|nil
local _buf = nil
---@type integer|nil
local _augroup = nil
---@type (fun())|nil Teardown for whatever was drawn into the window.
local _on_close = nil

--- Highlight groups a preview may ask for on its first line, and what each
--- links to when the user and the colorscheme have said nothing. Defined on
--- demand (see `open`) rather than at load time, so a colorscheme that comes
--- later still wins.
---
--- Three, not one: "this target does not exist" and "the server answered 500"
--- are errors, "this file has no text in it" is a statement of fact about a
--- perfectly healthy file, and colouring the third one red would report a
--- problem that is not there.
---@type table<string, string>
local HL_DEFAULTS = {
  LibHoverMissing = "DiagnosticError",
  LibHoverError = "DiagnosticError",
  LibHoverInfo = "DiagnosticHint",
}

--- Is a hover window currently open?
---@return boolean
function M.is_open()
  return _win ~= nil and api.nvim_win_is_valid(_win)
end

--- Register teardown to run when this hover closes — used by previewers that
--- draw into the window after it is already open (a rasterized PDF page
--- arriving from an async render, say) and must clear that drawing again.
---@param on_close fun()
function M.set_on_close(on_close)
  _on_close = on_close
end

--- Close the hover window, if any. Safe to call repeatedly.
---@param on_close fun()|nil Extra teardown, in addition to any registered via `set_on_close`.
function M.close(on_close)
  if _on_close then
    pcall(_on_close)
    _on_close = nil
  end
  if on_close then
    pcall(on_close)
  end

  if _augroup then
    pcall(api.nvim_del_augroup_by_id, _augroup)
    _augroup = nil
  end
  if _win and api.nvim_win_is_valid(_win) then
    pcall(api.nvim_win_close, _win, true)
  end
  if _buf and api.nvim_buf_is_valid(_buf) then
    pcall(api.nvim_buf_delete, _buf, { force = true })
  end
  _win, _buf = nil, nil
end

---@internal
--- Width/height from the content, clamped to the caller's maxima and to what
--- actually fits on screen. Width is measured in display columns rather than
--- bytes, so a CJK or emoji preview is not cut off half a cell short.
---@param lines string[]
---@param opts Lib.Hover.FloatOpts
---@return integer width
---@return integer height
local function measure(lines, opts)
  local width_of = require("lib.lua.strings.width").display_width

  local width = 1
  for _, line in ipairs(lines) do
    local w = width_of(line)
    if w > width then
      width = w
    end
  end

  width = math.min(width, opts.max_width or 80, math.max(20, vim.o.columns - 4))
  local height = math.min(#lines, opts.max_height or 20, math.max(3, vim.o.lines - 4))
  return width, math.max(height, 1)
end

--- Open (or replace) the hover window showing `lines`.
---@param lines string[]
---@param opts Lib.Hover.FloatOpts
---@return integer|nil win
---@return integer|nil buf
function M.open(lines, opts)
  opts = opts or {}
  M.close()

  -- Canvas mode: the float exists only to give a drawn image a frame and a
  -- set of coordinates, so it gets blank lines at the caller's exact size and
  -- neither text nor a title. A filename in the border and a "PNG · 10 KB"
  -- line describe a picture the reader is already looking at.
  local canvas = opts.canvas
  if canvas then
    lines = {}
    for i = 1, math.max(1, canvas.rows) do
      lines[i] = ""
    end
  end

  if not lines or #lines == 0 then
    return nil, nil
  end

  -- `nvim_buf_set_lines` rejects any element containing a newline
  -- ("'replacement string' item contains newlines") and throws, which in an
  -- async previewer's callback surfaces as a bare stack trace with no hover.
  -- Previewers assemble their lines from file contents, error strings and
  -- external tool output, so an embedded "\n" is a question of when, not if
  -- -- flattening here is one guard instead of one per previewer. Tabs are
  -- left alone; only the split is required.
  local flat = {}
  for _, line in ipairs(lines) do
    local text = type(line) == "string" and line or tostring(line)
    if text:find("\n", 1, true) then
      for _, part in ipairs(vim.split(text, "\n", { plain = true })) do
        flat[#flat + 1] = (part:gsub("\r$", ""))
      end
    else
      flat[#flat + 1] = text
    end
  end
  lines = flat

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Highlight the first line before the buffer is locked. Used wherever the
  -- first line is a verdict rather than content: the "missing" preview's ✗
  -- marker, an HTTP error status, a "this file has no text in it" badge. A
  -- filetype cannot express "this one line means something", and in each of
  -- those previews that line is the whole point.
  --
  -- `default = true` on the link, set here rather than at setup(): a
  -- colorscheme loaded after us must be able to override it, and a user who
  -- defined the group themselves must not have it overwritten.
  if opts.highlight and opts.highlight ~= "" then
    local link = HL_DEFAULTS[opts.highlight]
    if link then
      pcall(api.nvim_set_hl, 0, opts.highlight, { link = link, default = true })
    end
    pcall(api.nvim_buf_set_extmark, buf, api.nvim_create_namespace("lib.nvim.hover"), 0, 0, {
      end_row = 1,
      hl_group = opts.highlight,
      hl_eol = true,
    })
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  if not canvas and opts.filetype and opts.filetype ~= "" then
    -- `pcall`: a filetype whose ftplugin errors must not take the hover down.
    pcall(function()
      vim.bo[buf].filetype = opts.filetype
    end)
  end

  local width, height
  if canvas then
    width = math.max(1, math.min(canvas.cols, math.max(20, vim.o.columns - 4)))
    height = math.max(1, math.min(canvas.rows, math.max(3, vim.o.lines - 4)))
  else
    width, height = measure(lines, opts)
  end

  -- Positioned against the editor grid, not the cursor — even though "one
  -- line below the cursor" is exactly what is wanted here.
  --
  -- **Why.** With `relative = "cursor"`, `nvim_win_get_position` reports a
  -- column that is too large by the width of whatever sits left of the
  -- editor window (a file tree, a sidebar). Measured: a tree 26 columns wide
  -- makes a float whose frame is drawn at column ~59 report column 83.
  -- Neovim draws it correctly; only the reported number is wrong.
  --
  -- That matters because this float's geometry is not decoration: it *is*
  -- the box handed to the terminal for the image (`images.anchor` reads it
  -- back with `nvim_win_get_position`). Every consumer then computes a
  -- correct offset from a wrong origin, and the picture lands beside its own
  -- frame by the tree's width — which is precisely the bug this replaces.
  --
  -- `screenpos()` gives the cursor's true position on the editor grid, and
  -- an `editor`-relative float reports back exactly the coordinates it was
  -- given. The float lands in the same place as before; only the number it
  -- reports afterwards becomes trustworthy.
  local anchor_row, anchor_col
  do
    local cur_win = api.nvim_get_current_win()
    local cursor = api.nvim_win_get_cursor(cur_win)
    -- screenpos() is 1-based and returns {row=0, col=0} when the position is
    -- not currently visible (folded, scrolled away).
    local sp = vim.fn.screenpos(cur_win, cursor[1], cursor[2] + 1)
    if type(sp) == "table" and (sp.row or 0) > 0 and (sp.col or 0) > 0 then
      anchor_row, anchor_col = sp.row, sp.col - 1
    else
      -- Fall back to the window's own origin rather than to cursor-relative
      -- positioning: a slightly misplaced float still reports honestly, and
      -- an honest origin is what the image needs.
      local wp = api.nvim_win_get_position(cur_win)
      anchor_row, anchor_col = wp[1] + 1, wp[2]
    end
  end

  local ok, win = pcall(api.nvim_open_win, buf, false, {
    relative = "editor",
    row = anchor_row,
    col = anchor_col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    focusable = opts.focusable == true,
    noautocmd = true,
    title = not canvas and opts.title or nil,
    title_pos = not canvas and opts.title and "left" or nil,
  })
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return nil, nil
  end

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

  _win, _buf = win, buf

  -- Dismiss on the next thing the user does. `CursorMoved` alone is not
  -- enough: leaving insert mode or switching windows must also clear it, or
  -- a stale hover outlives the context it described.
  _augroup = autocmd.group("MarkdownHoverDismiss", true)
  autocmd.create(
    { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    function()
      M.close(opts.on_close)
    end,
    {
      group = _augroup,
      once = true,
      desc = "[markdown.nvim] hover: dismiss on the next cursor move or mode change",
    }
  )

  return win, buf
end

--- The window handle of the open hover, or nil.
---@return integer|nil
function M.win()
  return M.is_open() and _win or nil
end

return M
