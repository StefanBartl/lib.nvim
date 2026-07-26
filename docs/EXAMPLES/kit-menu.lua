-- docs/EXAMPLES/kit-menu.lua
--
-- Module:   lib.nvim.ui.kit.menu (lib.nvim.ui.kit.menu)
-- Scenario: a cursor-anchored action list -- each item pairs a label with
--           a callback, and picking an item just runs that callback. This
--           is the "right-click context menu" shape: no on_select
--           dispatch to write yourself, each item already knows what it
--           does.

local kit = require("lib.nvim.ui.kit")

kit.menu({
  title = "Actions",
  items = {
    {
      label = "Rename",
      action = function()
        require("myplugin").rename_under_cursor()
      end,
    },
    {
      label = "Delete",
      action = function()
        require("myplugin").delete_under_cursor()
      end,
    },
    {
      label = "Copy path",
      action = function()
        vim.fn.setreg("+", vim.api.nvim_buf_get_name(0))
      end,
    },
  },
})

-- Bind it to a keymap for a real "context menu on demand" feel -- opens
-- anchored at the cursor by default (`relative = "cursor"`), so it behaves
-- like a native right-click menu even though it was triggered from the
-- keyboard:
vim.keymap.set("n", "<leader>m", function()
  kit.menu({
    items = {
      { label = "Go to definition", action = vim.lsp.buf.definition },
      { label = "Rename symbol", action = vim.lsp.buf.rename },
      { label = "Show references", action = vim.lsp.buf.references },
    },
  })
end, { desc = "Open the LSP action menu" })
