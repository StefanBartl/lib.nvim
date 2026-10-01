---@module 'lib.nvim.markdown.link_cursor'
--- Put the cursor where a freshly inserted markdown link still needs typing.
---@description
--- Every plugin that drops a `[title](path)` / `![alt](path)` into a buffer
--- used to leave the cursor *behind* the link, which is exactly where nothing
--- needs to be written any more. The rule here is "go where something is
--- missing", and then enter insert mode:
---
---   * title empty (`![](assets/x.png)`, `[](https://...)`)  -> inside `[]`
---   * title filled, path filled (`[name](path)`)            -> in the path
---                                                              (end of it by
---                                                              default)
---   * title filled, path empty (`[name]()`)                 -> inside `()`
---
--- With several links in one insertion (a multi-line paste of a list of
--- links) the FIRST link decides. Text without a link puts the cursor behind
--- the text, as before.
---
--- This module only places the cursor and (optionally) inserts; it never
--- builds a link -- building stays with each caller, which knows its own
--- path spelling and title.
---
--- Columns are 0-based byte offsets and rows 0-based, matching
--- `nvim_buf_set_text`; `nvim_win_set_cursor` wants a 1-based row, the
--- conversion lives in `place()`.

local M = {}

---@class Lib.Markdown.LinkCursor.Opts
---@field enable? boolean           Move the cursor into the link at all (default true); false = behind the inserted text
---@field startinsert? boolean      Enter insert mode after placing the cursor (default true)
---@field path_cursor? "end"|"start" Where in a filled path the cursor goes (default "end")

---@type Lib.Markdown.LinkCursor.Opts
local config = { enable = true, startinsert = true, path_cursor = "end" }

--- Change the module-wide defaults (every caller of this module follows them
--- unless it passes its own `opts`). Unknown values are ignored, never raised.
---@param opts? Lib.Markdown.LinkCursor.Opts
function M.setup(opts)
  opts = opts or {}
  if type(opts.enable) == "boolean" then
    config.enable = opts.enable
  end
  if type(opts.startinsert) == "boolean" then
    config.startinsert = opts.startinsert
  end
  if opts.path_cursor == "end" or opts.path_cursor == "start" then
    config.path_cursor = opts.path_cursor
  end
end

---@return Lib.Markdown.LinkCursor.Opts
function M.config()
  return vim.deepcopy(config)
end

---@param opts? Lib.Markdown.LinkCursor.Opts
---@return Lib.Markdown.LinkCursor.Opts
local function resolve(opts)
  return vim.tbl_extend("force", config, opts or {})
end

---@param text string|string[]
---@return string[]
local function to_lines(text)
  if type(text) == "table" then
    return text
  end
  return vim.split(tostring(text), "\n", { plain = true })
end

---@class Lib.Markdown.LinkCursor.Spot
---@field row integer   0-based row inside the text
---@field col integer   0-based byte column inside that row
---@field kind "title"|"path"

--- Where the cursor belongs inside `text`: the first link's empty title, else
--- its path. nil when `text` contains no `[..](..)` link.
---@param text string|string[]
---@param opts? Lib.Markdown.LinkCursor.Opts
---@return Lib.Markdown.LinkCursor.Spot|nil
function M.locate(text, opts)
  local o = resolve(opts)
  for row, line in ipairs(to_lines(text)) do
    -- A leading `!` (image) needs no handling: the match starts at the `[`.
    -- `s` is the 1-based index of the `[`, which is also the 0-based column of
    -- the first title character (and of the `]` when the title is empty).
    local s, _, title, path = line:find("%[([^%]]*)%]%(([^%)]*)%)")
    if s then
      if title == "" then
        return { row = row - 1, col = s, kind = "title" }
      end
      -- 0-based column of the first path character: past `[`, the title, `]`, `(`.
      local path_start = s + #title + 2
      local col = o.path_cursor == "start" and path_start or (path_start + #path)
      return { row = row - 1, col = col, kind = "path" }
    end
  end
  return nil
end

--- Position the cursor for `text` that now sits at (`row`, `col`) of `win`'s
--- buffer, and enter insert mode if asked. Used after an insertion this
--- module did not perform itself.
---@param win integer
---@param row integer   0-based row where `text` starts
---@param col integer   0-based byte column where `text` starts
---@param text string|string[]
---@param opts? Lib.Markdown.LinkCursor.Opts
---@param buf? integer  the buffer `text` was inserted into; when given and `win` no longer shows it (an async insertion, the user moved on) nothing is placed
---@return boolean placed false when there was no window / nothing to place
function M.place(win, row, col, text, opts, buf)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  if buf and vim.api.nvim_win_get_buf(win) ~= buf then
    return false
  end
  local o = resolve(opts)
  local lines = to_lines(text)

  local target_row, target_col
  local spot = o.enable and M.locate(lines, o) or nil
  if spot then
    target_row = row + spot.row
    target_col = spot.col + (spot.row == 0 and col or 0)
  else
    -- Behind the text, like before: last line, column after its last byte.
    target_row = row + #lines - 1
    target_col = #lines[#lines] + (#lines == 1 and col or 0)
  end

  local win_buf = vim.api.nvim_win_get_buf(win)
  local line = vim.api.nvim_buf_get_lines(win_buf, target_row, target_row + 1, false)[1]
  if not line then
    return false
  end
  target_col = math.min(target_col, #line)

  if vim.api.nvim_get_current_win() ~= win then
    vim.api.nvim_set_current_win(win)
  end
  vim.api.nvim_win_set_cursor(win, { target_row + 1, target_col })
  if spot and o.startinsert then
    vim.cmd("startinsert")
  end
  return true
end

--- Insert `text` at (`row`, `col`) in `buf` and place the cursor in `win`.
---@param buf integer
---@param win integer
---@param row integer   0-based
---@param col integer   0-based byte column
---@param text string|string[]
---@param opts? Lib.Markdown.LinkCursor.Opts
---@return boolean ok false when the buffer/window is gone or not modifiable
function M.insert(buf, win, row, col, text, opts)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modifiable) then
    return false
  end
  local lines = to_lines(text)
  if not pcall(vim.api.nvim_buf_set_text, buf, row, col, row, col, lines) then
    return false
  end
  M.place(win, row, col, lines, opts, buf)
  return true
end

--- Insert several links (one per entry of `links`) at the cursor of `win`.
--- A single link goes inline, at the cursor, like `insert`. Several go on
--- lines of their own: they replace the current line when it is blank, else
--- they are added below it -- splitting a line of prose in the middle to
--- make room for a list is never what anyone wants. The cursor then goes into
--- the first link, per the usual rule.
---@param buf integer
---@param win integer
---@param links string[]
---@param opts? Lib.Markdown.LinkCursor.Opts
---@return boolean ok false when there is nothing to insert or the buffer/window is unusable
function M.insert_links(buf, win, links, opts)
  if #links == 0 then
    return false
  end
  if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  if #links == 1 then
    return M.insert(buf, win, cursor[1] - 1, cursor[2], links[1], opts)
  end

  if not vim.bo[buf].modifiable then
    return false
  end
  local row = cursor[1] - 1
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local first_row
  if line:match("^%s*$") then
    first_row = row
    if not pcall(vim.api.nvim_buf_set_lines, buf, row, row + 1, false, links) then
      return false
    end
  else
    first_row = row + 1
    if not pcall(vim.api.nvim_buf_set_lines, buf, row + 1, row + 1, false, links) then
      return false
    end
  end
  M.place(win, first_row, 0, links, opts, buf)
  return true
end

return M
