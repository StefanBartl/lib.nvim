# `lib.nvim.health`

Small helpers for writing a plugin's own `:checkhealth` implementation.

```
lib.nvim.health/
├── init.lua       -- version_ok, check_require
└── @types/        -- LuaLS types (Lib.Nvim.Health)
```

Entry point is `require("lib.nvim.health")`.

## Why these two

Both were literal, byte-identical duplicates found by
`docs/ROADMAP/tools/duplicate_functions.py`:

* **`version_ok(min)`** — this repo's own `lib.health`, documentation.nvim,
  and runtime-analysis.nvim each carried the same six lines checking
  `vim.version()` against a `{major, minor, patch}` floor.
* **`check_require(mod, label, level)`** — dap.nvim and debugging.nvim each
  had the same function reporting one required module through
  `vim.health.{ok,warn,info}`.

## API

```lua
local health = require("lib.nvim.health")

local MIN_NVIM = { 0, 10, 0 }

function M.check()
  vim.health.start("myplugin: environment")
  if health.version_ok(MIN_NVIM) then
    vim.health.ok("Neovim version OK")
  else
    vim.health.warn("Neovim 0.10+ recommended")
  end

  health.check_require("lib.nvim.notify", "lib.nvim", "warn")
  health.check_require("some.optional.dep", "optional dep", "info")
end
```

`check_require`'s `level` controls how loud a *missing* module is reported:
`"warn"` for something the plugin can't work without, `"info"` for an
optional extra that just degrades a feature.
