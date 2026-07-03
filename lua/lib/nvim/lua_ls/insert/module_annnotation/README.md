## Example usage (fully typed, LuaLS autocomplete):

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

Properties of the solution:
* optional passing of `bufnr`, `row`, `col`
* no arguments → current buffer + current cursor
* an explicit position fully overrides the cursor
* cleanly separated types for LuaLS suggestions
* works with non-active buffers without an implicit window dependency
