---@module 'lib.nvim.hover.preview.media'
---@brief Image and PDF hover previews.
---@description
--- Both aim at the same result: a blank float in the picture's own aspect
--- ratio, holding nothing but the picture. A filename in the border and a
--- "PNG · 10 KB" line describe something the reader is already looking at,
--- and the float's geometry is not decoration either — it *is* the drawing
--- box handed to the terminal, so a float measured against text deforms the
--- image inside it.
---
--- Metadata is the fallback, not the default: it appears where the picture
--- cannot be drawn at all (no provider, `inline_images = false`, a failed
--- render), and there it is the only thing the hover can say.
---
--- Neither previewer reimplements anything: image drawing goes through
--- `lib.nvim.image_preview`'s provider detection (images.nvim / snacks
--- / image.nvim), and a PDF page becomes a PNG via `pdfport.render_page`,
--- whose own docs name exactly this use case ("lets consumers like
--- images.nvim show a PDF page as an image").

local M = {}

---@internal
---@param n integer|nil
---@return string
local function human_size(n)
  if not n then
    return "?"
  end
  local ok, fmt = pcall(require, "lib.lua.strings.format")
  if ok and fmt and fmt.format_bytes then
    return fmt.format_bytes(n)
  end
  return tostring(n) .. " B"
end

---@internal
--- JPEG dimensions. Unlike PNG/GIF/BMP there is no fixed offset: the size
--- lives in a start-of-frame segment somewhere behind a variable-length run
--- of metadata (an EXIF thumbnail from a phone camera is routinely tens of
--- kilobytes), so the segment chain has to be walked. `f` must be positioned
--- just after the two-byte SOI.
---@param f file*
---@return integer|nil width
---@return integer|nil height
local function jpeg_dimensions(f)
  for _ = 1, 256 do -- bounded: a malformed file must not spin here
    local marker = f:read(2)
    if not marker or #marker < 2 then
      return nil, nil
    end
    local lead, code = marker:byte(1, 2)
    if lead ~= 0xFF then
      return nil, nil
    end

    -- 0xFF doubles as segment padding; skip any run of them.
    while code == 0xFF do
      local nxt = f:read(1)
      if not nxt then
        return nil, nil
      end
      code = nxt:byte(1)
    end

    -- Standalone markers (TEM, RSTn) carry no length field.
    if not (code == 0x01 or (code >= 0xD0 and code <= 0xD7)) then
      local len_bytes = f:read(2)
      if not len_bytes or #len_bytes < 2 then
        return nil, nil
      end
      local len = len_bytes:byte(1) * 256 + len_bytes:byte(2)
      if len < 2 then
        return nil, nil
      end

      -- SOF0..SOF15 carry the frame header, except 0xC4/0xC8/0xCC, which are
      -- Huffman/arithmetic tables that happen to sit in the same range.
      local is_sof = code >= 0xC0
        and code <= 0xCF
        and code ~= 0xC4
        and code ~= 0xC8
        and code ~= 0xCC
      if is_sof then
        local body = f:read(5) -- precision, height (2 bytes), width (2 bytes)
        if not body or #body < 5 then
          return nil, nil
        end
        return body:byte(4) * 256 + body:byte(5), body:byte(2) * 256 + body:byte(3)
      end

      if not f:seek("cur", len - 2) then
        return nil, nil
      end
    end
  end
  return nil, nil
end

---@internal
--- Image dimensions without a decoder: parse just enough header bytes for
--- the common formats. Returns nil for anything else (SVG, WebP, AVIF, …)
--- rather than guessing; `pixel_size` falls back to ImageMagick there.
---@param path string
---@return integer|nil width
---@return integer|nil height
local function dimensions(path)
  local f = io.open(path, "rb")
  if not f then
    return nil, nil
  end
  local head = f:read(32) or ""
  if #head < 24 then
    f:close()
    return nil, nil
  end

  local byte = string.byte

  -- PNG: 8-byte signature, then IHDR with big-endian width/height at 16..23.
  if head:sub(1, 8) == "\137PNG\r\n\26\n" then
    f:close()
    local function be32(offset)
      return byte(head, offset) * 0x1000000
        + byte(head, offset + 1) * 0x10000
        + byte(head, offset + 2) * 0x100
        + byte(head, offset + 3)
    end
    return be32(17), be32(21)
  end

  -- GIF: "GIF87a"/"GIF89a", then little-endian width/height.
  if head:sub(1, 3) == "GIF" then
    f:close()
    return byte(head, 7) + byte(head, 8) * 256, byte(head, 9) + byte(head, 10) * 256
  end

  -- BMP: "BM", little-endian width/height at 18..25.
  if head:sub(1, 2) == "BM" then
    f:close()
    local function le32(offset)
      return byte(head, offset)
        + byte(head, offset + 1) * 0x100
        + byte(head, offset + 2) * 0x10000
        + byte(head, offset + 3) * 0x1000000
    end
    return le32(19), le32(23)
  end

  -- JPEG: SOI, then a segment chain.
  if byte(head, 1) == 0xFF and byte(head, 2) == 0xD8 then
    f:seek("set", 2)
    local w, h = jpeg_dimensions(f)
    f:close()
    return w, h
  end

  f:close()
  return nil, nil
end

---@internal
--- Pixel size of an image: header parse first, ImageMagick only as fallback.
--- That order is deliberate. The parse above is a handful of reads and covers
--- the formats a markdown document actually links, while `images.info` shells
--- out — worth it for a WebP or SVG the parser cannot read, not worth it for
--- every PNG.
---@param path string
---@return Images.Scale.Dims|nil
local function pixel_size(path)
  local w, h = dimensions(path)
  if w and h and w > 0 and h > 0 then
    return { width = w, height = h }
  end

  local ok, info = pcall(require, "images.info")
  if ok and type(info.collect) == "function" then
    local px = info.collect(path)
    if px and px.width and px.height and px.width > 0 and px.height > 0 then
      return { width = px.width, height = px.height }
    end
  end
  return nil
end

---@internal
--- Fit `image_px` into the hover's maximum box, in cells. Prefers
--- `images.scale.fit_cells` — the same function `images.zen` and
--- `images.redact` size their windows with, so a hover, a zen window and a
--- redaction box all letterbox identically. The local fallback covers an
--- images.nvim too old to have it.
---@param image_px Images.Scale.Dims|nil
---@param opts Lib.Hover.PreviewOpts
---@return integer cols
---@return integer rows
local function canvas_cells(image_px, opts)
  local max_cols = math.max(10, math.min(opts.max_width or 80, math.max(10, vim.o.columns - 4)))
  local max_rows = math.max(3, math.min(opts.max_lines or 20, math.max(3, vim.o.lines - 4)))

  -- The frame is not the drawing box. `images.anchor` keeps `draw_inset`
  -- cells free on every side, so a float sized to fit the image exactly is
  -- then drawn into a box two cells smaller on each axis — and two cells off
  -- 20 rows is a bigger relative change than two off 77 columns. The ratio
  -- shifts, `preserveAspectRatio=1` letterboxes what no longer fits, and the
  -- terminal centres the remainder: measured at ~2.7 cells of empty space on
  -- the left for a 1200x675 image in a 77x20 frame. That reads as "the image
  -- is shifted right" and was chased as a placement bug for a long time.
  --
  -- So fit the image to the box it will actually be drawn in, then add the
  -- inset back for the frame. The float ends up slightly larger and the
  -- picture fills it edge to edge.
  local inset = 0
  do
    local ok_cfg, images_cfg = pcall(require, "images.config")
    if ok_cfg then
      local configured = (images_cfg.get().display or {}).draw_inset
      if type(configured) == "number" and configured > 0 then
        inset = math.floor(configured)
      end
    end
  end

  local ok, scale = pcall(require, "images.scale")
  if ok and type(scale.fit_cells) == "function" then
    -- Never let the inset eat the box: on a very small frame keep at least
    -- one cell to fit into, and drop the inset instead.
    local inner_cols = max_cols - 2 * inset
    local inner_rows = max_rows - 2 * inset
    if inner_cols < 1 or inner_rows < 1 then
      inset, inner_cols, inner_rows = 0, max_cols, max_rows
    end

    local cols, rows = scale.fit_cells(inner_cols, inner_rows, image_px)
    return math.min(cols + 2 * inset, max_cols), math.min(rows + 2 * inset, max_rows)
  end

  if not image_px then
    return max_cols, max_rows
  end
  -- A terminal cell is roughly twice as tall as it is wide — the same 0.5
  -- assumption images.scale documents.
  local aspect = image_px.width / image_px.height
  local cols = math.floor(max_rows * aspect / 0.5)
  if cols <= max_cols then
    return math.max(1, cols), max_rows
  end
  return max_cols, math.max(1, math.floor(max_cols * 0.5 / aspect))
end

--- A drawable file as hover content: a blank float in the file's own aspect
--- ratio, plus the path to draw into it. Public because a rasterized PDF page
--- is exactly this once it exists — a PNG that wants a correctly shaped
--- frame and has nothing to say about itself.
---@param path string
---@param opts Lib.Hover.PreviewOpts
---@return Lib.Hover.Content
function M.canvas_for(path, opts)
  local cols, rows = canvas_cells(pixel_size(path), opts)
  return { lines = {}, canvas = { cols = cols, rows = rows }, image_path = path }
end

--- Draw `png_path` into an already-open hover window, if a provider can.
--- Returns a teardown function to run when the hover closes, or nil when
--- no provider could draw at all.
---
--- The draw is deferred by one tick (`images.anchor`'s `defer` option), and
--- that is the whole reason this goes through `images.anchor` rather than
--- `images.browse.draw_in_window`: the hover float is opened in the *same*
--- tick this runs in. `nvim_ui_send` puts the image on the terminal at once,
--- but Neovim repaints everything that turned dirty since the last return to
--- its main loop — including the cells of the float that was just created —
--- and paints straight over it. Float there, image gone. `browse
--- .draw_in_window` never needed the defer (its snacks picker window has
--- stood for a while by then), so it draws immediately and is the wrong
--- primitive here.
---
--- Because the draw happens later, whether it succeeded is not known when
--- this returns; the teardown is registered on the strength of the provider
--- being present, and clearing when nothing was drawn is a no-op anyway.
---@param png_path string
---@param win integer
---@return (fun())|nil on_close
function M.draw_into(png_path, win)
  local provider = require("lib.nvim.image_preview").detect()
  if provider ~= "images.nvim" then
    -- Only images.nvim can draw into an arbitrary existing window;
    -- snacks/image.nvim need a buffer they own, which a borrowed hover
    -- window is not.
    return nil
  end

  local ok_anchor, anchor = pcall(require, "images.anchor")
  if ok_anchor and type(anchor.draw) == "function" then
    pcall(anchor.draw, win, "full", png_path, { defer = true })
  else
    -- images.nvim without `images.anchor`: fall back to the older public
    -- entry point, undeferred — worse, but better than no image.
    local ok, browse = pcall(require, "images.browse")
    if not ok or type(browse.draw_in_window) ~= "function" then
      return nil
    end
    local drawn = false
    pcall(function()
      drawn = browse.draw_in_window(png_path, win)
    end)
    if not drawn then
      return nil
    end
  end

  return function()
    pcall(function()
      require("images.terminal").clear()
    end)
  end
end

--- Image preview.
---
--- Two shapes, depending on whether the picture can actually be drawn:
---
--- * **Drawable** — a blank float sized to the image's aspect ratio, and
---   nothing else. No filename in the border, no dimension or size line: the
---   reader is looking at the picture, and a caption for it is noise. The
---   sizing is not only cosmetic — the drawing box handed to the terminal
---   *is* the float's geometry, so a float measured against two lines of text
---   squeezes the image into a box two cells tall.
--- * **Not drawable** (no provider, or `inline_images = false`) — the
---   metadata lines, which are then the only thing the hover can say at all.
---@param target Lib.Hover.Target
---@param opts Lib.Hover.PreviewOpts
---@return Lib.Hover.Content
function M.image(target, opts)
  local provider = require("lib.nvim.image_preview").detect()

  if provider and opts.inline_images ~= false then
    return M.canvas_for(target.path, opts)
  end

  local lines = {}
  local w, h = dimensions(target.path)
  if w and h then
    lines[#lines + 1] = ("%d × %d px"):format(w, h)
  end
  lines[#lines + 1] = ("%s · %s"):format((target.ext or "image"):upper(), human_size(target.size))
  if not provider then
    lines[#lines + 1] = "(no image provider installed)"
  end

  return { lines = lines, title = vim.fs.basename(target.path) }
end

---@internal
--- Rasterized pages, keyed by file *and* mtime: a PDF that changed on disk
--- must not answer with the old page. The PNGs outlive the float they were
--- drawn into — that is the whole point, a second hover over the same PDF
--- should not shell out to pdftoppm again — so they are cleaned up once at
--- exit rather than per close.
---@type table<string, string>
local _pages = {}
local _cleanup_hooked = false

---@internal
---@param path string
---@return string|nil
local function page_key(path)
  local st = vim.uv.fs_stat(path)
  if not st then
    return nil
  end
  return path .. " " .. tostring(st.mtime and st.mtime.sec or 0)
end

---@internal
---@param key string
---@param png string
local function remember_page(key, png)
  if not _cleanup_hooked then
    _cleanup_hooked = true
    require("lib.nvim.bindings.autocmd").create("VimLeavePre", function()
      for _, file in pairs(_pages) do
        pcall(os.remove, file)
      end
      _pages = {}
    end, {
      group = "MarkdownNvimHoverMedia",
      desc = "markdown.nvim: delete rasterized PDF hover pages",
    })
  end

  local previous = _pages[key]
  if previous and previous ~= png then
    pcall(os.remove, previous)
  end
  _pages[key] = png
end

--- PDF preview.
---
--- Same destination as an image hover — a blank float in the page's aspect
--- ratio — reached in up to three steps, because the page does not exist yet.
---
--- 1. **Already rasterized** (same file, same mtime): returns the finished
---    content synchronously. Nothing pops, because nothing has to wait.
--- 2. **Not yet**: `pdfport.render_page` shells out to pdftoppm and the
---    return value is a *provisional* metadata float marked `pending`. Whether
---    it is ever shown is the caller's decision — `lib.nvim.hover` holds it
---    back for a grace period, so a fast render never flashes it.
--- 3. **Rendered**: `on_result` receives the real content, and the page is
---    kept for the next hover.
---
--- The rendered PNG is owned by this module from here on. Callers must not
--- delete it — an earlier version did, which is why every hover re-rendered.
---@param target Lib.Hover.Target
---@param opts Lib.Hover.PreviewOpts
---@param on_result fun(content: Lib.Hover.Content): nil
---@return Lib.Hover.Content
function M.pdf(target, opts, on_result)
  local function metadata(extra)
    local lines = { ("PDF · %s"):format(human_size(target.size)) }
    if extra then
      lines[#lines + 1] = extra
    end
    return { lines = lines, title = vim.fs.basename(target.path) }
  end

  local ok_pdfport, pdfport = pcall(require, "pdfport")
  if not ok_pdfport or type(pdfport.render_page) ~= "function" then
    return metadata("(pdfport.nvim not installed — no page preview)")
  end

  if opts.inline_images == false then
    return metadata()
  end

  local provider = require("lib.nvim.image_preview").detect()
  if not provider then
    return metadata("(no image provider installed)")
  end

  local page = math.max(1, math.floor(opts.page or 1))
  local key = page_key(target.path, page)
  local cached = key and _pages[key]
  -- `fs_stat`: a temp sweeper may have taken the file since. Then it is not a
  -- cache entry any more, it is a dangling path.
  if cached and vim.uv.fs_stat(cached) then
    local content = M.canvas_for(cached, opts)
    content.scroll = { page = page, step = 1, more = true }
    -- Page 1 stays untitled, as every image preview does: a filename over a
    -- picture the reader is already looking at is noise. From page 2 on the
    -- number is the one thing the picture cannot say about itself.
    if page > 1 then
      content.title = ("p%d"):format(page)
    end
    return content
  end
  if cached then
    _pages[key] = nil
  end

  pdfport.render_page(target.path, page, nil, function(png_path, err)
    -- pdftoppm's exit lands in a fast event context, where neither
    -- `nvim_create_autocmd` nor the ImageMagick fallback's `vim.system():wait()`
    -- may be called. Everything downstream of here runs on the main loop.
    vim.schedule(function()
      if not png_path then
        -- A failed render past page 1 is almost always "there is no such
        -- page", which is how the page count is discovered: pdfport reports
        -- no total, so paging walks until it stops. Reported as an end rather
        -- than an error so the caller can step back instead of showing a
        -- failure for a document it has simply reached the end of.
        if page > 1 then
          on_result(vim.tbl_extend("force", metadata(("(no page %d)"):format(page)), {
            scroll = { page = page, step = 1, more = false, past_end = true },
          }))
        else
          on_result(metadata("(page render failed: " .. (err or "unknown error") .. ")"))
        end
        return
      end
      if key then
        remember_page(key, png_path)
      end
      local content = M.canvas_for(png_path, opts)
      content.scroll = { page = page, step = 1, more = true }
      if page > 1 then
        content.title = ("p%d"):format(page)
      end
      on_result(content)
    end)
  end)

  return vim.tbl_extend(
    "force",
    metadata(("rendering page %d…"):format(page)),
    { pending = true }
  )
end

return M
