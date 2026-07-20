---@module 'lib.nvim.harvest.render'
--- Turn a header list + row matrix into text: a GFM table, CSV/TSV, or plain
--- lines.
---
--- The GFM renderer is the one worth sharing. markdown.nvim's `tableview`
--- renders tables that *already exist* in a buffer; nothing in the ecosystem
--- went the other direction (arbitrary rows → a table you can paste). Column
--- widths are measured in display cells, not bytes, so a row containing
--- multibyte text still lines up in a fixed-width terminal.
---
---```lua
--- local render = require("lib.nvim.harvest.render")
--- render.markdown_table({ "File", "Link" }, { { "a.md", "https://x" } })
--- render.csv({ "a", "b" }, { { "1", "2" } })
--- render.lines({ { "x", "y" } }, " — ")
---```

require("lib.nvim.harvest.@types")

local M = {}

--- Cell text, flattened to a single line and with GFM's cell separator
--- escaped — an unescaped "|" would silently split one cell into two.
---@param v any
---@return string
local function cell(v)
  local s = tostring(v == nil and "" or v)
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("|", "\\|")
  return s
end

--- Display width of `s` (not its byte length): `vim.fn.strdisplaywidth`
--- accounts for multibyte and double-width characters, which is what column
--- padding has to agree with to look aligned.
---@param s string
---@return integer
local function width(s)
  return vim.fn.strdisplaywidth(s)
end

---@param s string
---@param w integer
---@param align "l"|"c"|"r"
---@return string
local function pad(s, w, align)
  local gap = w - width(s)
  if gap <= 0 then
    return s
  end
  if align == "r" then
    return string.rep(" ", gap) .. s
  end
  if align == "c" then
    local left = math.floor(gap / 2)
    return string.rep(" ", left) .. s .. string.rep(" ", gap - left)
  end
  return s .. string.rep(" ", gap)
end

--- Render a GFM table.
---@param headers string[]
---@param rows any[][]
---@param opts Lib.Harvest.TableOpts|nil
---@return string
function M.markdown_table(headers, rows, opts)
  opts = opts or {}
  headers = headers or {}
  rows = rows or {}

  local ncols = #headers
  for _, r in ipairs(rows) do
    ncols = math.max(ncols, #r)
  end
  if ncols == 0 then
    return ""
  end

  local align = opts.align or {}

  -- Normalize into a padded string matrix first so width measurement and
  -- emission agree on exactly the same cell contents.
  local head = {}
  for c = 1, ncols do
    head[c] = cell(headers[c])
  end
  local body = {}
  for i, r in ipairs(rows) do
    local out = {}
    for c = 1, ncols do
      out[c] = cell(r[c])
    end
    body[i] = out
  end

  local w = {}
  for c = 1, ncols do
    w[c] = width(head[c])
    for _, r in ipairs(body) do
      w[c] = math.max(w[c], width(r[c]))
    end
    -- GFM needs at least three dashes to be an unambiguous delimiter row.
    w[c] = math.max(w[c], 3)
  end

  local function row_line(cells)
    local parts = {}
    for c = 1, ncols do
      parts[c] = pad(cells[c], w[c], align[c] or "l")
    end
    return "| " .. table.concat(parts, " | ") .. " |"
  end

  local sep = {}
  for c = 1, ncols do
    local a = align[c] or "l"
    if a == "r" then
      sep[c] = string.rep("-", w[c] - 1) .. ":"
    elseif a == "c" then
      sep[c] = ":" .. string.rep("-", w[c] - 2) .. ":"
    else
      sep[c] = string.rep("-", w[c])
    end
  end

  local lines = { row_line(head), "| " .. table.concat(sep, " | ") .. " |" }
  for _, r in ipairs(body) do
    lines[#lines + 1] = row_line(r)
  end
  return table.concat(lines, "\n")
end

--- Render delimiter-separated values. Fields containing the separator, a
--- quote, or a newline are quoted and their quotes doubled (RFC 4180).
---@param headers string[]|nil
---@param rows any[][]
---@param sep string|nil  Defaults to ",".
---@return string
function M.csv(headers, rows, sep)
  sep = sep or ","
  local lines = {}

  local function emit(r)
    local parts = {}
    for i, v in ipairs(r) do
      local s = tostring(v == nil and "" or v)
      if s:find(sep, 1, true) or s:find('"', 1, true) or s:find("[\r\n]") then
        s = '"' .. s:gsub('"', '""') .. '"'
      end
      parts[i] = s
    end
    lines[#lines + 1] = table.concat(parts, sep)
  end

  if headers and #headers > 0 then
    emit(headers)
  end
  for _, r in ipairs(rows or {}) do
    emit(r)
  end
  return table.concat(lines, "\n")
end

--- Render rows as plain lines, joining each row's cells with `sep`.
---@param rows any[][]
---@param sep string|nil  Defaults to "  ".
---@return string
function M.lines(rows, sep)
  sep = sep or "  "
  local out = {}
  for i, r in ipairs(rows or {}) do
    local parts = {}
    for j, v in ipairs(r) do
      parts[j] = tostring(v == nil and "" or v)
    end
    out[i] = table.concat(parts, sep)
  end
  return table.concat(out, "\n")
end

return M
