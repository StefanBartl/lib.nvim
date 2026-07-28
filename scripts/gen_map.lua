---@module 'scripts.gen_map'
--- CLI entry point for the lib.nvim module map.
---
---   nvim --headless -l scripts/gen_map.lua           # regenerate artifacts
---   nvim --headless -l scripts/gen_map.lua --check    # verify, write nothing
---
---   nvim --headless -l scripts/gen_map.lua --check --lenient
---   nvim --headless -l scripts/gen_map.lua --full     # + LuaLS enrichment
---
--- Thin on purpose: everything that isn't lib.nvim's own layout lives in
--- `lib.nvim.docmap.cli`, so another plugin embedding lib.nvim reuses this
--- exact file verbatim — only `docmap.config` (or its own equivalent) needs
--- to change. See `docmap/README.md` § "Reusing docmap in another plugin".

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

local opts = require("lib.nvim.docmap.config")(root)
local code = require("lib.nvim.docmap.cli").run(opts, _G.arg or {})
vim.cmd("cq " .. code)
