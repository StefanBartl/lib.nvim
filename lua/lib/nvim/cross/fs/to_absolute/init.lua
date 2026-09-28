---@module 'lib.nvim.cross.fs.to_absolute'
--- Resolve any path spec -- relative, `~`/env-prefixed, mixed-separator, or
--- made up of nothing but separator characters -- to its absolute,
--- trailing-separator-free, forward-slash form. Composes the pure
--- `cross.fs` helpers around `vim.fn.fnamemodify(path, ":p")`, the one step
--- here that actually touches the filesystem/cwd.
---
--- `separators.collapse_dots` runs on the input *before* `fnamemodify`, not
--- just on its output: a path made up entirely of separators ("//",
--- "\\\\", "\\/\\", any length or mix) collapses there to a single POSIX
--- "/", which `fnamemodify` then resolves to the current drive's root on
--- Windows and to the real filesystem root on POSIX -- both correctly.
--- Skipping that pre-pass and handing such a path to `fnamemodify` as-is
--- does not: a naive trailing-separator strip collapses it to "", which
--- resolves to the cwd instead of the root, and on POSIX a literal `\` is
--- just an ordinary filename character, so an un-collapsed backslash-heavy
--- input resolves relative to the cwd rather than to anything the caller
--- meant. `collapse_dots` runs a second time on `fnamemodify`'s own output
--- because that modifier both expects the native separator on its input on
--- some platforms and re-adds a trailing separator to what it returns.

local expand_path = require("lib.nvim.cross.fs.expand_path")
local collapse_dots = require("lib.nvim.cross.fs.separators.collapse_dots")

---@param path string
---@return string
return function(path)
  assert(
    type(path) == "string",
    "[lib.nvim.cross.fs.to_absolute] parameter 'path' must be type of string, but is " .. type(path)
  )
  local unified = collapse_dots(path)
  if unified == "" then
    unified = "/"
  end
  return collapse_dots(vim.fn.fnamemodify(expand_path(unified), ":p"))
end
