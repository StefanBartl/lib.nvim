---@module 'lib.nvim.hover.preview.text'
---@brief Previews that are just "some lines of a file": plain files,
---directories, and the "it is not there" case.
---@description
--- All synchronous — these read at most `max_lines` lines and never touch
--- the network. Reading is capped by line count rather than by file size, so
--- a 300 MB log with one very long line costs the same as a short one.
---
--- Section previews (`#anchor`, and a markdown file with a fragment) are
--- deliberately absent: resolving a heading means GFM slugging and heading
--- parsing, which is markdown knowledge. `markdown.nvim` contributes those
--- through `lib.nvim.hover.registry`, which is also why nothing in this file
--- requires it.

local M = {}

---@internal
--- Read at most `limit` lines from `path`. Uses `io.lines` rather than
--- `fs.read` + split so a huge file is not slurped into memory just to show
--- its first 20 lines.
---@param path string
---@param limit integer
---@return string[] lines
---@return boolean truncated
local function head(path, limit)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return out, false
  end
  local truncated = false
  for line in f:lines() do
    if #out >= limit then
      truncated = true
      break
    end
    -- Strip a CR left by a CRLF file so the float does not render `^M`.
    out[#out + 1] = (line:gsub("\r$", ""))
  end
  f:close()
  return out, truncated
end

---@internal
---@param n integer
---@return string
local function human_size(n)
  local ok, strings = pcall(require, "lib.lua.strings.format")
  if ok and strings and strings.format_bytes then
    return strings.format_bytes(n)
  end
  return tostring(n) .. " B"
end

--- Preview a markdown or plain-text file.
---@param target Lib.Hover.Target
---@param opts Lib.Hover.PreviewOpts
---@return Lib.Hover.Content
function M.file(target, opts)
  local limit = opts.max_lines or 20
  local lines, truncated = head(target.path, limit)

  if #lines == 0 then
    return {
      lines = { ("(empty file, %s)"):format(human_size(target.size or 0)) },
      title = vim.fs.basename(target.path),
    }
  end

  if truncated then
    lines[#lines + 1] = "…"
  end

  return {
    lines = lines,
    -- Markdown gets its own filetype so the float renders headings/emphasis
    -- with the user's markdown highlighting; anything else is left plain
    -- rather than guessed, since a wrong ftplugin can be slow or noisy.
    filetype = target.type == "markdown" and "markdown" or nil,
    title = vim.fs.basename(target.path),
  }
end

--- Preview a directory: its entries, directories first.
---@param target Lib.Hover.Target
---@param opts Lib.Hover.PreviewOpts
---@return Lib.Hover.Content
function M.directory(target, opts)
  local limit = opts.max_lines or 20
  local uv = vim.uv or vim.loop

  local handle = uv.fs_scandir(target.path)
  if not handle then
    return { lines = { "(cannot read directory)" }, title = vim.fs.basename(target.path) }
  end

  local dirs, files = {}, {}
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if kind == "directory" then
      dirs[#dirs + 1] = name .. "/"
    else
      files[#files + 1] = name
    end
  end
  table.sort(dirs)
  table.sort(files)

  local out = {}
  for _, entry in ipairs(dirs) do
    out[#out + 1] = entry
  end
  for _, entry in ipairs(files) do
    out[#out + 1] = entry
  end

  local total = #out
  if total == 0 then
    out = { "(empty directory)" }
  end
  if #out > limit then
    out = vim.list_slice(out, 1, limit)
    out[#out + 1] = ("… (%d entries)"):format(total)
  end

  return { lines = out, title = vim.fs.basename(target.path) .. "/" }
end

--- Preview for a target that does not exist.
---
--- Marked with a red ✗ rather than stated in prose alone: this is the one
--- preview whose whole content is "the thing you are pointing at is not
--- there", and a glance has to carry that. The symbol is highlighted through
--- `LibHoverMissing` (linked to `DiagnosticError` by default, so it
--- follows the colorscheme instead of hard-coding a red).
---
--- The path is shown on its own line because it is the actionable half: what
--- was *tried* is what tells you whether the link is wrong or the file moved.
---@param target Lib.Hover.Target
---@return Lib.Hover.Content
function M.missing(target)
  local lines = { "✗ " .. (target.reason or "target does not exist") }
  if target.path then
    lines[#lines + 1] = target.path
  end
  return { lines = lines, title = "broken link", highlight = "LibHoverMissing" }
end

return M
