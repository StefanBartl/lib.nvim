---@module 'lib.nvim.bindings.docs_util'
--- Path helpers shared by the generated-bindings writers.
---@description
--- `lib.nvim.bindings.autocmd.docs` and `lib.nvim.bindings.usercmd.docs` answer
--- the same four questions about a source path, and answered them with four
--- identical local functions each. The reasoning behind the answers is the
--- interesting part and it belongs in one place, so a later fix lands for both:
--- `is_under` already had to be fixed once for Windows separators, in one of
--- the two.

local M = {}

---A path relative to `root`, with forward slashes, when it is inside it.
---@param abs string
---@param root string|nil
---@return string
function M.relativize(abs, root)
  local path = (abs or "?"):gsub("\\", "/")
  if not root or root == "" then
    return path
  end
  local prefix = root:gsub("\\", "/"):gsub("/+$", "") .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

---Was this source path produced inside `root`?
---
---The registries are global: one session holds records from every plugin that
---loaded. Writing one repo's docs means keeping only what came out of it.
---
---Both sides are normalized, not just `abs`. A caller handing in what
---`vim.fn.fnamemodify()` returns on Windows would otherwise match nothing and
---get an empty document with no error -- which is how this was found.
---@param abs string
---@param root string|nil
---@return boolean
function M.is_under(abs, root)
  if not root or root == "" then
    return true
  end
  local path = (abs or ""):gsub("\\", "/")
  local prefix = root:gsub("\\", "/"):gsub("/+$", "") .. "/"
  return path:sub(1, #prefix) == prefix
end

---The repository root a path belongs to, and the plugin name under its `lua/`.
---
---Derived from a source path rather than from `cwd`, because the answer has to
---be right when the call comes from a plugin's own command while the editor's
---cwd is some unrelated project.
---@param path string
---@return string|nil root
---@return string|nil plugin  # the first directory under `lua/`
function M.repo_of(path)
  local p = (path or ""):gsub("\\", "/")
  local root, rest = p:match("^(.*)/lua/(.+)$")
  if not root then
    return nil, nil
  end
  return root, rest:match("^([^/]+)")
end

---The source file `level` frames up the stack, with no `@` prefix.
---@param level integer
---@return string
function M.caller_file(level)
  local info = debug.getinfo(level, "S")
  return (((info and info.source) or ""):gsub("^@", ""))
end

---The call site `level` frames up the stack, as `file:line`.
---
---The line is half the answer: "something maps `<leader>q`" is only useful
---with the file to open next to it.
---@param level integer
---@return string
function M.caller_site(level)
  local info = debug.getinfo(level, "Sl")
  if not info then
    return "?"
  end
  local src = (info.source or "?"):gsub("^@", "")
  return ("%s:%d"):format(src, info.currentline or -1)
end

---Escape a pipe so a description cannot break a Markdown table row.
---@param s string|nil
---@return string
function M.cell(s)
  -- The outer parentheses drop `gsub`'s match count, which this function
  -- does not promise.
  return ((s or ""):gsub("|", "\\|"))
end

return M
