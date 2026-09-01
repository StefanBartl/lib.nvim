---@module 'lib.nvim.hover.classify'
---@brief Decide what kind of thing a link target points at.
---@description
--- Pure classification: target string (+ the document it was found in) in,
--- a `Lib.Hover.Target` out. No I/O beyond a single `uv.fs_stat` to tell
--- "exists" from "missing", and no preview work — that is
--- `lib.nvim.hover.preview`'s job.
---
--- Ordering matters: anchors and URLs are decided by *shape* before
--- anything touches the filesystem, so a `#heading` or an `https://` target
--- never produces a stat call.

local M = {}

local uv = vim.uv or vim.loop

--- Extensions that get a picture-shaped preview. Kept in sync with
--- `markdown.handler.image`'s own notion of "this is an image" by intent;
--- deliberately a superset (an `.avif` hover is harmless even where the
--- opener would not special-case it).
local IMAGE_EXT = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  bmp = true,
  ico = true,
  avif = true,
  svg = true,
}

local MARKDOWN_EXT = { md = true, markdown = true, mdx = true }

---@internal
---@param path string
---@return string|nil
local function extension(path)
  local ext = path:match("%.([%w]+)$")
  return ext and ext:lower() or nil
end

---@internal
--- Resolve `target` against the directory of `source_path`. An absolute
--- target is returned normalized; a relative one is joined onto the
--- document's own directory, which is what a markdown link means — not the
--- editor's cwd, which is where a naive `fnamemodify(":p")` would put it.
---@param target string
---@param source_path string|nil
---@return string
local function resolve_path(target, source_path)
  local expanded = vim.fn.expand(target)
  if expanded:match("^/") or expanded:match("^%a:[\\/]") or expanded:match("^[\\/][\\/]") then
    return vim.fs.normalize(expanded)
  end
  local base = source_path and source_path ~= "" and vim.fs.dirname(source_path) or vim.fn.getcwd()
  return vim.fs.normalize(base .. "/" .. expanded)
end

---@internal
--- Repair a URL written with Windows separators.
---
--- `http:\\example.com` is what a Windows keyboard produces when the habit
--- wins, and it is still perfectly clear what was meant. Normalizing it here
--- rather than in the preview means everything downstream — the split for
--- display, the `^https?://` test that decides fetchability — sees one shape
--- and not two.
---@param url string
---@return string
local function normalize_url(url)
  -- Only a *backslash* separator is repaired, and only when there is one:
  -- `mailto:someone@example.com` has no separator at all and must not grow a
  -- `//`, and a correctly written `http://` needs no help.
  local scheme, rest = url:match("^(%a[%w+.-]*):\\+(.*)$")
  if scheme then
    return scheme .. "://" .. rest
  end
  return url
end

--- Classify a link target.
---@param target string Raw target as `link_scan` reported it.
---@param source_path string|nil Absolute path of the document the link lives in.
---@return Lib.Hover.Target
function M.classify(target, source_path)
  local raw = vim.trim(target or "")

  if raw == "" then
    return { type = "missing", raw = raw, reason = "empty target" }
  end

  -- In-page anchor: `#heading`. Decided on shape, before any filesystem call.
  if raw:sub(1, 1) == "#" then
    return { type = "anchor", raw = raw, anchor = raw:sub(2) }
  end

  -- A scheme means it is a URL, full stop -- including mailto: and friends,
  -- which get classified but not fetched (see preview/url.lua).
  if raw:match("^%a[%w+.-]*:") and not raw:match("^%a:[\\/]") then
    return { type = "url", raw = raw, url = normalize_url(raw) }
  end
  if raw:match("^//") then
    return { type = "url", raw = raw, url = "https:" .. raw }
  end
  -- `www.example.com` with the scheme left off: a host, written as a host,
  -- and never a relative path that happens to exist. Assumed https, which is
  -- what a browser's address bar would do with it too.
  if raw:match("^www%.[%w%-]") then
    return { type = "url", raw = raw, url = "https://" .. raw }
  end

  -- Local path, possibly with a trailing #anchor.
  local path_part, anchor = raw:match("^(.-)#(.*)$")
  path_part = path_part or raw
  if path_part == "" then
    path_part = raw
  end

  local abs = resolve_path(path_part, source_path)
  local stat = uv.fs_stat(abs)

  if not stat then
    return {
      type = "missing",
      raw = raw,
      path = abs,
      anchor = anchor,
      reason = "no such file",
    }
  end

  if stat.type == "directory" then
    return { type = "directory", raw = raw, path = abs, size = stat.size }
  end

  local ext = extension(abs)
  local kind = "file"
  if ext and IMAGE_EXT[ext] then
    kind = "image"
  elseif ext == "pdf" then
    kind = "pdf"
  elseif ext and MARKDOWN_EXT[ext] then
    kind = "markdown"
  elseif require("lib.nvim.hover.formats").is_office(ext) then
    -- Its own type rather than "some binary file", because it is the one
    -- group with a second answer available: LibreOffice can turn it into a
    -- PDF, and a PDF is something this hover can actually show. Everything
    -- else that cannot be read as text is caught by the byte test in
    -- `preview.binary`, which needs no extension to be listed anywhere.
    kind = "office"
  end

  return {
    type = kind,
    raw = raw,
    path = abs,
    anchor = anchor,
    size = stat.size,
    ext = ext,
  }
end

--- Whether `ext` is one this module considers an image.
---@param ext string|nil
---@return boolean
function M.is_image_ext(ext)
  return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

return M
