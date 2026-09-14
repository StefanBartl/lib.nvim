---@module 'lib.nvim.buffer.apply_edits'
---Apply multiple positional text edits to a buffer safely.
---
---Two hazards a naive "loop over edits, set_text each one" hits:
---
---1. Applying edits top-to-bottom shifts every later edit's row/col once an
---   earlier one changes the line count or a line's length -- a position
---   computed before any edit landed is only valid until the first one runs.
---   Applying bottom-up (highest position first) avoids this: an edit never
---   changes anything above itself.
---2. An edit's position can go stale even bottom-up, if it was computed
---   against a buffer snapshot that something else has since changed.
---   Applying it anyway silently corrupts text at the wrong place. Passing
---   `expect` makes that detectable: the range's current text is compared
---   against it first, and the edit is skipped (not applied) on a mismatch.

local api = vim.api

---Sort edits by position, bottom-up (highest row/col first), keeping each
---edit's original index for reporting.
---@param edits Lib.Buffer.Edit[]
---@return { edit: Lib.Buffer.Edit, index: integer }[]
local function sort_bottom_up(edits)
  local indexed = {}
  for i, edit in ipairs(edits) do
    indexed[i] = { edit = edit, index = i }
  end
  table.sort(indexed, function(a, b)
    if a.edit.start_row ~= b.edit.start_row then
      return a.edit.start_row > b.edit.start_row
    end
    return a.edit.start_col > b.edit.start_col
  end)
  return indexed
end

---Apply one edit; returns whether it was applied and, if not, why.
---@param bufnr integer
---@param edit Lib.Buffer.Edit
---@return boolean applied
---@return string|nil reason
local function apply_one(bufnr, edit)
  if edit.expect ~= nil then
    local ok, current = pcall(
      api.nvim_buf_get_text,
      bufnr,
      edit.start_row,
      edit.start_col,
      edit.end_row,
      edit.end_col,
      {}
    )
    if not ok then
      return false, "out-of-range"
    end
    if table.concat(current, "\n") ~= edit.expect then
      return false, "stale-match"
    end
  end

  local text = edit.text
  if type(text) == "string" then
    text = vim.split(text, "\n", { plain = true })
  end

  local ok = pcall(
    api.nvim_buf_set_text,
    bufnr,
    edit.start_row,
    edit.start_col,
    edit.end_row,
    edit.end_col,
    text
  )
  if not ok then
    return false, "apply-failed"
  end
  return true, nil
end

---Apply `edits` to `bufnr`, bottom-up, with an optional stale-match check
---per edit (via `edit.expect`).
---
---Edits are independent, positional ranges (0-indexed rows, byte columns,
---end-exclusive -- the same convention as `nvim_buf_set_text`/LSP
---`TextEdit`). They must not overlap; overlapping ranges after
---bottom-up sorting have undefined results, same as calling
---`nvim_buf_set_text` twice over the same span.
---@param bufnr integer
---@param edits Lib.Buffer.Edit[]
---@return Lib.Buffer.ApplyEditsResult
local function apply_edits(bufnr, edits)
  local applied, skipped = 0, {}

  for _, item in ipairs(sort_bottom_up(edits)) do
    local ok, reason = apply_one(bufnr, item.edit)
    if ok then
      applied = applied + 1
    else
      skipped[#skipped + 1] = { index = item.index, reason = reason }
    end
  end

  return { applied = applied, skipped = skipped }
end

return apply_edits
