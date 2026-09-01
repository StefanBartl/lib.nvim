---@module 'lib.nvim.hover.preview.binary'
---@brief The honest answer for a file whose bytes are not text.
---@description
--- **The symptom this exists for.** Hovering a `.docx` opened a float full of
--- mojibake — the first twenty lines of a ZIP container, with the document's
--- name in the border, as if that were a preview of it. Every binary format
--- did the same, because the file preview reads lines and a binary file has
--- "lines" in the sense that it contains newline bytes.
---
--- **Why a byte test and not a list of extensions.** A list answers for the
--- formats someone thought of; the case that produced the bug is the one
--- nobody listed. So the test is `is_binary`: read the head of the file and
--- decide from the bytes. `lib.nvim.hover.formats` is consulted only for a
--- better *word* than "binary file" once the decision is already made.
---
--- What comes back is deliberately three lines at most. There is nothing to
--- read here, and a float that says so should be small enough to be taken in
--- at a glance and dismissed.

local M = {}

--- How many bytes of the head decide it. Enough to carry every container
--- signature worth recognizing, small enough that the read costs nothing on a
--- 300 MB file.
local SAMPLE_BYTES = 4096

--- Share of control characters above which text stops being a plausible
--- reading. UTF-8 prose contains none of them beyond tab/newline/CR/FF, so
--- anything past a few percent is a container that happens to have no NUL in
--- its first page.
local CONTROL_RATIO = 0.1

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

--- Whether `path` holds bytes that would be nonsense as text.
---
--- Two tests, in the order they are cheap:
---
---  * **A NUL byte.** No text encoding Neovim would display uses one, and
---    every container format has them in quantity. This alone catches
---    docx/xlsx/pptx, PDFs, images, executables and archives.
---  * **Too many other control characters.** The fallback for a head that
---    happens to be NUL-free — a compressed stream can run a page without
---    one — measured against `CONTROL_RATIO`.
---
--- An empty or unreadable file is *not* binary: there is nothing to
--- misinterpret, and the file preview already has a sentence for it.
---@param path string
---@return boolean
function M.is_binary(path)
  local f = io.open(path, "rb")
  if not f then
    return false
  end
  local chunk = f:read(SAMPLE_BYTES)
  f:close()

  if type(chunk) ~= "string" or chunk == "" then
    return false
  end
  if chunk:find("\0", 1, true) then
    return true
  end

  local control = 0
  for i = 1, #chunk do
    local b = chunk:byte(i)
    -- Tab, LF, VT, FF, CR are text; everything else below 0x20 is not.
    if b < 32 and not (b >= 9 and b <= 13) then
      control = control + 1
    end
  end
  return (control / #chunk) > CONTROL_RATIO
end

--- The badge: what the file is, how big, and — when the caller has one — a
--- line saying what could still be done about it.
---
--- The `note` is how the office preview offers its own escape hatch
--- ("`:Lib hover office on`") without this module knowing that feature
--- exists.
---@param target Lib.Hover.Target
---@param opts? { note?: string, label?: string }
---@return Lib.Hover.Content
function M.badge(target, opts)
  opts = opts or {}
  local label = opts.label or require("lib.nvim.hover.formats").label(target.ext) or "binary file"

  local lines = { "◆ " .. label }
  lines[#lines + 1] = ("%s · %s"):format((target.ext or "?"):upper(), human_size(target.size))
  if opts.note and opts.note ~= "" then
    lines[#lines + 1] = opts.note
  end

  return {
    lines = lines,
    title = target.path and vim.fs.basename(target.path) or nil,
    -- Not an error — the file is fine, it simply cannot be read as text — so
    -- a hint colour rather than the red the `missing` marker gets.
    highlight = "LibHoverInfo",
  }
end

return M
