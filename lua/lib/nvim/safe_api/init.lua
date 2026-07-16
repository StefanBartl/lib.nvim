---@module 'lib.nvim.safe_api'
--- Validated, pcall-wrapped `vim.api` accessors for buffers/windows.
---
--- Every call validates its handle (and other arguments) up front, then
--- routes the actual `vim.api` call through `pcall`, so a deleted buffer or a
--- closed window never raises past a UI callback (extmark highlighting,
--- async job completion, autocmd handlers) — it just returns `false` plus an
--- error string.
---
--- All functions share one return shape:
---   success: boolean, result: any|nil, error: string|nil
---
--- `is_valid_buffer`/`is_valid_window` skip the `pcall` for hot paths that
--- only need a boolean. `with_retry` re-attempts a call a few times when the
--- failure looks handle-related (a window closing mid-async-callback), and
--- gives up immediately on any other kind of error.
---
--- Usage:
--- ```lua
--- local safe_api = require("lib.nvim.safe_api")
--- local ok, lines, err = safe_api.buf_get_lines(bufnr, 0, -1, false)
--- if not ok then return end
--- ```

require("lib.nvim.safe_api.@types")

local api = vim.api

local M = {}

---Wrap any function call in `pcall`, normalized to `(ok, result, err)`.
---@param fn function
---@param ... any
---@return boolean success
---@return any|nil result
---@return string|nil error
function M.safe_call(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then
    return true, result, nil
  end
  return false, nil, tostring(result)
end

---@param bufnr integer
---@return boolean valid
---@return string|nil error
local function validate_buffer(bufnr)
  if type(bufnr) ~= "number" then
    return false, string.format("Invalid buffer type: expected number, got %s", type(bufnr))
  end
  if bufnr < 0 then
    return false, string.format("Invalid buffer number: %d (must be >= 0)", bufnr)
  end
  if not api.nvim_buf_is_valid(bufnr) then
    return false, string.format("Buffer %d is not valid or has been deleted", bufnr)
  end
  return true, nil
end

---@param winnr integer
---@return boolean valid
---@return string|nil error
local function validate_window(winnr)
  if type(winnr) ~= "number" then
    return false, string.format("Invalid window type: expected number, got %s", type(winnr))
  end
  if winnr < 0 then
    return false, string.format("Invalid window number: %d (must be >= 0)", winnr)
  end
  if not api.nvim_win_is_valid(winnr) then
    return false, string.format("Window %d is not valid or has been closed", winnr)
  end
  return true, nil
end

---@param bufnr integer
---@return boolean valid
function M.is_valid_buffer(bufnr)
  return type(bufnr) == "number" and bufnr >= 0 and api.nvim_buf_is_valid(bufnr)
end

---@param winnr integer
---@return boolean valid
function M.is_valid_window(winnr)
  return type(winnr) == "number" and winnr >= 0 and api.nvim_win_is_valid(winnr)
end

---@param bufnr integer
---@param start integer 0-indexed, inclusive
---@param end_ integer 0-indexed, exclusive (-1 for end of buffer)
---@param strict_indexing boolean
---@return boolean success
---@return string[]|nil lines
---@return string|nil error
function M.buf_get_lines(bufnr, start, end_, strict_indexing)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  if type(start) ~= "number" or type(end_) ~= "number" then
    return false, nil, "Start and end must be numbers"
  end
  return M.safe_call(api.nvim_buf_get_lines, bufnr, start, end_, strict_indexing)
end

---@param bufnr integer
---@return boolean success
---@return integer|nil count
---@return string|nil error
function M.buf_line_count(bufnr)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  return M.safe_call(api.nvim_buf_line_count, bufnr)
end

---@param bufnr integer
---@param name string
---@return boolean success
---@return any|nil value
---@return string|nil error
function M.buf_get_option(bufnr, name)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  if type(name) ~= "string" or name == "" then
    return false, nil, "Option name must be a non-empty string"
  end
  return M.safe_call(api.nvim_get_option_value, name, { buf = bufnr })
end

---@param bufnr integer
---@param name string
---@param value any
---@return boolean success
---@return nil result
---@return string|nil error
function M.buf_set_option(bufnr, name, value)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  if type(name) ~= "string" or name == "" then
    return false, nil, "Option name must be a non-empty string"
  end
  return M.safe_call(api.nvim_set_option_value, name, value, { buf = bufnr })
end

---@param bufnr integer
---@param ns_id integer
---@param line integer 0-indexed
---@param col integer 0-indexed
---@param opts table
---@return boolean success
---@return integer|nil id
---@return string|nil error
function M.buf_set_extmark(bufnr, ns_id, line, col, opts)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  if type(ns_id) ~= "number" then return false, nil, "Namespace ID must be a number" end
  if type(line) ~= "number" or line < 0 then return false, nil, "Line must be a non-negative number" end
  if type(col) ~= "number" or col < 0 then return false, nil, "Column must be a non-negative number" end
  if type(opts) ~= "table" then return false, nil, "Options must be a table" end
  return M.safe_call(api.nvim_buf_set_extmark, bufnr, ns_id, line, col, opts)
end

---Extmark setter that clamps/validates `col_start`/`col_end` against
---`line_content`'s length before creating the extmark, so callers
---highlighting many ranges per line don't need to re-fetch/re-validate it.
---@param bufnr integer
---@param ns_id integer
---@param line integer 0-indexed
---@param col_start integer 0-indexed, byte offset
---@param col_end integer 0-indexed, byte offset, exclusive
---@param hl_group any
---@param line_content string
---@param priority? integer default 100
---@return boolean success
---@return integer|nil id
---@return string|nil error
function M.set_extmark(bufnr, ns_id, line, col_start, col_end, hl_group, line_content, priority)
  if type(line_content) ~= "string" then
    return false, nil, "Missing line content"
  end
  local line_length = #line_content
  if type(col_start) ~= "number" or col_start < 0 or col_start > line_length then
    return false, nil, string.format("col_start %s out of range (line length: %d)", tostring(col_start), line_length)
  end
  if type(col_end) ~= "number" or col_end < col_start or col_end > line_length then
    return false, nil,
      string.format("col_end %s out of range (line length: %d, col_start: %d)", tostring(col_end), line_length, col_start)
  end
  return M.buf_set_extmark(bufnr, ns_id, line, col_start, {
    end_col = col_end,
    hl_group = hl_group,
    priority = priority or 100,
  })
end

---@param bufnr integer
---@param ns_id integer
---@param line_start integer 0-indexed, inclusive
---@param line_end integer 0-indexed, exclusive
---@return boolean success
---@return nil result
---@return string|nil error
function M.buf_clear_namespace(bufnr, ns_id, line_start, line_end)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  if type(ns_id) ~= "number" then return false, nil, "Namespace ID must be a number" end
  return M.safe_call(api.nvim_buf_clear_namespace, bufnr, ns_id, line_start, line_end)
end

---@param winnr integer
---@param name string
---@return boolean success
---@return any|nil value
---@return string|nil error
function M.win_get_option(winnr, name)
  local valid, err = validate_window(winnr)
  if not valid then return false, nil, err end
  if type(name) ~= "string" or name == "" then
    return false, nil, "Option name must be a non-empty string"
  end
  return M.safe_call(api.nvim_get_option_value, name, { win = winnr })
end

---@param winnr integer
---@param name string
---@param value any
---@return boolean success
---@return nil result
---@return string|nil error
function M.win_set_option(winnr, name, value)
  local valid, err = validate_window(winnr)
  if not valid then return false, nil, err end
  if type(name) ~= "string" or name == "" then
    return false, nil, "Option name must be a non-empty string"
  end
  return M.safe_call(api.nvim_set_option_value, name, value, { win = winnr })
end

---@param winnr integer
---@return boolean success
---@return integer|nil bufnr
---@return string|nil error
function M.win_get_buf(winnr)
  local valid, err = validate_window(winnr)
  if not valid then return false, nil, err end
  return M.safe_call(api.nvim_win_get_buf, winnr)
end

---@param winnr integer
---@param force boolean
---@return boolean success
---@return nil result
---@return string|nil error
function M.win_close(winnr, force)
  local valid, err = validate_window(winnr)
  if not valid then return false, nil, err end
  return M.safe_call(api.nvim_win_close, winnr, force)
end

---@param bufnr integer
---@param opts? table
---@return boolean success
---@return nil result
---@return string|nil error
function M.buf_delete(bufnr, opts)
  local valid, err = validate_buffer(bufnr)
  if not valid then return false, nil, err end
  opts = opts or {}
  if type(opts) ~= "table" then return false, nil, "Options must be a table" end
  return M.safe_call(api.nvim_buf_delete, bufnr, opts)
end

---Retry `fn` up to `max_retries` times when the failure looks
---handle-related (an "invalid"/"closed" error), giving up immediately on
---any other kind of error.
---@param fn function
---@param max_retries integer
---@param ... any
---@return boolean success
---@return any|nil result
---@return string|nil error
function M.with_retry(fn, max_retries, ...)
  local args = { ... }
  local argc = select("#", ...)

  for attempt = 1, max_retries do
    local success, result, err = M.safe_call(fn, unpack(args, 1, argc))
    if success then
      return true, result, nil
    end
    if err and not err:match("invalid") and not err:match("closed") then
      return false, nil, err
    end
    if attempt < max_retries then
      vim.wait(10)
    end
  end

  return false, nil, "Max retries exceeded"
end

return M
