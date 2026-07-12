---@module 'lib.nvim.ui.kit.theme'
--- Theme / preset engine for lib.nvim.ui.kit.
---
--- A theme is a table of design tokens (border, padding, zindex, highlights, …).
--- Presets are named themes differing mainly in border strength; their highlight
--- groups link to standard groups (NormalFloat / FloatBorder / PmenuSel / …) so
--- the default look is correct in any colorscheme. Callers pass a preset name, a
--- partial override table (deep-merged over the active default), or nil.

local hl = require("lib.nvim.ui.hl")
local config = require("lib.nvim.ui.kit.config")

local M = {}

--- Base tokens; every preset is merged over this.
---@type Lib.UI.Kit.Theme
local BASE = {
  border = "rounded",
  ascii_border = false,
  padding = { x = 1, y = 0 },
  zindex = { base = 50, popup = 50, toast = 70, menu = 60 },
  title_pos = "center",
  dims = { min_w = 20, max_w = 100, min_h = 1, max_h = 30 },
  hl = {
    normal = "NormalFloat",
    border = "FloatBorder",
    title = "FloatTitle",
    selection = "PmenuSel",
    accent = "Special",
    muted = "Comment",
    error = "DiagnosticError",
  },
}

--- Built-in presets (overrides layered onto BASE).
---@type table<string, table>
local BUILTIN = {
  minimal = { border = "none" },
  rounded = { border = "rounded" },
  solid = { border = "single" },
  double = { border = "double" },
  ascii = {
    border = { "+", "-", "+", "|", "+", "-", "+", "|" },
    ascii_border = true,
  },
}

-- Runtime registry (built-ins + user presets) and the active default.
local presets = vim.deepcopy(BUILTIN)
local default_name = config.defaults.default

--- Global highlight groups a theme materializes. winhighlight maps the float's
--- built-in groups onto these; components use the rest via extmarks.
local GROUPS = {
  normal = "KitNormal",
  border = "KitBorder",
  title = "KitTitle",
  selection = "KitSelection",
  accent = "KitAccent",
  muted = "KitMuted",
  error = "KitError",
}

--- Resolve a theme argument to a full token table.
---@param theme? Lib.UI.Kit.ThemeArg
---@return Lib.UI.Kit.Theme
function M.resolve(theme)
  local base = vim.deepcopy(BASE)

  if type(theme) == "string" and presets[theme] then
    return vim.tbl_deep_extend("force", base, presets[theme])
  end

  local active = presets[default_name] or presets.rounded or {}
  local resolved = vim.tbl_deep_extend("force", base, active)

  if type(theme) == "table" then
    resolved = vim.tbl_deep_extend("force", resolved, theme)
  end

  return resolved
end

--- Define the Kit* highlight groups for a resolved theme (idempotent).
---@param resolved Lib.UI.Kit.Theme
local function materialize(resolved)
  for key, group in pairs(GROUPS) do
    local spec = resolved.hl[key]
    local opts = type(spec) == "string" and { link = spec } or spec
    hl.set(group, opts)
  end
end

--- Apply a resolved theme to an open window: materialize its groups and point
--- the float's built-in groups at them via winhighlight.
---@param winid integer
---@param resolved Lib.UI.Kit.Theme
function M.apply(winid, resolved)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  materialize(resolved)
  local winhl = table.concat({
    "NormalFloat:" .. GROUPS.normal,
    "FloatBorder:" .. GROUPS.border,
    "FloatTitle:" .. GROUPS.title,
  }, ",")
  pcall(vim.api.nvim_set_option_value, "winhighlight", winhl, { win = winid })
end

--- Register user presets / change the active default.
---@param opts? Lib.UI.Kit.SetupOpts
function M.setup(opts)
  opts = opts or {}
  if type(opts.presets) == "table" then
    for name, spec in pairs(opts.presets) do
      presets[name] = spec
    end
  end
  if type(opts.default) == "string" and presets[opts.default] then
    default_name = opts.default
  end
  -- Re-materialize the active default so links refresh after a colorscheme
  -- change (set up once).
  if not M._colorscheme_hook then
    M._colorscheme_hook = true
    local group = vim.api.nvim_create_augroup("lib_ui_kit_theme", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = group,
      callback = function()
        pcall(materialize, M.resolve(nil))
      end,
      desc = "lib.nvim.ui.kit: refresh theme highlight groups",
    })
  end
end

--- Names of all registered presets.
---@return string[]
function M.presets()
  local out = {}
  for name in pairs(presets) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

---@return string
function M.default()
  return default_name
end

return M
