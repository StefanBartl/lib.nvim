-- docs/EXAMPLES/autocmd-dispatcher-filetype.lua
--
-- Module:   lib.nvim.autocmd.dispatcher (+ its FileType wrapper)
-- Scenario: replace N hand-rolled `FileType` autocmds -- one per language
--           server setup, each with its own guard + lazy require -- with one
--           registry: one real autocmd, deterministic ordering, lazy-loaded
--           modules, and a per-buffer `once` so re-entering the same buffer's
--           filetype twice doesn't redo setup.
--
-- Call this once, e.g. from your config's init or a plugin's setup().

local dispatcher = require("lib.nvim.autocmd.dispatcher")

local ft = dispatcher.filetype.new({ group = "MyFiletypeDispatcher" })

-- `load` is required (and therefore executed) only the first time "lua"
-- actually matches -- the module's own top-level code does the LSP setup.
ft.register("lua", {
  load = function()
    require("lsp.languages.scripting.lua")
  end,
  priority = 10,
  once = true, -- per buffer, not once-globally
})

-- One registration can cover several filetypes that share a loader --
-- this is ONE registration (shares one once-slot across "c" and "cpp"),
-- which is correct here since a buffer only ever has one of the two.
ft.register({ "c", "cpp" }, {
  load = function()
    require("lsp.languages.systems.c")
  end,
  once = true,
})

-- Glob keys match by prefix/suffix via "*".
ft.register("noice*", {
  load = function()
    require("noice_setup")
  end,
})

-- A handler can also be a plain function, called directly with ctx -- no
-- lazy-require indirection needed for a two-line inline handler.
ft.register("markdown", function(ctx)
  -- ctx.context is the default FileType context: a Lib.Buffer.Context.Ctx.
  if ctx.context:is_normal() then
    vim.notify(("opened a markdown buffer: %d"):format(ctx.buf))
  end
end)

ft.attach() -- creates the single underlying FileType autocmd

-- Introspection, e.g. from a :checkhealth or debug command:
--   ft.stats()  -->  { total_keys = 4, total_handlers = 4, keys = {...}, attached = true }
