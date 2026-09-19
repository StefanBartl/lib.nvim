---@module 'lib.nvim.ui.icons'
--- File icons as data: a glyph, a colour and a name for a file, an
--- extension or a filetype, without a plugin behind it.
---@description
--- Every statusline, tree and picker in this collection wants the same
--- lookup -- "what glyph and colour does `init.lua` get" -- and until now
--- each reached for nvim-web-devicons through its own soft-require and
--- fallback. This module is that lookup as a table: a curated subset of the
--- devicons default set (`data.lua`, ~150 extensions, ~90 file names, the
--- filetype map), resolved in the order devicons uses -- exact file name
--- first, then the longest matching extension, then the filetype -- with
--- the Nerd Font gate of `lib.nvim.ui.nerd_font` applied to the glyph.
---
--- When nvim-web-devicons *is* installed and `prefer_plugin` is on
--- (default), its answer wins, because it knows 500 extensions and this
--- table knows 150. The table is the floor, not a replacement: a consumer
--- gets an icon either way, and one that is not the plugin's replacement
--- character when the plugin is absent.

local M = {}

---@class Lib.UI.Icons.Opts
---@field default? boolean        # true (default): fall back to the generic file icon; false: nil when unknown
---@field fallback? string        # the text used when no Nerd Font is declared (default "")
---@field prefer_plugin? boolean  # true (default): ask nvim-web-devicons first when it is loaded

---@type table|nil  nvim-web-devicons, when loadable
local plugin = nil
local plugin_checked = false

---@internal
---@return table|nil
local function devicons()
  if plugin_checked then
    return plugin
  end
  plugin_checked = true
  local ok, mod = pcall(require, "nvim-web-devicons")
  if ok and type(mod) == "table" and type(mod.get_icon_color) == "function" then
    plugin = mod
  end
  return plugin
end

---Forget whether the plugin was found (for tests, and after a late install).
function M.reset()
  plugin = nil
  plugin_checked = false
end

---@internal
---@return { by_extension: table<string, Lib.UI.Icon>, by_filename: table<string, Lib.UI.Icon>, by_filetype: table<string, Lib.UI.Icon>, default: Lib.UI.Icon }
local function data()
  return require("lib.nvim.ui.icons.data")
end

---The entry for a file name (`init.lua`, `.gitignore`, a full path is fine)
---from this module's own table only: exact name, then the longest matching
---extension. `nil` when nothing matches.
---@param filename string
---@return Lib.UI.Icon|nil
function M.lookup(filename)
  if type(filename) ~= "string" or filename == "" then
    return nil
  end
  local d = data()
  local base = filename:match("([^/\\]+)$") or filename
  local entry = d.by_filename[base] or d.by_filename[base:lower()]
  if entry then
    return entry
  end
  -- Longest extension first: `d.ts` before `ts`, `tar.gz` before `gz`.
  -- Capped at a few segments: every real entry in the table is at most two
  -- dots deep, and without a cap a name with many dots cost one sub()
  -- allocation per dot, each over the still-mostly-uncut remainder -- O(n)
  -- work per dot, O(n^2) total on a name with O(n) dots.
  local rest = base
  for _ = 1, 4 do
    local dot = rest:find(".", 1, true)
    if not dot then
      break
    end
    local ext = rest:sub(dot + 1)
    if ext ~= "" then
      entry = d.by_extension[ext] or d.by_extension[ext:lower()]
      if entry then
        return entry
      end
    end
    rest = ext
  end
  -- A bare name that devicons files under the extension table:
  -- `Makefile` -> `makefile`, `LICENSE` -> `license`, `Dockerfile`.
  if not base:find(".", 1, true) then
    return d.by_extension[base] or d.by_extension[base:lower()]
  end
  return nil
end

---The entry for a filetype from this module's own table, or nil.
---@param filetype string
---@return Lib.UI.Icon|nil
function M.by_filetype(filetype)
  if type(filetype) ~= "string" or filetype == "" then
    return nil
  end
  return data().by_filetype[filetype]
end

---The glyph and colour for `filename` (optionally with `filetype` as the
---last resort): nvim-web-devicons when loaded and preferred, this table
---otherwise, the generic file icon when nothing matches (unless
---`opts.default == false`). The glyph is replaced by `opts.fallback` when
---no Nerd Font is declared.
---@param filename string|nil
---@param filetype string|nil
---@param opts Lib.UI.Icons.Opts|nil
---@return string|nil icon
---@return string|nil color
---@return string|nil name
function M.get(filename, filetype, opts)
  opts = opts or {}
  local entry = nil

  if opts.prefer_plugin ~= false then
    local mod = devicons()
    if mod and filename and filename ~= "" then
      local base = filename:match("([^/\\]+)$") or filename
      local ext = base:match("^.+%.(.+)$")
      local ok, icon, color = pcall(mod.get_icon_color, base, ext, { default = false })
      if ok and icon then
        -- `name` is "devicons' icon name, for highlight-group naming" (see
        -- data.lua) -- a stable per-TYPE identifier, not the file's own
        -- name. Using `base` here named a group after every distinct file
        -- ever queried through the plugin path instead of every distinct
        -- extension, and Neovim has no highlight-group-delete API to
        -- reclaim them: unbounded growth over a session that touches many
        -- files. `ext` (falling back to `base` only for an exact-name
        -- match like `Makefile`, which has none) matches what this
        -- module's own table already uses for the same field.
        entry = { icon = icon, color = color, name = ext or base }
      end
    end
  end

  entry = entry or M.lookup(filename or "") or M.by_filetype(filetype or "")
  if not entry then
    if opts.default == false then
      return nil, nil, nil
    end
    entry = data().default
  end

  local nerd = require("lib.nvim.ui.nerd_font")
  local glyph = entry.icon
  if not nerd.available() then
    glyph = opts.fallback or ""
  end
  return glyph, entry.color, entry.name
end

---A highlight group named after the entry with its colour as foreground,
---created on first use: `LibIcon_<name>`.
---@param name string
---@param color string|nil
---@return string group
function M.hl_group(name, color)
  local group = "LibIcon_" .. (name or "Default"):gsub("[^%w]", "_")
  if color then
    pcall(vim.api.nvim_set_hl, 0, group, { fg = color, default = true })
  end
  return group
end

---How many entries the table holds, per section (for health checks).
---@return { extensions: integer, filenames: integer, filetypes: integer }
function M.counts()
  local d = data()
  local function n(t)
    local c = 0
    for _ in pairs(t) do
      c = c + 1
    end
    return c
  end
  return {
    extensions = n(d.by_extension),
    filenames = n(d.by_filename),
    filetypes = n(d.by_filetype),
  }
end

return M
