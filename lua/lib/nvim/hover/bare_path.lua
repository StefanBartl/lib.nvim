---@module 'lib.nvim.hover.bare_path'
---@brief Find a filesystem path under the cursor that is not written as a link.
---@description
--- `lib.nvim.hover` answers "what does the link under the cursor point at".
--- This module answers the same question for text that carries no link syntax
--- at all — a path sitting in prose, in a code comment, in a `:messages` dump:
---
---     ./assets/pdf_inline_hover.png
---     ../docs/BINDINGS.md
---     ...AppData/Local/nvim/init.lua:42
---
--- Everything downstream is unchanged: the raw string produced here goes into
--- `lib.nvim.hover.classify` exactly like a link target would, so a bare path
--- gets the same image / PDF / markdown-section / file-head / directory
--- preview a linked one already gets. This module only widens *what counts as
--- a target*, never what a target can look like once found.
---
--- **Why gopath.nvim rather than `<cfile>` alone.** `<cfile>` reads a token
--- off the line under the cursor and stops there. gopath.nvim resolves the
--- awkward cases that a log or an error message actually produces: a
--- truncated path (`...nvim/init.lua`, `…/lua/config/init.lua`), a `:line:col`
--- suffix, a path only findable through `&path`/`rtp`/a tail search. That is
--- precisely the "a path in `:messages`, truncated or not, should hover too"
--- case, and it is gopath's whole subject matter — reimplementing any of it
--- here would be duplicating a sibling plugin for no gain. Soft dependency:
--- without gopath.nvim the `<cfile>` path below still covers ordinary
--- relative and absolute paths.
---
--- **Why existence is required.** A link is an explicit statement that
--- something is there, so `classify` reporting `missing` for a broken link is
--- useful. Bare text is not: every ordinary word under the cursor would
--- otherwise open a float saying "this target does not exist". So a bare path
--- must resolve to something real, or it is not a target at all.

local M = {}

local api = vim.api

---@internal
--- Whether `str` is shaped like a path rather than an ordinary word.
---
--- Deliberately stricter than gopath's own heuristic: this runs on every
--- CursorHold in every buffer, so a plain word ("the", "config", "return")
--- must be rejected before any filesystem call. A separator or an extension
--- is the cheapest evidence that text was meant as a path.
---@param str string
---@return boolean
local function looks_like_path(str)
  if type(str) ~= "string" or str == "" then
    return false
  end
  if #str > 512 then
    return false
  end

  if str:match("[/\\]") then
    return true
  end -- a/b, ./a, C:\a
  if str:match("^%.%.%.") or str:match("^…") then
    return true
  end -- truncated
  if str:match("%.[%w]+$") then
    return true
  end -- README.md
  if str:match("%.[%w]+:%d+") then
    return true
  end -- init.lua:42
  return false
end

---@internal
--- Whether `str` can *only* have been meant as a path.
---
--- The distinction that decides whether a **non-existent** target is worth
--- reporting. `looks_like_path` accepts a bare `name.ext` because `README.md`
--- in prose is a path — but so is `vim.api`, `string.format` or any Lua
--- module name, and those are the overwhelming majority of what a code buffer
--- puts under the cursor. Reporting those as broken paths would put a red ✗
--- on half the identifiers in every Lua file.
---
--- A separator or a `...` truncation is different: no identifier is spelled
--- `docs/setup.md` or `...nvim/init.lua`. Those were meant as paths, so if
--- they do not resolve, saying so is the useful answer rather than noise.
---@param str string
---@return boolean
local function is_unambiguous_path(str)
  if type(str) ~= "string" or str == "" then
    return false
  end
  return str:match("[/\\]") ~= nil or str:match("^%.%.%.") ~= nil or str:match("^…") ~= nil
end

---@internal
--- Strip what surrounds a path in real prose but is not part of it: quotes,
--- markdown emphasis, brackets, and trailing sentence punctuation. A path at
--- the end of a sentence ("see ./docs/a.md.") must not lose its match to the
--- full stop, but `a.md` must keep its extension.
---@param str string
---@return string
local function trim_delimiters(str)
  local out = vim.trim(str)
  out = out:gsub("^[%(%[{<\"'`*_]+", ""):gsub("[%)%]}>\"'`*_]+$", "")
  out = out:gsub("[%.,;:!%?]+$", "")
  return out
end

---@internal
--- The `:line[:col]` suffix a log line carries, split off the path itself.
--- `classify` stats the path, so the suffix has to go; it is returned so the
--- caller can keep it for display.
---@param str string
---@return string path
---@return string|nil location
local function split_location(str)
  local path, location = str:match("^(.-)(:%d+:?%d*)$")
  if path and path ~= "" then
    return path, location
  end
  return str, nil
end

---@internal
--- gopath.nvim's answer for the cursor position, when it is installed, is
--- enabled, and confirms the path exists.
---@return string|nil absolute path
local function via_gopath()
  local ok, gopath = pcall(require, "gopath.resolve")
  if not ok or type(gopath.resolve_at_cursor) ~= "function" then
    return nil
  end

  local ok_res, res = pcall(gopath.resolve_at_cursor)
  if not ok_res or type(res) ~= "table" then
    return nil
  end

  -- A URL result is gopath's own concern (it opens a browser); the hover has
  -- its own URL previewer reached through the link path, and a bare URL is
  -- already found by `link_scan`. Only local, confirmed files interest us.
  if res.kind == "url" then
    return nil
  end
  if not (res.exists and type(res.path) == "string" and res.path ~= "") then
    return nil
  end
  return res.path
end

---@internal
--- The `<cfile>` token, resolved against the buffer's own directory first and
--- the cwd second — the same order `classify.resolve_path` uses for a link,
--- so a bare `./a.png` and a linked `./a.png` resolve identically.
---@param bufnr integer
---@return string|nil raw target as written
local function via_cfile(bufnr)
  local cfile = vim.fn.expand("<cfile>")
  if type(cfile) ~= "string" or cfile == "" then
    return nil
  end

  cfile = trim_delimiters(cfile)
  local path = split_location(cfile)
  if not looks_like_path(path) then
    return nil
  end

  local uv = vim.uv or vim.loop
  local expanded = vim.fn.expand(path)

  -- Absolute already: hand it back untouched.
  if expanded:match("^/") or expanded:match("^%a:[\\/]") or expanded:match("^[\\/][\\/]") then
    return uv.fs_stat(expanded) and path or nil
  end

  local bases = {}
  local name = api.nvim_buf_get_name(bufnr)
  if name ~= "" then
    bases[#bases + 1] = vim.fs.dirname(name)
  end
  bases[#bases + 1] = uv.cwd()

  for _, base in ipairs(bases) do
    if base and base ~= "" then
      if uv.fs_stat(base .. "/" .. expanded) then
        return path
      end
    end
  end
  return nil
end

--- A path under the cursor written without link syntax.
---
--- Returns a `Lib.Hover.Source`-shaped table so `lib.nvim.hover` can treat it exactly
--- like a scanned link — `target` is what `classify` receives.
---@param bufnr? integer
---@return Lib.Hover.Source|nil
function M.under_cursor(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end

  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= bufnr then
    return nil
  end

  local pos = api.nvim_win_get_cursor(win)
  local row, col = pos[1], pos[2]
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line or line == "" then
    return nil
  end

  -- Cheap gate before anything else: the cursor has to sit on non-blank text
  -- that could be part of a path at all. Without this, every CursorHold in
  -- prose would reach gopath's resolver pipeline.
  local char = line:sub(col + 1, col + 1)
  if char == "" or char:match("%s") then
    return nil
  end

  local token =
    trim_delimiters(type(vim.fn.expand("<cfile>")) == "string" and vim.fn.expand("<cfile>") or "")
  if not looks_like_path(token) then
    return nil
  end

  -- gopath first: it is the one that handles truncated paths and `:line`
  -- suffixes, which is the case `<cfile>` cannot resolve on its own.
  local resolved = via_gopath() or via_cfile(bufnr)

  -- Nothing on disk. Worth reporting only when the text cannot have been
  -- anything but a path -- see `is_unambiguous_path`. `classify` then turns
  -- it into a `missing` target and the preview marks it with a red ✗, the
  -- same answer a broken *link* already gets.
  if not resolved then
    if not is_unambiguous_path(token) then
      return nil
    end
    resolved = (split_location(token))
  end

  return {
    target = resolved,
    col = col,
    col_end = col,
    lnum = row,
    kind = "bare_path",
  }
end

return M
