---@module 'lib.nvim.docmap.doccoverage'
--- Documentation coverage (R4): one number instead of three scattered
--- findings. `missing-summary`, `undocumented-param` and
--- `param-name-mismatch` each answer "is this one thing wrong", which is
--- right for `--check` and wrong for "how documented is this tree, and did
--- that number move since last time" — the question `diff.lua` already
--- answers for the require graph and the API surface, and this is the same
--- idea for documentation completeness.
---
--- A function counts as documented when it has a non-empty summary and its
--- declared parameters are fully and correctly named in `@param` lines —
--- exactly the two conditions `missing-summary`/`undocumented-param`/
--- `param-name-mismatch` already check per-function, reused here rather than
--- reimplemented so the aggregate can never quietly disagree with the
--- findings a reader already sees. `@return` is deliberately not part of the
--- definition: unlike a parameter, a function's raw signature carries no
--- count of what it returns, so there is no structural fact to check
--- against — only "did the author write an @return line", which
--- `missing-summary`-style nagging already covers badly enough without a
--- coverage number pretending it is more precise than that.
---
--- `@internal` functions are excluded, the same as all three findings this
--- builds on: an internal function's documentation bar is the author's own,
--- and folding it into a "published API" coverage number would make the
--- number answer a question nobody asked.

local M = {}

---True when `fn`'s declared parameters are fully and correctly documented:
---same count, same names at each position — exactly what
---`undocumented-param` and `param-name-mismatch` each check one half of.
---@param fn Lib.Docmap.FunctionInfo
---@return boolean
local function params_documented(fn)
  local check = require("lib.nvim.docmap.check")
  local declared = check.declared_param_names(fn)

  local doc_params = fn.params
  -- Same colon-method `self` exception `param-name-mismatch` needs: Lua's
  -- implicit sugar means `self` never appears in the raw signature text,
  -- but documenting it explicitly is legitimate LuaCATS style.
  if fn.name:find(":") and doc_params[1] and doc_params[1].name == "self" then
    local shifted = {}
    for i = 2, #doc_params do
      shifted[#shifted + 1] = doc_params[i]
    end
    doc_params = shifted
  end

  local declared_count = 0
  for _, token in ipairs(declared) do
    if token ~= "..." then
      declared_count = declared_count + 1
    end
  end
  if declared_count > #doc_params then
    return false
  end

  for i = 1, math.min(#declared, #doc_params) do
    if declared[i] ~= "..." and declared[i] ~= doc_params[i].name then
      return false
    end
  end
  return true
end

---Aggregate documentation coverage over `ir`: how many published (non-
---`@internal`) functions have both a summary and fully, correctly
---documented parameters.
---@param ir Lib.Docmap.IR
---@return integer documented
---@return integer total
function M.summary(ir)
  local documented, total = 0, 0
  for _, id in ipairs(ir.order) do
    for _, fn in ipairs(ir.nodes[id].functions) do
      if not fn.internal then
        total = total + 1
        local has_summary = fn.summary ~= nil and fn.summary ~= ""
        if has_summary and params_documented(fn) then
          documented = documented + 1
        end
      end
    end
  end
  return documented, total
end

---`M.summary(ir)` rendered as a shields.io-shaped SVG badge — what
---`opts.badge` writes to `coverage.svg`. Split out of `M.summary` so a
---caller that only wants the raw numbers (the CLI's printed line, a future
---Analysis-tab panel) never pulls in `render/badge.lua` for nothing.
---@param ir Lib.Docmap.IR
---@return string svg
function M.badge_svg(ir)
  local badge = require("lib.nvim.docmap.render.badge")
  local documented, total = M.summary(ir)
  local pct = total > 0 and (100 * documented / total) or 0
  return badge.render("doc coverage", ("%.0f%%"):format(pct), badge.color_for(pct))
end

return M
