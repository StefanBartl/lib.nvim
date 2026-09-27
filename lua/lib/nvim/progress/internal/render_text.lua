---@module 'lib.nvim.progress.internal.render_text'
---@brief Shared "title + text (current/total)" formatter for text-based progress styles.
---@description
--- Identical logic was duplicated verbatim in `styles/statusline.lua` and
--- `styles/notify.lua`; extracted here before `styles/echo.lua` made it a
--- third copy of the same body -- the exact duplication class
--- `lib.nvim.dev.duplicates` looks for across sibling repos, this time
--- inside one repo's own sibling files.

require("lib.nvim.progress.@types")

---@param spec Lib.Progress.Spec
---@return string
local function render_text(spec)
  local parts = {}
  if spec.text and spec.text ~= "" then
    parts[#parts + 1] = spec.text
  end
  if type(spec.current) == "number" then
    if type(spec.total) == "number" and spec.total > 0 then
      parts[#parts + 1] = string.format("(%d/%d)", spec.current, spec.total)
    else
      parts[#parts + 1] = string.format("(%d)", spec.current)
    end
  end
  return spec.title .. table.concat(parts, " ")
end

return render_text
