---@module 'lib.nvim.fs.dir_guard'
--- Hold the working directory on a path until released.
---
--- Neovim's cwd is global mutable state that any plugin may change at any
--- time — a picker that `:lcd`s into a result, a session restore, a test
--- runner, an LSP root-dir hook. Code that deliberately pins the cwd (a
--- project lock, a per-tab workspace) therefore cannot just call `chdir`
--- once: it has to notice when something else moved it and put it back.
---
--- This module is that watcher. `hold(path)` changes into `path` and keeps
--- it there via `DirChanged`; every foreign change is undone, every change
--- the guard makes itself is ignored (no re-entrant loop). Releasing does
--- **not** restore the previous directory — the guard holds a position, it
--- does not own a stack.
---
---   local dir_guard = require("lib.nvim.fs.dir_guard")
---
---   local held = dir_guard.hold("/repo")
---   vim.cmd.cd("/tmp")     -- undone: cwd is /repo again
---   held.bypass(function() vim.cmd.cd("/tmp") end)  -- allowed, then restored
---   held.update("/other")  -- move the pin
---   held.release()
---
--- Built on `lib.nvim.fs.chdir` (explicit scope, normalized paths) — the
--- guard watches exactly the scope it holds: a global hold ignores a
--- window-local `:lcd`, because that does not change the global cwd.
---
--- See @types/init.lua for Lib.Fs.DirGuard.*.

require("lib.nvim.fs.dir_guard.@types")

local chdir = require("lib.nvim.fs.chdir")
local normkey = require("lib.nvim.fs.normkey")
local au = require("lib.nvim.bindings.autocmd")

local M = {}

---Unique suffix per guard: augroups are keyed by name, and two guards must
---never share (or clear) each other's group.
local _seq = 0

---@internal
---Read the cwd of the scope a guard holds.
---
---`getcwd()` takes window/tab *numbers*, not handles, so an explicit
---`opts.win`/`opts.tab` is translated first. `-1` means "not scoped" — the
---pair `(-1, -1)` is the global cwd, which is what a global hold compares
---against: a `:lcd` elsewhere must not count as a violation.
---@param opts Lib.Fs.DirGuard.Opts
---@return string
local function scope_cwd(opts)
  local scope = opts.scope or "global"

  local tabnr = -1
  if opts.tab and vim.api.nvim_tabpage_is_valid(opts.tab) then
    tabnr = vim.api.nvim_tabpage_get_number(opts.tab)
  elseif scope ~= "global" then
    tabnr = 0
  end

  local winnr = -1
  if scope == "win" then
    winnr = 0
    if opts.win and vim.api.nvim_win_is_valid(opts.win) then
      winnr = vim.api.nvim_win_get_number(opts.win)
    end
  end

  local ok, cwd = pcall(vim.fn.getcwd, winnr, tabnr)
  return ok and cwd or ""
end

---@internal
---Canonical comparison key; "" for an unusable path so a failed lookup can
---never accidentally compare equal to a held directory.
---@param p string?
---@return string
local function key(p)
  if type(p) ~= "string" or p == "" then
    return ""
  end
  return normkey(p)
end

---Pin the working directory to `path` until the returned handle is released.
---@param path string
---@param opts? Lib.Fs.DirGuard.Opts
---@return Lib.Fs.DirGuard.Handle? handle nil when the initial change failed
---@return string? err
function M.hold(path, opts)
  opts = opts or {}

  local ok, err = chdir(path, opts)
  if not ok then
    return nil, err
  end

  -- Read the cwd back instead of trusting the input: chdir normalized and
  -- resolved it, and this key is compared against `getcwd()` on every event.
  local held = key(scope_cwd(opts))
  if held == "" then
    return nil, "dir_guard: could not read back the working directory"
  end

  _seq = _seq + 1
  local group =
    vim.api.nvim_create_augroup(("lib.nvim.fs.dir_guard.%d"):format(_seq), { clear = true })

  local released = false
  -- Set while the guard itself is changing directory. The re-assert below
  -- triggers another DirChanged, which would otherwise be read as a foreign
  -- change and re-assert again — a loop.
  local reasserting = false

  local handle

  ---@internal
  ---Put the cwd back where the guard wants it.
  local function reassert()
    reasserting = true
    local ok2, err2 = chdir(held, opts)
    reasserting = false
    if not ok2 and opts.on_error then
      pcall(opts.on_error, err2 or "chdir failed")
    end
  end

  au.create("DirChanged", function()
    if released or reasserting then
      return
    end
    local now = key(scope_cwd(opts))
    if now == "" or now == held then
      return
    end
    -- `on_violation` gets the last word: returning false accepts the foreign
    -- change and drops the guard, so a caller can implement "the user meant
    -- it" without racing the watcher from inside the same event.
    if opts.on_violation then
      local ok2, verdict = pcall(opts.on_violation, now, held)
      if ok2 and verdict == false then
        handle.release()
        return
      end
    end
    reassert()
  end, {
    group = group,
    pattern = { "global", "tabpage", "window", "auto" },
    desc = "lib.nvim.fs.dir_guard: hold " .. held,
  })

  ---@type Lib.Fs.DirGuard.Handle
  handle = {
    path = function()
      return held
    end,

    is_held = function()
      return not released
    end,

    update = function(new_path)
      if released then
        return false, "dir_guard: guard already released"
      end
      reasserting = true
      local ok2, err2 = chdir(new_path, opts)
      if ok2 then
        local next_key = key(scope_cwd(opts))
        if next_key ~= "" then
          held = next_key
        end
      end
      reasserting = false
      return ok2, err2
    end,

    bypass = function(fn)
      if released then
        return pcall(fn)
      end
      -- The whole callback runs unguarded — including any directory change it
      -- makes and any it triggers indirectly — then the pin is restored.
      reasserting = true
      local ok2, res = pcall(fn)
      reasserting = false
      if key(scope_cwd(opts)) ~= held then
        reassert()
      end
      return ok2, res
    end,

    release = function()
      if released then
        return
      end
      released = true
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  }

  return handle
end

---@type Lib.Fs.DirGuard
return M
