---@module 'lib.nvim.treesitter.regions'
--- Capture name -> the ranges of a buffer, fail-open.
---
--- A feature that should only look at part of a buffer (spell-check the `@spell` regions, skip `@string`s,
--- hand `@comment`s to a linter) asks the language's query which nodes carry a capture and gets their
--- ranges. When the buffer has no parser, no such query, or the query does not define the capture at all,
--- there is no region information: `collect` returns `nil` plus a reason and the caller keeps working on
--- the WHOLE buffer instead of silently dropping text (fail-open: never throws, never invents regions).
---
--- Not `lib.nvim.treesitter.guard` (a filetype allowlist) and not `parser_policy` (which parsers to install).
--- Generalised from `language.nvim`'s `spell/core/regions.lua`.
---
--- ```lua
--- local regions = require("lib.nvim.treesitter.regions")
---
--- local found, why = regions.collect(bufnr, { "spell", "nospell" })
--- if not found then
---   -- no parser / query / capture: treat everything as in scope (`why` says which)
--- else
---   regions.contains_pos(found.spell, lnum, col)   -- is (1-based lnum, col) inside an @spell node?
--- end
--- ```

local M = {}

---@class Lib.Ts.Region
---@field [1] integer  # start row (0-based)
---@field [2] integer  # start column (byte, 0-based)
---@field [3] integer  # end row (0-based)
---@field [4] integer  # end column (byte, exclusive)
---@field start_byte integer  # byte offset of the start in the buffer (0-based)
---@field end_byte integer    # byte offset of the end in the buffer (exclusive)

---@class Lib.Ts.RegionsOpts
---@field query? string   # Query group (default "highlights"; "injections", "locals" ...).
---@field lang? string    # Language (default: from the buffer's filetype).
---@field first_row? integer  # Only nodes from this 0-based row on (default 0).
---@field last_row? integer   # ... up to this row, exclusive (default: the end).

---@alias Lib.Ts.RegionsReason "no_filetype"|"no_parser"|"no_query"|"capture_not_defined"|"parse_failed"|"invalid_buffer"

---Ranges of the nodes carrying each requested capture, keyed by capture name (without `@`).
---
---Returns `nil, reason` when the buffer cannot say (see the module description). When at least one requested
---capture exists in the query the result holds an entry for every one the query defines: a capture that
---matched nothing here is an EMPTY list, one the query does not define is absent from the map.
---@param bufnr integer
---@param captures string[]  # Capture names without the leading `@`.
---@param opts? Lib.Ts.RegionsOpts
---@return table<string, Lib.Ts.Region[]>|nil found
---@return Lib.Ts.RegionsReason|nil reason
function M.collect(bufnr, captures, opts)
  opts = opts or {}
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "invalid_buffer"
  end

  local lang = opts.lang
  if not lang then
    local ok_ft, ft = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
    if not ok_ft or ft == "" then
      return nil, "no_filetype"
    end
    lang = vim.treesitter.language.get_lang(ft) or ft
  end

  local ok_p, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok_p or not parser then
    return nil, "no_parser"
  end

  local ok_q, query = pcall(vim.treesitter.query.get, lang, opts.query or "highlights")
  if not ok_q or not query then
    return nil, "no_query"
  end

  local wanted = {}
  for _, name in ipairs(captures) do
    wanted[name] = true
  end
  local defined, defined_any = {}, false
  for _, name in ipairs(query.captures) do
    if wanted[name] then
      defined[name] = true
      defined_any = true
    end
  end
  if not defined_any then
    return nil, "capture_not_defined"
  end

  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or type(trees) ~= "table" then
    return nil, "parse_failed"
  end

  ---@type table<string, Lib.Ts.Region[]>
  local found = {}
  for name in pairs(defined) do
    found[name] = {}
  end

  local first = opts.first_row or 0
  local last = opts.last_row or -1
  for _, tree in ipairs(trees) do
    local ok_iter = pcall(function()
      for id, node in query:iter_captures(tree:root(), bufnr, first, last) do
        local bucket = found[query.captures[id]]
        if bucket then
          local sr, sc, sb, er, ec, eb = node:range(true)
          bucket[#bucket + 1] = { sr, sc, er, ec, start_byte = sb, end_byte = eb }
        end
      end
    end)
    if not ok_iter then
      return nil, "parse_failed"
    end
  end
  return found, nil
end

---Is the 0-based (row, col) inside any of `ranges` (end exclusive)?
---@param ranges Lib.Ts.Region[]
---@param row integer
---@param col integer
---@return boolean
function M.contains(ranges, row, col)
  for _, r in ipairs(ranges) do
    local sr, sc, er, ec = r[1], r[2], r[3], r[4]
    local after_start = row > sr or (row == sr and col >= sc)
    local before_end = row < er or (row == er and col < ec)
    if after_start and before_end then
      return true
    end
  end
  return false
end

---Is the 1-based (lnum, byte col) inside any of `ranges`?
---@param ranges Lib.Ts.Region[]
---@param lnum integer
---@param col integer
---@return boolean
function M.contains_pos(ranges, lnum, col)
  return M.contains(ranges, lnum - 1, col - 1)
end

---Is the byte offset (0-based, from the start of the buffer) inside any of `ranges`?
---@param ranges Lib.Ts.Region[]
---@param byte integer
---@return boolean
function M.contains_byte(ranges, byte)
  for _, r in ipairs(ranges) do
    if byte >= r.start_byte and byte < r.end_byte then
      return true
    end
  end
  return false
end

---The `{ start_byte, end_byte }` pairs of `ranges` (0-based, end exclusive), for a caller that works on a
---string of the whole buffer rather than on rows and columns.
---@param ranges Lib.Ts.Region[]
---@return { [1]: integer, [2]: integer }[]
function M.byte_ranges(ranges)
  local out = {}
  for _, r in ipairs(ranges) do
    out[#out + 1] = { r.start_byte, r.end_byte }
  end
  return out
end

return M
