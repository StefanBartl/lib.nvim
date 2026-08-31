---@module 'lib.nvim.hover.registry'
--- Sources and previews a plugin contributes to the hover.
---@description
--- **The problem.** The hover framework knows how to find a path under the
--- cursor, classify it and draw a float around whatever comes back. It must
--- not know *who* can read a `#heading` out of a markdown file, or who can
--- turn a `.png` into pixels. Those are plugin capabilities, and a library
--- that requires plugins to do its job has the dependency backwards: install
--- lib.nvim on its own and half of it would be missing.
---
--- **The shape.** Plugins register into the library rather than the library
--- reaching for plugins. Two kinds of contribution, because the hover asks
--- two separate questions:
---
--- ```lua
--- hover.register("markdown", {
---   -- "what is under the cursor?" -- returns a raw target string, or nil.
---   -- Tried in registration order, before the built-in bare-path source.
---   sources = {
---     function(bufnr, row, col) return link_scan_at(bufnr, row, col) end,
---   },
---   -- "how do I preview a target of this type?" -- keyed by the type
---   -- `classify` produced. Overrides the built-in preview for that type.
---   previews = {
---     anchor = function(target, opts, bufnr) return section_of(target, bufnr) end,
---   },
--- })
--- ```
---
--- **Why sources are ordered and previews are not.** Several sources can
--- match the same cursor position — a markdown link and a bare path both
--- exist on `[a](./b.png)` — so "first match wins" needs an order, and
--- registration order is the only one a library can honestly offer. A preview
--- answers for exactly one type, so a second registration for that type is a
--- replacement, not a competitor, and needs no ordering rule.
---
--- **Why a plugin name is required.** Re-registering under the same name
--- replaces that plugin's contribution instead of stacking a second copy on
--- top: `setup()` running twice (a reload, a `:Lazy reload`) must not make
--- every source fire twice.

local M = {}

---@class Lib.Hover.Contribution
---@field sources? (fun(bufnr: integer, row: integer, col: integer): string|nil, table|nil)[] # Each returns the raw target under the cursor, or nil. A second return value is merged into the source record (e.g. `col`/`col_end` for highlighting).
---@field previews? table<string, fun(target: Lib.Hover.Target, opts: Lib.Hover.PreviewOpts, bufnr: integer): Lib.Hover.Content|nil>

---@type { name: string, fn: function }[]
local sources = {}

---@type table<string, { name: string, fn: function }>
local previews = {}

--- Register a plugin's hover contributions.
---@param name string plugin name; re-registering replaces its previous entry
---@param contribution Lib.Hover.Contribution
---@return nil
function M.register(name, contribution)
  if type(name) ~= "string" or name == "" then
    return
  end
  contribution = contribution or {}

  -- Drop this plugin's previous sources before adding the new ones, so a
  -- second setup() replaces rather than duplicates.
  local kept = {}
  for _, entry in ipairs(sources) do
    if entry.name ~= name then
      kept[#kept + 1] = entry
    end
  end
  sources = kept

  for _, fn in ipairs(contribution.sources or {}) do
    if type(fn) == "function" then
      sources[#sources + 1] = { name = name, fn = fn }
    end
  end

  for target_type, fn in pairs(contribution.previews or {}) do
    if type(fn) == "function" then
      previews[target_type] = { name = name, fn = fn }
    end
  end
end

--- Ask every registered source, in registration order, for the target under
--- the cursor. The first one that answers wins.
---@param bufnr integer
---@param row integer 1-based
---@param col integer 0-based
---@return string|nil target
---@return table|nil extra fields the source wants carried on the record
function M.source_at(bufnr, row, col)
  for _, entry in ipairs(sources) do
    -- `pcall`: a broken contribution from one plugin must not take the hover
    -- down for every other.
    local ok, target, extra = pcall(entry.fn, bufnr, row, col)
    if ok and type(target) == "string" and target ~= "" then
      return target, extra
    end
  end
  return nil
end

--- The registered preview for `target_type`, if a plugin claimed it.
---@param target_type string
---@return function|nil
function M.preview_for(target_type)
  local entry = previews[target_type]
  return entry and entry.fn or nil
end

--- Whether any source is registered. `markdown.hover`'s link scanning is the
--- usual one; without it the hover still works from bare paths alone.
---@return boolean
function M.has_sources()
  return #sources > 0
end

--- Drop every registration. Tests only.
---@return nil
function M.reset()
  sources, previews = {}, {}
end

return M
