-- docs/EXAMPLES/harvest-scan-and-export.lua
--
-- Module:   lib.nvim.harvest
-- Scenario: scan every Markdown file under the current working directory for
--           "TODO" markers, render the hits as a Markdown table, and drop
--           that table into a scratch buffer.
--
-- lib.nvim.harvest deliberately does NOT provide a "collect + filter +
-- render" pipeline object to plug callbacks into -- the middle step
-- (deciding what counts as a hit) is domain logic and stays with the
-- caller. This file shows the three independent pieces -- scope, your own
-- filter loop, render + emit -- wired together by hand.
--
-- Not meant to be `dofile`'d standalone: paste the body into a user command
-- or keymap callback inside a running Neovim instance.

local harvest = require("lib.nvim.harvest")

-- 1. SCOPE -- resolve a location token into a flat list of `Source` records
--    ({ file, bufnr, lines, first }). `resolve_token` is the convenience
--    entry point a user command's argument would go through; "cwd" scans
--    the working directory recursively, `match` narrows the walk to
--    Markdown files by basename before any file is even read.
local sources, err = harvest.scope.resolve_token("cwd", { match = "%.md$" })
if err then
  vim.notify("harvest: " .. err, vim.log.levels.ERROR)
  return
end

-- 2. FILTER -- yours, not harvest's. harvest hands you lines plus
--    provenance and nothing more; what counts as a "hit" is entirely your
--    decision. Here: any line containing the literal string "TODO".
local rows = {}
for _, src in ipairs(sources) do
  for i, line in ipairs(src.lines) do
    if line:match("TODO") then
      -- `src.first` is the 1-based line number of `src.lines[1]` within its
      -- file. For a whole-file scan (as here) it is always 1, but it is
      -- exactly what lets a *partial* scope (e.g. "range", a Visual
      -- selection) report real line numbers instead of every hit claiming
      -- to start at line 1.
      rows[#rows + 1] = { src.file or "[buffer]", src.first + i - 1, line }
    end
  end
end

-- 3. RENDER + SINK -- turn the rows into a GitHub-flavored Markdown table,
--    then hand the resulting text to a sink. `emit` maps a user-facing
--    output token ("table", "clipboard", "file:<path>", "echo") to the
--    matching `harvest.sink.*` call, so a plugin's own `out=` argument can
--    be forwarded verbatim instead of a hand-written if/elseif chain.
local text = harvest.render.markdown_table({ "File", "Line", "Text" }, rows)

harvest.emit(text, "table") -- opens a scratch buffer containing the table

-- Other sinks, same `text`, just a different output token:
-- harvest.emit(text, "clipboard")           -- copy to the system clipboard
-- harvest.emit(text, "file:/tmp/todos.md")  -- write straight to a file
-- harvest.emit(text, "echo")                -- print to the command line
