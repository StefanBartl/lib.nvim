---@module 'lib.nvim.bindings.keymap.cheatsheet'
--- The lines of a `g?` cheatsheet, built from what a plugin really has bound.
---
--- `keymap.registered(plugin)` knows every named action with its `lhs`, mode and `desc`; each plugin used to
--- format its own cheatsheet from that. This does it once: grouped, aligned, only what is actually bound
--- (an action the user disabled is simply not there, one action on several keys shows all of them), plus the
--- highlight spans so a float or a scratch buffer can colour it.
---
--- ```lua
--- local sheet = require("lib.nvim.bindings.keymap").cheatsheet("testing", {
---   groups = {
---     { title = "Run",  actions = { "run_file", "run_nearest" } },
---     { title = "Move", actions = { "next_fail", "prev_fail" } },
---   },
---   footer = "q close",
---   width = 60,
--- })
--- vim.api.nvim_buf_set_lines(buf, 0, -1, false, sheet.lines)
--- for _, h in ipairs(sheet.highlights) do
---   vim.api.nvim_buf_add_highlight(buf, ns, h.group, h.line, h.col_start, h.col_end)
--- end
--- ```

local M = {}

---@class Lib.Keymap.CheatsheetGroup
---@field title string
---@field actions string[]  # Action names, in the order to show them.

---@class Lib.Keymap.CheatsheetOpts
---@field groups? Lib.Keymap.CheatsheetGroup[]  # Sections; actions not named in any go under `other_title`. Default: one block, no heading.
---@field other_title? string                   # Heading of the leftovers when `groups` is given (default "Other").
---@field buffer? integer                       # Only what is global or bound to this buffer (default: global entries only).
---@field footer? string|string[]               # Hint line(s) under the list.
---@field width? integer                        # Maximum width in columns; a longer description is cut with "…" (default none).
---@field indent? integer                       # Left indent (default 2).
---@field modes? boolean                        # Prefix each key column with the modes (`n,x`) when an action is not normal-only.
---@field hl? { heading?: string, key?: string, desc?: string, footer?: string }  # Highlight groups.

---@class Lib.Keymap.CheatsheetSpan
---@field line integer       # 0-based line index into `lines`.
---@field col_start integer  # 0-based byte column.
---@field col_end integer    # Exclusive.
---@field group string       # Highlight group.

---@class Lib.Keymap.CheatsheetRow
---@field name string
---@field keys string[]
---@field modes string[]
---@field desc string

---@class Lib.Keymap.Cheatsheet
---@field lines string[]
---@field highlights Lib.Keymap.CheatsheetSpan[]
---@field rows Lib.Keymap.CheatsheetRow[]  # What is shown, in display order (groups flattened).
---@field width integer                    # Display width of the widest line.

local function dw(s)
  return vim.fn.strdisplaywidth(s)
end

---@param value string|string[]|nil
---@return string[]
local function as_list(value)
  if type(value) == "string" then
    return { value }
  end
  return type(value) == "table" and value or {}
end

---@param plugin string
---@param desc string|nil
---@return string
local function strip_plugin(plugin, desc)
  desc = desc or ""
  local base = plugin:gsub("/.*$", "")
  local prefix = base .. ": "
  if desc:sub(1, #prefix) == prefix then
    return desc:sub(#prefix + 1)
  end
  return desc
end

---Fold the registry's per-key entries into one row per action.
---@param plugin string
---@param opts Lib.Keymap.CheatsheetOpts
---@return Lib.Keymap.CheatsheetRow[] rows
local function collect(plugin, opts)
  local rows, by_name = {}, {}
  for _, e in ipairs(require("lib.nvim.bindings.keymap").registered(plugin)) do
    local local_ok = e.buffer == nil or e.buffer == false
    if opts.buffer ~= nil then
      local_ok = local_ok or e.buffer == opts.buffer
    end
    if e.bound and e.lhs and e.lhs ~= "" and local_ok then
      local row = by_name[e.name]
      if not row then
        row = { name = e.name, keys = {}, modes = {}, desc = strip_plugin(plugin, e.desc) }
        by_name[e.name] = row
        rows[#rows + 1] = row
      end
      if row.desc == "" then
        row.desc = strip_plugin(plugin, e.desc)
      end
      if not vim.tbl_contains(row.keys, e.lhs) then
        row.keys[#row.keys + 1] = e.lhs
      end
      for _, m in ipairs(as_list(e.mode)) do
        if not vim.tbl_contains(row.modes, m) then
          row.modes[#row.modes + 1] = m
        end
      end
    end
  end
  return rows
end

---Build the cheatsheet of one plugin (or of one `plugin/surface` registry key).
---@param plugin string
---@param opts? Lib.Keymap.CheatsheetOpts
---@return Lib.Keymap.Cheatsheet
function M.build(plugin, opts)
  opts = opts or {}
  if type(plugin) ~= "string" or plugin == "" then
    error("lib.nvim.bindings.keymap.cheatsheet: plugin must be a non-empty string", 2)
  end
  local hl = vim.tbl_extend("force", {
    heading = "Title",
    key = "Special",
    desc = "Normal",
    footer = "Comment",
  }, opts.hl or {})
  local indent = opts.indent or 2
  local rows = collect(plugin, opts)

  -- sections
  ---@type { title: string|nil, rows: Lib.Keymap.CheatsheetRow[] }[]
  local sections = {}
  if opts.groups then
    local used = {}
    local by_name = {}
    for _, row in ipairs(rows) do
      by_name[row.name] = row
    end
    for _, g in ipairs(opts.groups) do
      local sec = { title = g.title, rows = {} }
      for _, name in ipairs(g.actions or {}) do
        if by_name[name] and not used[name] then
          used[name] = true
          sec.rows[#sec.rows + 1] = by_name[name]
        end
      end
      if #sec.rows > 0 then
        sections[#sections + 1] = sec
      end
    end
    local rest = {}
    for _, row in ipairs(rows) do
      if not used[row.name] then
        rest[#rest + 1] = row
      end
    end
    if #rest > 0 then
      sections[#sections + 1] = { title = opts.other_title or "Other", rows = rest }
    end
  elseif #rows > 0 then
    sections[1] = { rows = rows }
  end

  -- the key column: its text per row, and one width for all of them
  local function key_text(row)
    local text = table.concat(row.keys, " / ")
    if opts.modes and not (#row.modes == 1 and row.modes[1] == "n") and #row.modes > 0 then
      text = table.concat(row.modes, ",") .. " " .. text
    end
    -- With a width, the key column may take at most half of it: the rest is for the description.
    if opts.width then
      local cap = math.max(8, math.floor((opts.width - indent) / 2))
      if dw(text) > cap then
        text = (require("lib.lua.strings").truncate(text, cap, { ellipsis = "…" }))
      end
    end
    return text
  end
  local key_w = 0
  for _, sec in ipairs(sections) do
    for _, row in ipairs(sec.rows) do
      key_w = math.max(key_w, dw(key_text(row)))
    end
  end

  local lines, spans, shown = {}, {}, {}
  local function add_span(line, s, e, group)
    spans[#spans + 1] = { line = line, col_start = s, col_end = e, group = group }
  end

  for si, sec in ipairs(sections) do
    if si > 1 and (sec.title or sections[si - 1].title) then
      lines[#lines + 1] = ""
    end
    if sec.title then
      lines[#lines + 1] = string.rep(" ", math.max(indent - 2, 0)) .. sec.title
      add_span(#lines - 1, math.max(indent - 2, 0), #lines[#lines], hl.heading)
    end
    for _, row in ipairs(sec.rows) do
      local key = key_text(row)
      local pad = string.rep(" ", key_w - dw(key))
      local left = string.rep(" ", indent) .. key .. pad .. "  "
      local desc = row.desc ~= "" and row.desc or row.name
      if opts.width then
        local room = opts.width - dw(left)
        if room < 1 then
          desc = ""
        elseif dw(desc) > room then
          desc = (require("lib.lua.strings").truncate(desc, room, { ellipsis = "…" }))
        end
      end
      lines[#lines + 1] = left .. desc
      local li = #lines - 1
      add_span(li, indent, indent + #key, hl.key)
      if desc ~= "" then
        add_span(li, #left, #left + #desc, hl.desc)
      end
      shown[#shown + 1] = row
    end
  end

  local footer = as_list(opts.footer)
  if #footer > 0 then
    if #lines > 0 then
      lines[#lines + 1] = ""
    end
    for _, text in ipairs(footer) do
      lines[#lines + 1] = string.rep(" ", indent) .. text
      add_span(#lines - 1, indent, #lines[#lines], hl.footer)
    end
  end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, dw(l))
  end
  return { lines = lines, highlights = spans, rows = shown, width = width }
end

return M
