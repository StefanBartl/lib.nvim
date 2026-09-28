---@module 'lib.nvim.ui.kit.presets'
---@brief Canonical "box shape" vocabulary shared by every chip-ish feature in
---this plugin (`lib.nvim.ui.kit.chip`, `ui.context`'s sticky-scope chips,
---`ui.tabline`'s tab-chip boundary style, `ui.statusline`'s module
---separators) and by third-party consumers (sessions.nvim, casedesk.nvim).
---@description
---Three presets, one vocabulary everywhere:
---  - `"classic"`      -- no box, plain colored text
---  - `"chip"`         -- flat, square-cornered block
---  - `"rounded_chip"` -- bordered capsule
---
---A consumer may keep extra options of its own outside these three
---(`ui.tabline`'s `"divider"`, `ui.statusline`'s `"arrow"`) -- `normalize()`
---only touches the shared vocabulary and its deprecated aliases below,
---passing anything else through unchanged.
---
---Every name each system used before this module existed keeps working:
---`normalize()` maps it to the new canonical one and warns once per distinct
---old value per session, rather than breaking an existing config.

local M = {}

---@alias Lib.UI.Kit.Preset "classic"|"chip"|"rounded_chip"

---@type Lib.UI.Kit.Preset[]
M.PRESETS = { "classic", "chip", "rounded_chip" }

---Old name -> canonical preset. Collects every alias actually shipped by a
---consumer before this module existed:
---`lib.nvim.ui.kit.chip`
---(`"text"`/`"rect"`/`"rounded"`), `ui.tabline.styles`
---(`"square"`/`"rounded"`), `ui.statusline`
---separators (`"default"`/`"round"`/`"block"`).
---@type table<string, Lib.UI.Kit.Preset>
local ALIASES = {
  text = "classic",
  rect = "chip",
  square = "chip",
  block = "chip",
  rounded = "rounded_chip",
  round = "rounded_chip",
  default = "rounded_chip",
}

---@param value any
---@return boolean
function M.is_preset(value)
  return type(value) == "string" and vim.tbl_contains(M.PRESETS, value)
end

---Normalize a shape/style value onto the three canonical presets. A value
---that is already canonical, or not recognized as an old alias at all (a
---caller's own extra option, e.g. `ui.tabline`'s `"divider"`), is returned
---unchanged.
---@param value any
---@param who? string  caller name for the deprecation message, e.g. "lib.nvim.ui.kit.chip"
---@return any
function M.normalize(value, who)
  if M.is_preset(value) then
    return value
  end
  local canonical = type(value) == "string" and ALIASES[value]
  if canonical then
    vim.notify_once(
      ("%s: shape/style %q is deprecated, use %q instead"):format(
        who or "lib.nvim.ui.kit.presets",
        value,
        canonical
      ),
      vim.log.levels.WARN
    )
    return canonical
  end
  return value
end

return M
