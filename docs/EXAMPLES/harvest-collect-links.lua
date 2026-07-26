-- docs/EXAMPLES/harvest-collect-links.lua
--
-- Module:   lib.nvim.harvest
-- Scenario: pull every Markdown link out of the current buffer and let the
--           user jump to one through a picker.
--
-- This is the exact use case that motivated lib.nvim.harvest: markdown.nvim
-- used to carry two near-identical link collectors (one for the current
-- buffer/cwd, one for a whole directory tree), each hand-rolling its own
-- file filter and "which file did this line come from" bookkeeping. This
-- file is what either of those collapses to on top of harvest.
--
-- Not meant to be `dofile`'d standalone: paste the body into a user command
-- or keymap callback inside a running Neovim instance.

local harvest = require("lib.nvim.harvest")

-- 1. SCOPE -- just the current buffer this time. "buffer" (also reachable
--    as "" or "%") is what `resolve_token` falls back to by default;
--    spelled out here for clarity.
local sources = harvest.scope.resolve_token("buffer")

-- 2. FILTER -- yours, not harvest's: a small Lua-pattern link extractor.
--    Real code would likely reach for a proper Markdown parser; a pattern
--    is enough to show the shape of a harvest consumer.
---@type { label: string, file: string|nil, line: integer }[]
local links = {}
for _, src in ipairs(sources) do
  for i, line in ipairs(src.lines) do
    for text, url in line:gmatch("%[([^%]]+)%]%(([^%)]+)%)") do
      links[#links + 1] = {
        label = ("%s  ->  %s"):format(text, url),
        file = src.file,
        line = src.first + i - 1,
      }
    end
  end
end

if #links == 0 then
  vim.notify("harvest: no Markdown links in the current buffer", vim.log.levels.WARN)
  return
end

-- 3. SINK -- `harvest.sink.select` is the picker half of `emit`: it takes a
--    `format` function to turn each item into a display string, and calls
--    the callback with whichever item the user picked (or nil on cancel).
harvest.sink.select(links, {
  prompt = "Links",
  format = function(item)
    return item.label
  end,
}, function(choice)
  if choice and choice.file then
    vim.cmd.edit(vim.fn.fnameescape(choice.file))
    vim.api.nvim_win_set_cursor(0, { choice.line, 0 })
  end
end)
