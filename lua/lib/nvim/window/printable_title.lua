---@module 'lib.nvim.window.printable_title'
---@internal
---The title of a float, with every unprintable character spelled out.
---
---`nvim_open_win` / `nvim_win_set_config` take a plain-string title as it is and draw
---it cell by cell: an ESC or a BEL in it becomes a grid cell of its own, which the TUI
---then writes to the terminal verbatim -- a title built from pasted or typed text
---(`:Verb <C-v><Esc>]0;...<C-v><C-g>`, a file name, a case title) can set the terminal's
---window title or move its cursor. Neovim spells the same characters out (`^[`, `^G`,
---`<9b>`) everywhere else it shows text, so this does it for a title too, through
---`strtrans()`; TAB and LF are not exempt (the TUI would move the cursor for those too).
---
---A title without any such character, a list of chunks (Neovim spells those out
---itself) and a non-string come back untouched.

---@param title any
---@return any
local function printable_title(title)
  if type(title) ~= "string" then
    return title
  end
  -- Fast path: plain ASCII text, which is every title but a handful.
  if not title:find("[%z\1-\31\127-\255]") then
    return title
  end
  -- A NUL reaches vim.fn as a Blob (E976); `^@` is how it is drawn anyway.
  local text = title:gsub("%z", "^@")
  local ok, shown = pcall(vim.fn.strtrans, text)
  -- strtrans cannot fail on a NUL-free string; if it ever does, drop the
  -- offending bytes rather than hand them on.
  if ok and type(shown) == "string" then
    return shown
  end
  return (text:gsub("[\1-\31\127]", ""))
end

return printable_title
