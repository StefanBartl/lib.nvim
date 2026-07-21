---@module 'lib.nvim.docmap.registry'
--- `install()` / `uninstall()`: a live, in-memory `Lib.Docmap.Handle` around
--- a scanned IR, as opposed to `generate()`'s one-shot scan-render-write.
---
--- This is the "objects in source code" half of docmap — another plugin's
--- Lua code reaches for `handle.ir()` directly instead of reading and
--- parsing `module_map.json` off disk, and can subscribe to `on_change` to
--- react when the tree does.
---
--- Deliberately has no opinion about user commands: it does not create
--- `:LibMap` or any other usercmd itself. `docmap.command.setup()` is what
--- layers a named command on top of a handle, precisely so two independent
--- `install()` calls (this repo's own map, and a consuming plugin's map)
--- never fight over registering the same command name — that collision was
--- the actual bug this split avoids, not a hypothetical one.

local notify = require("lib.nvim.notify").create("[docmap]")
local autocmd = require("lib.nvim.autocmd")

local M = {}

---@type table<string, { opts: Lib.Docmap.Opts, ir: Lib.Docmap.IR, findings: Lib.Docmap.Finding[], watchers: fun(ir: Lib.Docmap.IR, findings: Lib.Docmap.Finding[])[], augroup: integer?, debounce: Lib.Debounce.Handle?, handle: Lib.Docmap.Handle }>
local registry = {}

---@param root string
---@return string
local function norm_root(root)
  return (root:gsub("\\", "/"):gsub("/+$", ""))
end

---@param entry table
local function notify_watchers(entry)
  for _, cb in ipairs(entry.watchers) do
    -- One misbehaving subscriber must not break the others or the rescan
    -- that triggered this.
    local ok, err = pcall(cb, entry.ir, entry.findings)
    if not ok then
      vim.schedule(function()
        notify.warn("on_change subscriber errored: " .. tostring(err))
      end)
    end
  end
end

---Install a live handle for `opts.root`. Runs an initial scan immediately
---(synchronously — including the LuaLS shell-out if `opts.luals` is set, so
---a caller passing `luals = true` here is opting into that cost up front,
---not just on some later rescan).
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.Handle
function M.install(opts)
  assert(type(opts) == "table" and type(opts.root) == "string" and opts.root ~= "", "docmap.install: opts.root is required")

  local root = norm_root(opts.root)
  opts = vim.tbl_extend("force", {}, opts, { root = root })

  if registry[root] then
    -- Re-installing over an existing handle for the same root is treated as
    -- "replace, don't stack": tearing down the old watch/augroup first keeps
    -- a caller's repeated setup()-under-hot-reload from leaking timers.
    M.uninstall(registry[root].handle)
  end

  local docmap = require("lib.nvim.docmap")
  local entry = { opts = opts, watchers = {} }
  registry[root] = entry

  local function rescan(rescan_opts)
    local scan_opts = rescan_opts and vim.tbl_extend("force", opts, rescan_opts) or opts
    entry.ir, entry.findings = docmap.scan_full(scan_opts)
    notify_watchers(entry)
    return entry.ir, entry.findings
  end
  entry.rescan_fn = rescan

  rescan() -- initial scan; handle.ir() must never observe an unset IR

  if opts.watch then
    local source_dir = root .. "/" .. (opts.source or "lua")
    local is_subpath = require("lib.nvim.fs.is_subpath")
    -- Raw nvim_create_augroup on purpose, not autocmd.group(): uninstall()
    -- below deletes this group by numeric id (nvim_del_augroup_by_id), which
    -- autocmd.group()'s name -> id cache has no visibility into — a second
    -- install() for the same root would hand back the now-stale cached id
    -- instead of creating a fresh group.
    local group = vim.api.nvim_create_augroup("LibDocmapWatch:" .. root, { clear = true })
    local debounce = require("lib.nvim.debounce").new(function()
      rescan()
    end, opts.watch_ms or 500)

    -- Scoping via an autocmd *glob pattern* (e.g. "<root>/<source>/**/*.lua")
    -- is the obvious approach and the wrong one: Vim's pattern matcher compares
    -- against the raw buffer path, which is OS-native (backslashes on
    -- Windows), while any path built here is forward-slash — verified this
    -- mismatches and the autocmd silently never fires. `is_subpath` already
    -- exists for exactly this normalize-both-sides comparison (its own
    -- history has the same backslash bug on record), so scope with a cheap
    -- extension-only pattern and an explicit subpath check in the callback
    -- instead of trusting the glob engine with directory structure.
    autocmd.create({ "BufWritePost" }, function(args)
      local buf_path = vim.api.nvim_buf_get_name(args.buf)
      if buf_path ~= "" and is_subpath(buf_path, source_dir) then
        debounce.call()
      end
    end, {
      group = group,
      pattern = "*.lua",
    })

    entry.augroup = group
    entry.debounce = debounce
  end

  ---@type Lib.Docmap.Handle
  local handle = {
    root = root,
    ir = function()
      return entry.ir
    end,
    findings = function()
      return entry.findings
    end,
    node = function(id)
      return entry.ir.nodes[id]
    end,
    rescan = rescan,
    on_change = function(cb)
      entry.watchers[#entry.watchers + 1] = cb
      return function()
        for i, existing in ipairs(entry.watchers) do
          if existing == cb then
            table.remove(entry.watchers, i)
            return
          end
        end
      end
    end,
    uninstall = function()
      M.uninstall(root)
    end,
  }
  entry.handle = handle

  return handle
end

---Look up an existing handle by root, without installing one.
---@param root string
---@return Lib.Docmap.Handle?
function M.get(root)
  local entry = registry[norm_root(root)]
  return entry and entry.handle
end

---Tear down a handle: cancels the watch debounce/autocmd, drops it from the
---registry. Idempotent — uninstalling twice, or a handle/root that was never
---installed, is a no-op returning `false`, not an error, matching this
---repo's own `usercmd.create` tolerance for repeated setup/teardown under
---hot-reload configs.
---@param handle_or_root Lib.Docmap.Handle|string
---@return boolean uninstalled
function M.uninstall(handle_or_root)
  local root = type(handle_or_root) == "table" and handle_or_root.root or handle_or_root
  if type(root) ~= "string" then
    return false
  end
  root = norm_root(root)

  local entry = registry[root]
  if not entry then
    return false
  end

  if entry.debounce then
    entry.debounce.cancel()
  end
  if entry.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, entry.augroup)
  end
  entry.watchers = {}
  registry[root] = nil
  return true
end

return M
