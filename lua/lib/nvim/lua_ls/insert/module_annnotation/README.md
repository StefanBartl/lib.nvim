## Beispielverwendungen (vollständig typisiert, LuaLS-autocomplete):

```lua
require("lib.nvim.lua_ls.insert.module_annotation")()
```

```lua
require("lib.nvim.lua_ls.insert.module_annotation")({
  bufnr = 3,
})
```

```lua
require("lib.nvim.lua_ls.insert.module_annotation")({
  bufnr = 3,
  row = 0,
})
```

```lua
require("lib.nvim.lua_ls.insert.module_annotation")({
  bufnr = 3,
  row = 5,
  col = 2,
})
```

Eigenschaften der Lösung:
* optionale Übergabe von `bufnr`, `row`, `col`
* keine Argumente → aktueller Buffer + aktueller Cursor
* explizite Position überschreibt Cursor vollständig
* sauber getrennte Typen für LuaLS-Suggestions
* kompatibel mit nicht-aktiven Buffern ohne implizite Fensterabhängigkei
