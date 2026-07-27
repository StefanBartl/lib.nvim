-- docs/EXAMPLES/docmap-browse.lua
--
-- Module:   lib.nvim.docmap.browse
-- Scenario: navigate the generated module map from inside the editor
--           (`:LibBrowse`) instead of opening the HTML page — a drill-down
--           list over the same edges, with the three things the page cannot
--           do: jump to source, fill the quickfix list, and stay live.
--
-- Not meant to be `dofile`'d standalone: paste the body into your config or
-- a user command inside a running Neovim instance.

-- 1. REGISTER — the commands are opt-in. Requiring lib.nvim.docmap alone
--    never creates one, so two plugins each generating their own map never
--    fight over the same command name.
require("lib.nvim.docmap.command").setup()
-- :LibMap     regenerates / checks the artifacts (the generator)
-- :LibBrowse  reads them (the viewer) -- separate commands on purpose, so a
--             read-only viewer is never one typo away from rewriting files.

-- 2. OPEN — directly, without going through the command.
local browse = require("lib.nvim.docmap.browse")

browse.open({ root = vim.fn.getcwd() })

-- Centered on one module. The name resolves against a declared `@module`, a
-- raw node id, OR the module path a directory's location implies -- which
-- matters because `lua/lib/nvim/fs` has no init.lua and so declares no
-- module, yet `lib.nvim.fs` is exactly what you would type.
browse.open({ root = vim.fn.getcwd(), center = "lib.nvim.fs" })

-- 3. LIVE — installs a watching docmap handle instead of reading the
--    artifact. Costs one full scan up front (~0.65s over lib.nvim) but then
--    re-scans on every write, so the view never goes stale.
--
--    The default is the artifact precisely because that cost is real: 10ms
--    to decode module_map.json vs 650ms to scan is the difference between a
--    window that opens and one that hangs. When the artifact IS stale, the
--    status line says so rather than showing wrong data silently.
browse.open({ root = vim.fn.getcwd(), live = true })

-- 4. KEYS, once open:
--    1..4        structure / deps / calls / types
--    j k         move; the detail pane follows
--    <CR>        descend a level, or follow the edge in deps/calls
--    - <BS>      up a level
--    <C-o> <C-i> back / forward through the visit history
--    h l         direction: incoming / outgoing (deps, calls)
--    + _         depth +/-1 (deps)
--    gd          open the source at the line (closes the browser)
--    gq          send the current list to the quickfix list
--    /           fuzzy jump across every module and function
--    q <Esc>     close

-- 5. A KEYMAP worth having -- "what calls the thing I'm looking at?" without
--    leaving the file:
vim.keymap.set("n", "<leader>db", function()
  browse.open({ root = vim.fn.getcwd() })
end, { desc = "Browse the module map" })
