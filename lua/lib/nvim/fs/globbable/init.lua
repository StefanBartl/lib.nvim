---@module 'lib.nvim.fs.globbable'
--- A spelling of a directory path that is safe to hand to Vim's glob.
---
--- `vim.fn.glob` and `vim.fn.globpath` read their argument as a *pattern*,
--- not as a path, and a `~` in a pattern is a home-directory reference. On
--- Windows that makes an 8.3 short name fatal: under
--- `C:/Users/STEFAN~1/...` — which is what `%TEMP%`, `vim.fn.tempname()` and
--- any cwd inherited from one of them expand to for a profile name longer
--- than eight characters — glob tries to resolve `~1` as a user, finds no
--- such user, and returns an **empty list**. No error, no warning: code that
--- globs a directory it was handed reports "nothing here" for a directory
--- full of files.
---
--- `uv.fs_realpath` gives back the long form, which globs correctly. It only
--- works on a path that exists; a root that does not is returned unchanged,
--- since glob would find nothing under it either way.
---
--- The syscall is skipped entirely when there is no `~` to resolve, which is
--- the common case — this sits directly in front of directory scans.
---
--- Not handled: the other glob metacharacters. A directory whose *name*
--- contains `[`, `]`, `*` or `?` is the same class of hazard, but escaping
--- those is not portable (a backslash escape is itself a separator on
--- Windows), and `fs_realpath` does not help. See the README.

local uv = vim.uv or vim.loop

--- `root` is deliberately optional: the guard below answers `""` for
--- anything that is not a non-empty string.
---@param root string|nil  directory path the caller is about to glob under
---@return string  the same directory, spelled so glob can read it
return function(root)
  if type(root) ~= "string" or root == "" then
    return ""
  end
  if not root:find("~", 1, true) then
    return root
  end
  local real = uv.fs_realpath(root)
  return real and (real:gsub("\\", "/")) or root
end
