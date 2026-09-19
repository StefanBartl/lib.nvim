-- TESTS/icons_spec.lua — lib.nvim.ui.icons
--
-- The in-house icon table and its lookup order: exact file name, then the
-- longest matching extension, then the filetype, then the generic default.
-- The Nerd Font gate replaces the glyph with a fallback when no font was
-- declared; nvim-web-devicons is asked first only when it is loaded and
-- `prefer_plugin` is on (a stub stands in for it here).

return function(H)
  local eq = H.eq
  local ok = H.ok

  local icons = require("lib.nvim.ui.icons")
  local data = require("lib.nvim.ui.icons.data")

  local had_nerd = vim.g.have_nerd_font
  vim.g.have_nerd_font = true
  local saved_plugin = package.loaded["nvim-web-devicons"]
  package.loaded["nvim-web-devicons"] = nil
  icons.reset()

  -- ------------------------------------------------------------ the table
  local c = icons.counts()
  ok(c.extensions >= 100, "icons: at least 100 extensions (" .. c.extensions .. ")")
  ok(c.filenames >= 50, "icons: at least 50 file names (" .. c.filenames .. ")")
  ok(c.filetypes >= 100, "icons: at least 100 filetypes (" .. c.filetypes .. ")")
  ok(
    data.by_extension.lua ~= nil and data.by_extension.lua.color:match("^#%x%x%x%x%x%x$") ~= nil,
    "icons: lua entry with a hex colour"
  )

  -- ------------------------------------------------------------ lookup order
  eq(icons.lookup("init.lua").name, data.by_extension.lua.name, "lookup: extension")
  eq(
    icons.lookup("/some/dir/init.lua").name,
    data.by_extension.lua.name,
    "lookup: full path takes the base name"
  )
  eq(
    icons.lookup("package.json").name,
    data.by_filename["package.json"].name,
    "lookup: exact file name wins"
  )
  eq(icons.lookup(".gitignore").name, data.by_filename[".gitignore"].name, "lookup: dotfile name")
  eq(
    icons.lookup("archive.tar.gz").name,
    data.by_extension["gz"].name,
    "lookup: last extension when the longer one is unknown"
  )
  eq(icons.lookup("thing.unknownext"), nil, "lookup: nil when nothing matches")
  eq(icons.lookup(""), nil, "lookup: empty name")
  -- Fix: the extension loop is capped (every real entry is at most two
  -- dots deep) instead of walking every dot in the name -- a name with
  -- many dots must still terminate and correctly report no match rather
  -- than paying O(dots) sub()/find() passes, each over the still mostly
  -- uncut remainder.
  eq(
    icons.lookup("x." .. string.rep("y.", 30) .. "unknownext"),
    nil,
    "lookup: many dots -> no match, does not hang"
  )
  eq(
    icons.lookup("Makefile").name,
    data.by_extension.makefile.name,
    "lookup: bare name via the extension table"
  )
  eq(icons.lookup("LICENSE").name, data.by_extension.license.name, "lookup: LICENSE -> license")
  eq(
    icons.by_filetype("python") and icons.by_filetype("python").name,
    data.by_extension.py.name,
    "by_filetype: python"
  )

  -- ------------------------------------------------------------ get()
  local glyph, color, name = icons.get("main.rs")
  eq(glyph, data.by_extension.rs.icon, "get: glyph from the table")
  eq(color, data.by_extension.rs.color, "get: colour from the table")
  eq(name, data.by_extension.rs.name, "get: name from the table")

  local _, _, ft_name = icons.get("noext", "typescript")
  eq(ft_name, data.by_filetype.typescript.name, "get: filetype as the last resort")

  glyph, color = icons.get("whatever.zzz")
  eq(glyph, data.default.icon, "get: generic default when unknown")
  eq(color, data.default.color, "get: default colour")
  eq(icons.get("whatever.zzz", nil, { default = false }), nil, "get: default = false yields nil")

  -- ------------------------------------------------------------ nerd font gate
  vim.g.have_nerd_font = false
  glyph = icons.get("main.rs")
  eq(glyph, "", "get: no Nerd Font -> empty fallback")
  glyph = icons.get("main.rs", nil, { fallback = "*" })
  eq(glyph, "*", "get: no Nerd Font -> given fallback")
  vim.g.have_nerd_font = true

  -- ------------------------------------------------------------ plugin first
  package.loaded["nvim-web-devicons"] = {
    get_icon_color = function(fname, ext)
      if fname == "main.rs" or ext == "rs" then
        return "P", "#123456"
      end
      return nil
    end,
  }
  icons.reset()
  glyph, color, name = icons.get("main.rs")
  eq(glyph, "P", "get: plugin answer wins when loaded")
  eq(color, "#123456", "get: plugin colour")
  -- Fix: `name` is the entry's stable, highlight-group-naming identifier
  -- (see data.lua) -- the plugin path used to set it to the raw file
  -- name, so every distinct FILE (not extension) ever queried this way
  -- minted its own never-reclaimed highlight group via hl_group().
  eq(name, "rs", "get: plugin path names the entry after the extension, not the file")
  local _, _, name2 = icons.get("some_other_unique_file_12345.rs")
  eq(
    name2,
    name,
    "get: two different files sharing an extension share one name (bounded hl_group namespace)"
  )
  glyph = icons.get("main.rs", nil, { prefer_plugin = false })
  eq(glyph, data.by_extension.rs.icon, "get: prefer_plugin = false uses the table")
  glyph = icons.get("init.lua")
  eq(glyph, data.by_extension.lua.icon, "get: table when the plugin has no answer")

  -- ------------------------------------------------------------ hl group
  local group = icons.hl_group("Lua", "#51a0cf")
  eq(group, "LibIcon_Lua", "hl_group: name")
  local hl = vim.api.nvim_get_hl(0, { name = group })
  eq(hl.fg, 0x51a0cf, "hl_group: colour applied")

  package.loaded["nvim-web-devicons"] = saved_plugin
  icons.reset()
  vim.g.have_nerd_font = had_nerd
end
