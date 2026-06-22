# Usage Examples and Best Practices

@usage
 Basic safe notification from autocommand:
   vim.api.nvim_create_autocmd("TextChanged", {
     callback = function()
       require("lib.nvim.notify").safe.schedule("Text changed!", vim.log.levels.INFO)
     end
   })

 Using deferred notification for debouncing:
   vim.api.nvim_create_autocmd("CursorMoved", {
     callback = function()
       require("lib.nvim.notify").safe.defer("Cursor moved", vim.log.levels.DEBUG, {}, 500)
     end
   })

 Creating a wrapped notifier for repeated use:
   local safe_notify = require("lib.nvim.notify").safe.wrap()
   vim.api.nvim_create_autocmd("BufEnter", {
     callback = function()
       safe_notify("Buffer entered", vim.log.levels.INFO)
     end
   })

 Creating a safe prefixed notifier:
   local notify = require("lib.nvim.notify").safe.create_safe("[MyPlugin]")
   vim.api.nvim_create_autocmd("User", {
     pattern = "MyEvent",
     callback = function()
       notify.info("Event triggered")  -- Automatically safe and prefixed
     end
   })


