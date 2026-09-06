---@module 'lib.nvim.image_preview'
---@brief In-Neovim image preview via images.nvim, snacks.nvim or image.nvim (soft deps).
---@description
--- All three are optional. `detect()` reports which one is installed, and
--- `preview()` renders a file into a floating window using it. Neither is
--- required: with no provider installed the image handler keeps its previous
--- behaviour of shelling out to the system viewer, with no prompt.
---
--- images.nvim is checked first and preferred when several are installed:
--- snacks.nvim and image.nvim both speak only the Kitty graphics protocol,
--- which native Windows Neovim in WezTerm never draws when it comes from
--- Neovim itself (see images.nvim's README, "Why not snacks.image or
--- image.nvim") — so on that setup both are silently non-functional here.
--- images.nvim draws via OSC 1337 instead, which does work there.
---
--- The three providers need different treatment:
---
---   images.nvim  — no buffer hook either; `images.browse.draw_in_window`
---                  (public, already used by images.nvim's own `:Image
---                  pickers` for exactly the same "draw into an arbitrary
---                  already-open window" need) targets the float's geometry
---                  directly. Cleared via `images.terminal.clear()` on close.
---   snacks.nvim  — `Snacks.image` hooks buffer loading for image files, so
---                  the float only has to `:edit` the path and snacks renders
---                  it. Nothing to place or clean up by hand.
---   image.nvim   — has no buffer hook; an image object is built from the
---                  file and rendered into the float's window explicitly, and
---                  must be cleared when that window closes.

local M = {}

---@alias Lib.ImagePreview.Provider "images.nvim"|"snacks"|"image.nvim"

---Which in-Neovim preview provider is available, if any.
---
---images.nvim is preferred when several are installed: it is the only one of
---the three that draws anything on native Windows Neovim in WezTerm (see
---module doc above) — snacks/image.nvim are kept as the fallback for setups
---where they do work (Kitty-capable terminals).
---@return Lib.ImagePreview.Provider|nil
function M.detect()
  local ok_images, images = pcall(require, "images")
  if ok_images and type(images) == "table" and images.show then
    return "images.nvim"
  end

  local ok_snacks, snacks = pcall(require, "snacks")
  if ok_snacks and type(snacks) == "table" and snacks.image then
    return "snacks"
  end

  local ok_image = pcall(require, "image")
  if ok_image then
    return "image.nvim"
  end

  return nil
end

---Whether an in-Neovim preview is possible at all.
---@return boolean
function M.available()
  return M.detect() ~= nil
end

---Float geometry: a centred window at 80% of the editor, clamped so a very
---large or very small editor still yields something usable.
---@return table win_opts
local function float_opts()
  local width = math.max(20, math.floor(vim.o.columns * 0.8))
  local height = math.max(10, math.floor(vim.o.lines * 0.8))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
  }
end

---Close `win` (and its buffer) on q/<Esc>, and run `on_close` when it goes.
---@param buf integer
---@param win integer
---@param on_close fun()|nil
local function wire_close(buf, win, on_close)
  local function close()
    if on_close then
      pcall(on_close)
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, close, { buffer = buf, nowait = true, silent = true })
  end

  -- Also covers the window being closed some other way (:q, <C-w>c), so an
  -- image.nvim placement is never left rendered over an unrelated buffer.
  require("lib.nvim.bindings.autocmd").create("WinClosed", function()
    if on_close then
      pcall(on_close)
    end
  end, {
    group = "lib_nvim_image_preview",
    pattern = tostring(win),
    once = true,
    desc = "lib.nvim.image_preview: clear the placement when its window closes",
  })
end

---Preview `path` in a floating window.
---@param path string  Absolute path to an image file
---@return boolean ok
---@return string|nil err
function M.preview(path)
  local provider = M.detect()
  if not provider then
    return false, "no image preview provider installed (images.nvim, snacks.nvim or image.nvim)"
  end

  if provider == "images.nvim" then
    local ok_guard, guard = pcall(require, "images.guard")
    if ok_guard then
      pcall(guard.check)
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, float_opts())

    local ok, browse = pcall(require, "images.browse")
    local drawn = ok and browse.draw_in_window(path, win)
    if not drawn then
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      return false, "images.nvim could not draw " .. path
    end

    wire_close(buf, win, function()
      pcall(function()
        require("images.terminal").clear()
      end)
    end)
    return true
  end

  if provider == "snacks" then
    -- Snacks renders image files through its own buffer hook, so opening the
    -- path in the float is all that is needed.
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, float_opts())
    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if not ok then
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      return false, tostring(err)
    end
    -- :edit replaced the scratch buffer with the file's own.
    wire_close(vim.api.nvim_win_get_buf(win), win, nil)
    return true
  end

  -- image.nvim: build and render explicitly, then clear on close.
  local image = require("image")
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, float_opts())

  local ok, img = pcall(image.from_file, path, {
    window = win,
    buffer = buf,
    with_virtual_padding = true,
  })

  if not ok or not img then
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    return false, ("image.nvim could not load %s: %s"):format(path, tostring(img))
  end

  local ok_render, render_err = pcall(function()
    img:render()
  end)
  if not ok_render then
    pcall(function()
      img:clear()
    end)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    return false, tostring(render_err)
  end

  wire_close(buf, win, function()
    img:clear()
  end)
  return true
end

return M
