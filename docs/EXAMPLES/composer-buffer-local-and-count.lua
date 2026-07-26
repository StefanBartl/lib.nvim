-- docs/EXAMPLES/composer-buffer-local-and-count.lua
--
-- Module:   lib.nvim.usercmd.composer
-- Scenario: two command-registration options beyond the plain global verb,
--           both opt-in and both single command-level settings (matching
--           `nvim_create_user_command`'s own bang/range/count, which are one
--           setting per command, not one per route):
--             spec.buffer  -- register via nvim_buf_create_user_command
--             spec.count   -- accept a `:N Verb` count prefix

local composer = require("lib.nvim.usercmd.composer")

-- 1. BUFFER-LOCAL -- `spec.buffer = true` registers for the CURRENT buffer
-- (or pass an explicit bufnr). Typical use: a per-filetype command that
-- only makes sense in buffers of that type, registered from a FileType
-- autocmd. Re-registering (the autocmd firing again for the same buffer)
-- is safe -- it just overwrites, same as the global form.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    composer.verb("TableView", {
      buffer = true,
      desc = "Render the table under the cursor",
      default = function(ctx)
        require("markdown.tableview").open()
      end,
    })
  end,
})

-- 2. COUNT PREFIX -- `spec.count = 0` (or a specific route's `route.count`)
-- accepts `:N Verb`, surfaced as `ctx.range.count`. Without it, Neovim
-- silently rejects a count prefix on a command that never opted in.
composer.verb("File", {
  count = 0,
  routes = {
    {
      path = { "next" },
      desc = "Cycle to the next file (optionally N at a time)",
      run = function(ctx)
        local n = ctx.range.count > 0 and ctx.range.count or 1
        require("fileops").cycle("next", n)
      end,
    },
    {
      path = { "prev" },
      desc = "Cycle to the previous file (optionally N at a time)",
      run = function(ctx)
        local n = ctx.range.count > 0 and ctx.range.count or 1
        require("fileops").cycle("prev", n)
      end,
    },
  },
})
-- :File next     -> ctx.range.count == 0  -> falls back to 1
-- :3File next    -> ctx.range.count == 3  -> cycles 3 files forward
