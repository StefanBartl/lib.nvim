---@module 'lib.nvim.fs.chdir'
--- Scope-aware working-directory change: global (`:cd`), tab-local (`:tcd`)
--- or window-local (`:lcd`), with normalization, validation and no throwing.
---
--- Why not `vim.fn.chdir()`: its scope is *implicit* — it changes globally,
--- per-tab or per-window depending on what the current window happens to
--- have, so the same call means different things in different windows. Code
--- that manages a cwd deliberately (a project lock, a per-tab workspace)
--- needs to say which scope it means. This module makes that explicit and
--- keeps the rest of the ceremony in one place:
---
---   * `path` is canonicalized through `lib.nvim.fs.normkey` (`~` expansion,
---     symlinks resolved, forward slashes, upper-cased Windows drive) so the
---     resulting cwd is directly comparable to `vim.fn.getcwd()` — which
---     reports libuv's physical cwd, i.e. already symlink-resolved.
---   * a path that is missing or not a directory is rejected *before* the
---     command runs, with a message instead of an exception.
---   * every failure is returned as `false, err`; nothing throws.
---
---   local chdir = require("lib.nvim.fs.chdir")
---   chdir("~/projects/app")                        -- global
---   chdir("/repo", { scope = "tab" })              -- :tcd in the current tab
---   chdir("/repo", { scope = "win", win = winid }) -- :lcd in that window
---
--- See @types/init.lua for Lib.Fs.Chdir.Opts.

require("lib.nvim.fs.chdir.@types")

local normkey = require("lib.nvim.fs.normkey")
local is_dir = require("lib.nvim.fs.is_dir")

---`:cd` clears a window-local directory for the current window, `:tcd` sets
---the tab-local one, `:lcd` the window-local one. Mapping the scope name to
---the command keeps the intent readable at the call site.
---@type table<Lib.Fs.Chdir.Scope, string>
local COMMANDS = {
  global = "cd",
  tab = "tcd",
  win = "lcd",
}

---Drop a trailing slash unless the path *is* a root ("/", "C:/", "//host/share").
---@param p string
---@return string
local function strip_trailing_slash(p)
  if #p <= 1 or p:sub(-1) ~= "/" then
    return p
  end
  local without = p:sub(1, -2)
  -- "C:" alone is not a directory path — keep "C:/". Likewise a bare UNC share.
  if without:match("^%a:$") or without:match("^//[^/]+/[^/]*$") then
    return p
  end
  return without
end

---Run `fn` in the window that owns the requested scope.
---
---A tab-local `:tcd` has to be executed from *some* window inside that tab —
---there is no tabpage-call API — so the tab's current window is borrowed.
---`nvim_win_call` does not fire the usual window-enter autocmds, which is
---what makes this safe to do from an event handler.
---@param opts Lib.Fs.Chdir.Opts
---@param fn fun()
---@return boolean ok
---@return string? err
local function in_scope(opts, fn)
  local win = opts.win
  if not win and opts.tab then
    if not vim.api.nvim_tabpage_is_valid(opts.tab) then
      return false, "invalid tabpage: " .. tostring(opts.tab)
    end
    win = vim.api.nvim_tabpage_get_win(opts.tab)
  end

  if not win then
    local ok, err = pcall(fn)
    return ok, ok and nil or tostring(err)
  end

  if not vim.api.nvim_win_is_valid(win) then
    return false, "invalid window: " .. tostring(win)
  end
  local ok, err = pcall(vim.api.nvim_win_call, win, fn)
  return ok, ok and nil or tostring(err)
end

---Change the working directory in an explicit scope.
---@param path string Directory to change into; `~` and relative paths allowed.
---@param opts? Lib.Fs.Chdir.Opts
---@return boolean ok
---@return string? err Reason on failure; the resolved path is never returned here — read it back with `vim.fn.getcwd()`.
return function(path, opts)
  if type(path) ~= "string" or path == "" then
    return false, "chdir: path must be a non-empty string"
  end
  opts = opts or {}

  local scope = opts.scope or "global"
  local command = COMMANDS[scope]
  if not command then
    return false, "chdir: unknown scope: " .. tostring(scope)
  end

  -- Resolve relative input against the *current* cwd before normalizing:
  -- normkey only canonicalizes, it does not make a path absolute. `:p` on a
  -- directory appends a trailing slash, which is then dropped again — a cwd
  -- read back via `getcwd()` never carries one, and the two must compare
  -- equal for callers that hold or watch a directory.
  local target = strip_trailing_slash(normkey(vim.fn.fnamemodify(path, ":p")))

  if target == "" then
    return false, "chdir: could not resolve path: " .. path
  end
  if not is_dir(target) then
    return false, "chdir: not a directory: " .. target
  end

  return in_scope(opts, function()
    vim.cmd[command](vim.fn.fnameescape(target))
  end)
end
