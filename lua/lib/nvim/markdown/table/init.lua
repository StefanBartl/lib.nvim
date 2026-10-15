---@module 'lib.nvim.markdown.table'
--- Parse and re-render GFM pipe tables.
---@description
--- Extracted from two duplicated implementations — `markdown.nvim`'s
--- `core/table_fmt.lua` and `buffer-ctx.nvim`'s `format/table_fmt.lua` — that
--- had already drifted, each carrying a fix the other lacked. This module
--- takes the better half of each (see the individual function docs below for
--- which fix came from where); a second copy does not merely cost the lines
--- twice, it quietly keeps one caller on the older behaviour.
---
--- **Width, deliberately `vim.fn.strdisplaywidth`.** `lib.lua.strings.width`
--- has a pure-Lua `display_width`, and it is not the same function: it decides
--- ambiguous-width characters from its own tables while Neovim consults
--- `'ambiwidth'` and the active encoding. Both plugins measured with
--- `strdisplaywidth`, and these tables get written back into the user's files
--- — a different measurement would silently reflow every table anybody has.
--- The pure version is the fallback for a non-Neovim host, and `opts.width_fn`
--- overrides both.
---
--- **No notifications, no config lookup.** Everything is returned: a caller
--- with a `notify` prefix and a config table wires those two ends itself. That
--- is what let the buffer- and file-level helpers move here too rather than
--- staying behind as the third and fourth copy.

local strings = require("lib.lua.strings.core")

local M = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Measuring and padding
-- ─────────────────────────────────────────────────────────────────────────────

---Trim leading/trailing whitespace. Non-string input trims to `""`.
---@param str any
---@return string
function M.trim(str)
  if type(str) ~= "string" then
    return ""
  end
  return strings.trim(str)
end

local trim = M.trim

---Display width of `str` in terminal columns.
---
---`vim.fn.strdisplaywidth` when Neovim is there (see the module note on why
---that specific function), `lib.lua.strings.width` otherwise.
---@param str any
---@return integer
function M.display_width(str)
  if type(str) ~= "string" then
    return 0
  end
  if vim and vim.fn and vim.fn.strdisplaywidth then
    local ok, w = pcall(vim.fn.strdisplaywidth, str)
    if ok then
      return w
    end
  end
  return require("lib.lua.strings.width").display_width(str)
end

---Pad `str` to `width` columns, aligned.
---
---An odd remainder goes to the right when centering, matching
---`lib.lua.strings.width.pad_center`.
---@param str string
---@param width integer
---@param align "left"|"center"|"right"
---@param width_fn? fun(s: string): integer
---@return string
function M.pad_cell(str, width, align, width_fn)
  local content = trim(str)
  local cw = (width_fn or M.display_width)(content)
  if cw >= width then
    return content
  end
  local pad = width - cw
  if align == "left" then
    return content .. string.rep(" ", pad)
  elseif align == "right" then
    return string.rep(" ", pad) .. content
  end
  local left = math.floor(pad / 2)
  return string.rep(" ", left) .. content .. string.rep(" ", pad - left)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Recognising and parsing
-- ─────────────────────────────────────────────────────────────────────────────

---Does the trimmed row start with a pipe and end with a real (unescaped) one?
---
---An odd run of backslashes before the final pipe escapes it (`d \|` keeps
---the pipe inside the cell), so the row has no closing pipe. A plain
---byte walk, no pattern: nothing to backtrack on a long run of backslashes.
---@param t string  # already trimmed
---@return boolean
local function has_closing_pipe(t)
  if #t < 2 or t:byte(1) ~= 124 or t:byte(-1) ~= 124 then
    return false
  end
  local bs, i = 0, #t - 1
  while i >= 2 and t:byte(i) == 92 do
    bs = bs + 1
    i = i - 1
  end
  return bs % 2 == 0
end

---Is `line` a pipe-table row?
---@param line any
---@return boolean
function M.is_table_line(line)
  if type(line) ~= "string" then
    return false
  end
  return has_closing_pipe(trim(line))
end

---Is `line` a table's separator row, and in which style?
---
---"spaced" is `| --- | --- |`, "compact" is `|---|---|`. The style is carried
---through so re-rendering a table keeps the one the author wrote.
---@param line any
---@return boolean is_sep
---@return "spaced"|"compact"|nil style
function M.is_separator_line(line)
  if type(line) ~= "string" then
    return false, nil
  end
  local t = trim(line)
  if not t:match("%-") then
    return false, nil
  end
  if not t:match("^|.*|$") then
    return false, nil
  end
  local inner = t:match("^|(.+)|$")
  if not inner then
    return false, nil
  end
  if not inner:match("^[%-%s:|]+$") then
    return false, nil
  end
  local spaced = inner:match("%s%-") or inner:match("%-%s")
  return true, spaced and "spaced" or "compact"
end

---Split one table row into trimmed cells, honouring the escaped pipe.
---
---A pipe preceded by an odd number of backslashes does not end a cell (GFM:
---`\|` stays in the cell, also inside a code span), so the cell keeps the raw
---`\|` text and a re-render writes the same bytes back. `find` with a plain
---pattern instead of a char-by-char `..` accumulator: the latter is O(n²) in
---the row length, because each concatenation reallocates and rescans the
---growing string. A trailing `|` is appended so the segment after the last
---real separator is captured by the same step as every other one.
---@param line string
---@return string[] cells
---@return { [1]: integer, [2]: integer }[] ranges  # 1-based inclusive byte range of each raw cell (between its pipes) in `line`
function M.split_cells(line)
  local cells, ranges = {}, {}
  if type(line) ~= "string" then
    return cells, ranges
  end
  local trimmed = trim(line)
  -- Not `^|(.-)%s*|$`: that retries a whitespace run from every byte inside it (SEC-32).
  if not has_closing_pipe(trimmed) then
    return cells, ranges
  end
  -- Offset of `trimmed` inside `line`, so ranges are in `line` coordinates.
  local base = #(line:match("^%s*") or "") + 1
  local inner = strings.rtrim(trimmed:sub(2, -2))
  local start, pos = 1, 1
  while true do
    local p = inner:find("|", pos, true)
    if p then
      -- Odd run of backslashes right before the pipe: escaped, keep scanning.
      local bs = 0
      while p - bs - 1 >= start and inner:byte(p - bs - 1) == 92 do
        bs = bs + 1
      end
      if bs % 2 == 1 then
        pos = p + 1
      else
        cells[#cells + 1] = trim(inner:sub(start, p - 1))
        ranges[#ranges + 1] = { base + start, base + p - 1 }
        start, pos = p + 1, p + 1
      end
    else
      cells[#cells + 1] = trim(inner:sub(start))
      ranges[#ranges + 1] = { base + start, base + #trimmed - 2 } -- up to the closing pipe, padding included
      break
    end
  end
  return cells, ranges
end

---Split one table row into trimmed cells (see `split_cells`).
---@param line string
---@return string[]
function M.parse_row(line)
  return (M.split_cells(line))
end

---Every GFM table in `lines`.
---
---A run of consecutive table lines shorter than three (header, separator, one
---row) is not a table and is skipped rather than reported.
---@param lines string[]
---@return Lib.Markdown.Table[]
function M.parse(lines)
  local tables = {}
  local i = 1
  while i <= #lines do
    if not M.is_table_line(lines[i]) then
      i = i + 1
    else
      local start = i
      while i <= #lines and M.is_table_line(lines[i]) do
        i = i + 1
      end
      local stop = i - 1
      if stop - start >= 2 then
        local rows, sep_style, sep_line_idx, col_count = {}, nil, nil, 0
        for ln = start, stop do
          local is_sep, style = M.is_separator_line(lines[ln])
          -- A header made of dashes (`| - | - |`) directly above the delimiter row is the header,
          -- not the delimiter: when the first two lines both look like a separator, the second is.
          if is_sep and ln == start and M.is_separator_line(lines[ln + 1]) then
            is_sep = false
          end
          -- only the first such line is the delimiter row; a later `| - | - |` is a data row
          if is_sep and not sep_line_idx then
            sep_line_idx = ln
            sep_style = style
          else
            local cells = M.parse_row(lines[ln])
            rows[#rows + 1] = cells
            if #cells > col_count then
              col_count = #cells
            end
          end
        end
        if sep_line_idx and #rows >= 2 then
          tables[#tables + 1] = {
            start_line = start,
            end_line = stop,
            rows = rows,
            col_count = col_count,
            separator_style = sep_style or "spaced",
          }
        end
      end
    end
  end
  return tables
end

---The table containing 1-based `lnum`, if any.
---@param tables Lib.Markdown.Table[]
---@param lnum integer
---@return Lib.Markdown.Table|nil
---@return string|nil err
function M.at_cursor(tables, lnum)
  for _, tbl in ipairs(tables) do
    if lnum >= tbl.start_line and lnum <= tbl.end_line then
      return tbl, nil
    end
  end
  return nil, "No table at cursor"
end

---Column widths: the widest cell in each column.
---@param rows string[][]
---@param col_count integer
---@param width_fn? fun(s: string): integer
---@return integer[]
function M.calc_widths(rows, col_count, width_fn)
  local wf = width_fn or M.display_width
  local widths = {}
  for i = 1, col_count do
    widths[i] = 0
  end
  for _, row in ipairs(rows) do
    for ci, cell in ipairs(row) do
      if ci <= col_count then
        widths[ci] = math.max(widths[ci], wf(cell))
      end
    end
  end
  return widths
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Column alignment overrides
-- ─────────────────────────────────────────────────────────────────────────────

---Resolve `col` -> alignment overrides against a table's header.
---
---An override may name a column by 1-based index or by header text
---(case-insensitively). One that matches nothing is **returned as a warning**
---rather than reported here: a library that notifies decides for its caller
---how loud a config typo should be, and both original copies wanted that
---differently.
---@param overrides Lib.Markdown.Table.ColOverride[]|nil
---@param header_cells string[]
---@param col_count integer
---@return table<integer, string> map
---@return string[] warnings
function M.resolve_overrides(overrides, header_cells, col_count)
  local map, warnings = {}, {}
  if not overrides or #overrides == 0 then
    return map, warnings
  end

  local name_to_idx = {}
  for i = 1, col_count do
    local key = trim(header_cells[i] or ""):lower()
    if key ~= "" then
      name_to_idx[key] = i
    end
  end

  for _, ov in ipairs(overrides) do
    local idx
    if type(ov.col) == "number" then
      idx = ov.col
    elseif type(ov.col) == "string" then
      idx = name_to_idx[ov.col:lower()]
    end
    if idx and idx >= 1 and idx <= col_count then
      map[idx] = ov.align
    else
      warnings[#warnings + 1] =
        string.format("col_overrides: column %q not found (ignored)", tostring(ov.col))
    end
  end

  return map, warnings
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Rendering
-- ─────────────────────────────────────────────────────────────────────────────

---Render a table's separator row for a given style.
---@param widths integer[]
---@param style "spaced"|"compact"
---@return string
function M.gen_separator(widths, style)
  local parts = {}
  if style == "spaced" then
    for _, w in ipairs(widths) do
      parts[#parts + 1] = " " .. string.rep("-", w) .. " "
    end
  else
    for _, w in ipairs(widths) do
      parts[#parts + 1] = string.rep("-", w + 2)
    end
  end
  return "|" .. table.concat(parts, "|") .. "|"
end

local gen_separator = M.gen_separator

---Render one already-padded table row.
---@param cells string[]
---@param widths integer[]
---@param default_align "left"|"center"|"right"
---@param override_map table<integer, string>
---@param width_fn? fun(s: string): integer
---@return string
function M.format_row(cells, widths, default_align, override_map, width_fn)
  local parts = {}
  for ci, w in ipairs(widths) do
    parts[#parts + 1] = M.pad_cell(cells[ci] or "", w, override_map[ci] or default_align, width_fn)
  end
  return "| " .. table.concat(parts, " | ") .. " |"
end

local format_row = M.format_row

---Re-render one table. Takes the content half: `render` never looks at where
---the table sat, so a table assembled in memory is as valid an input as a
---parsed one.
---@param parsed Lib.Markdown.Table.Content
---@param opts Lib.Markdown.Table.RenderOpts|nil
---@return string[] lines
function M.render(parsed, opts)
  opts = opts or {}
  local header_align = opts.header_align or "left"
  local entry_align = opts.entry_align or "left"
  local override_map = opts.override_map or {}
  local width_fn = opts.width_fn or M.display_width

  local widths = M.calc_widths(parsed.rows, parsed.col_count, width_fn)
  local out = {}
  out[1] = format_row(parsed.rows[1], widths, header_align, override_map, width_fn)
  out[2] = gen_separator(widths, parsed.separator_style)
  for i = 2, #parsed.rows do
    out[#out + 1] = format_row(parsed.rows[i], widths, entry_align, override_map, width_fn)
  end
  return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Whole-document formatting
-- ─────────────────────────────────────────────────────────────────────────────

---Re-render every table in `lines`, returning new lines.
---
---The pure heart of this module: the buffer and file helpers below are this
---plus I/O, which is what makes them testable without either.
---@param lines string[]
---@param opts Lib.Markdown.Table.FormatOpts|nil
---@return string[] lines
---@return integer count      # tables re-rendered
---@return string[] warnings
function M.format_lines(lines, opts)
  opts = opts or {}
  local tables = M.parse(lines)
  if #tables == 0 then
    return lines, 0, {}
  end

  -- Built as a new list rather than spliced in place, so every table's
  -- recorded start/end still refers to the input while it is being read --
  -- rewriting in place moves everything below the first table and invalidates
  -- the rest of the positions.
  local by_start = {}
  for _, t in ipairs(tables) do
    by_start[t.start_line] = t
  end

  local out, warnings = {}, {}
  local i = 1
  while i <= #lines do
    local parsed = by_start[i]
    if parsed then
      local map, warn = M.resolve_overrides(opts.col_overrides, parsed.rows[1], parsed.col_count)
      for _, w in ipairs(warn) do
        warnings[#warnings + 1] = w
      end
      local rendered = M.render(parsed, {
        header_align = opts.header_align,
        entry_align = opts.entry_align,
        override_map = map,
        width_fn = opts.width_fn,
      })
      -- A source line that ends in a CR (a CRLF block inside a file with mixed endings, where `format_file`
      -- could not strip the CRs globally) gets its CR back on the rendered line at the same position; `trim`
      -- drops it while parsing, so without this an already formatted block would still count as changed.
      -- Rendering keeps one line per source line, so each keeps its own ending; a block whose line count
      -- changed (it cannot be matched line by line) takes a CR only when every source line had one.
      local span = parsed.end_line - parsed.start_line + 1
      local all_cr = true
      for ln = parsed.start_line, parsed.end_line do
        if lines[ln]:sub(-1) ~= "\r" then
          all_cr = false
          break
        end
      end
      for k, l in ipairs(rendered) do
        local cr = all_cr
        if #rendered == span then
          cr = lines[parsed.start_line + k - 1]:sub(-1) == "\r"
        end
        out[#out + 1] = cr and (l .. "\r") or l
      end
      i = parsed.end_line + 1
    else
      out[#out + 1] = lines[i]
      i = i + 1
    end
  end

  return out, #tables, warnings
end

---Re-render every table in `bufnr`.
---@param bufnr integer|nil  # Defaults to the current buffer.
---@param opts Lib.Markdown.Table.FormatOpts|nil
---@return boolean ok
---@return string|nil err
---@return integer count
---@return string[] warnings
function M.format_buffer(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Invalid buffer", 0, {}
  end

  local ok_read, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok_read or type(lines) ~= "table" then
    return false, "Failed to read buffer", 0, {}
  end

  local out, count, warnings = M.format_lines(lines, opts)
  if count == 0 then
    return true, nil, 0, warnings
  end
  -- Nothing changed: no write, so no `changedtick` bump. A caller that
  -- re-formats from TextChanged (table mode) would otherwise re-trigger itself
  -- on its own no-op write, forever.
  if vim.deep_equal(out, lines) then
    return true, nil, count, warnings
  end

  local ok_write = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, out)
  if not ok_write then
    return false, "Failed to update buffer", 0, warnings
  end
  return true, nil, count, warnings
end

---Re-render only the table under `lnum` (default: the cursor).
---@param bufnr integer|nil
---@param opts Lib.Markdown.Table.FormatOpts|nil
---@return boolean ok
---@return string|nil err
---@return string[] warnings
function M.format_at_cursor(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Invalid buffer", {}
  end

  local lnum = opts.lnum
  if not lnum then
    local ok_c, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
    if not ok_c then
      return false, "Failed to get cursor position", {}
    end
    lnum = cursor[1]
  end

  local ok_read, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok_read or type(lines) ~= "table" then
    return false, "Failed to read buffer", {}
  end

  local parsed, err = M.at_cursor(M.parse(lines), lnum)
  if not parsed then
    return false, err, {}
  end

  local map, warnings = M.resolve_overrides(opts.col_overrides, parsed.rows[1], parsed.col_count)
  local rendered = M.render(parsed, {
    header_align = opts.header_align,
    entry_align = opts.entry_align,
    override_map = map,
    width_fn = opts.width_fn,
  })

  -- Unchanged table: no write (see `format_buffer`).
  if vim.deep_equal(rendered, vim.list_slice(lines, parsed.start_line, parsed.end_line)) then
    return true, nil, warnings
  end

  local ok_write = pcall(
    vim.api.nvim_buf_set_lines,
    bufnr,
    parsed.start_line - 1,
    parsed.end_line,
    false,
    rendered
  )
  if not ok_write then
    return false, "Failed to update buffer", warnings
  end
  return true, nil, warnings
end

---Re-render every table in the file at `path`, in place.
---
---Only writes when something actually changed, so a formatting run over a
---tree does not touch the mtime of every file in it.
---@param path string
---@param opts Lib.Markdown.Table.FormatOpts|nil
---@return boolean ok
---@return string|nil err
---@return integer count
---@return string[] warnings
function M.format_file(path, opts)
  -- Binary on both ends: text mode would translate CRLF on Windows, and a
  -- BOM would stay glued to line 1 (which then no longer starts with a pipe).
  local fh, err = io.open(path, "rb")
  if not fh then
    return false, string.format("Cannot open %q: %s", path, err or "?"), 0, {}
  end
  local content = fh:read("a") or ""
  fh:close()
  local original = content

  local bom = content:sub(1, 3) == "\239\187\191"
  if bom then
    content = content:sub(4)
  end
  local final_newline = content:sub(-1) == "\n"
  local lines = {}
  if content ~= "" then
    for line in (final_newline and content or content .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
  end
  -- CRLF only when every terminated line ends in CR LF; a mixed file keeps its
  -- CRs inside the lines (they are not touched) instead of being normalised.
  local terminated = final_newline and #lines or (#lines - 1)
  local crlf = terminated > 0
  for i = 1, terminated do
    if lines[i]:sub(-1) ~= "\r" then
      crlf = false
      break
    end
  end
  if crlf then
    for i = 1, terminated do
      lines[i] = lines[i]:sub(1, -2)
    end
  end

  local out, count, warnings = M.format_lines(lines, opts)
  if count == 0 or table.concat(out, "\n") == table.concat(lines, "\n") then
    return true, nil, count, warnings
  end

  local eol = crlf and "\r\n" or "\n"
  local body = table.concat(out, eol) .. (final_newline and eol or "")
  local wh, werr = io.open(path, "wb")
  if not wh then
    return false, string.format("Cannot write %q: %s", path, werr or "?"), 0, warnings
  end
  -- In place (not temp + rename): keeps symlinks, hard links and permissions,
  -- and a rename over a file another program holds open fails on Windows.
  -- `open("wb")` has already truncated the file, so a failed write must put the
  -- original bytes back instead of reporting success over a short file.
  local wrote, write_err = wh:write(bom and "\239\187\191" or "", body)
  local closed, close_err = wh:close()
  if not wrote or not closed then
    local restored = false
    local rh = io.open(path, "wb")
    if rh then
      local rw = rh:write(original)
      local rc = rh:close()
      restored = rw ~= nil and rc ~= nil
    end
    return false,
      string.format(
        "Cannot write %q: %s%s",
        path,
        tostring(write_err or close_err or "?"),
        restored and ""
          or " -- AND the original could not be restored, the file may be truncated or damaged"
      ),
      0,
      warnings
  end

  return true, nil, count, warnings
end

---@type Lib.Markdown.Table.Mod
return M
