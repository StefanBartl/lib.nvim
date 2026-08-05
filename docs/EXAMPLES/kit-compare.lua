-- docs/EXAMPLES/kit-compare.lua
--
-- Module:   lib.nvim.ui.kit.compare
-- Scenario: pick two files out of a scanned list and view their contents
--           side by side -- the generic version of what images.nvim's
--           `:Image compare` builds on top of (there, `render` draws an
--           image via terminal escape sequences instead of buffer text).
--
-- Flow: SEARCH (prompt + results + a live preview of the highlighted file)
--   -> <M-c> or <CR> marks the current file, entering MARKED (results
--      shrinks, a frozen preview of the marked file appears below it, the
--      live preview on the right keeps following the selection)
--   -> <CR> again confirms the second file, entering COMPARE (two full
--      previews side by side; q/<Esc> closes).

local kit = require("lib.nvim.ui.kit")

-- Pretend data source: replace with a real file scan.
local FILES = { "README.md", "CHANGELOG.md", "lua/init.lua", "lua/config.lua" }

---@param path string
---@return string[]
local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return { "(could not read " .. path .. ")" }
  end
  return lines
end

kit.compare({
  items = FILES,
  title = "Compare two files",

  -- Paint `item` into `surface` -- for text, just set_lines(). A caller
  -- drawing something that isn't buffer content (images.nvim's terminal
  -- overlay) would use `surface.winid`'s geometry instead; see
  -- images.nvim's lua/images/compare.lua for that version.
  render = function(item, surface)
    surface:set_lines(read_lines(item))
  end,

  -- Called once, however the picker ends: aborted from SEARCH (a = nil),
  -- aborted from MARKED (a = the marked file, b = nil), or dismissed from
  -- COMPARE (both set).
  on_close = function(a, b)
    if a and b then
      vim.notify(("compared %s <-> %s"):format(a, b))
    end
  end,
})

-- The returned handle also exposes: state() ("search"|"marked"|"compare"),
-- slots() (the raw kit.surface windows for the current state), move(delta),
-- mark() (SEARCH: freeze the highlighted item), confirm() (SEARCH: same as
-- mark; MARKED: pick the 2nd item), and close().
