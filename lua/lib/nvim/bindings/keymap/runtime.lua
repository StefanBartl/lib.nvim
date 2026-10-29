---@module 'lib.nvim.bindings.keymap.runtime'
--- The mappings that are valid right now, and how they differ from a pristine Neovim.
---@description
--- `registry.conflicts()` sees what lib.nvim bound; the `tap` sees what was
--- bound *since it was installed*. This module reads what is actually in
--- effect, from Neovim itself, and answers three questions the other two
--- cannot:
---
---  1. **What is bound, and by whom?** `snapshot()` lists every effective
---     mapping with the file and line that set it (`sid`/`lnum` resolved to a
---     path) and an `origin`: Neovim's own defaults (`builtin`), lib.nvim's
---     registry (`lib`), or anything else (`other`).
---  2. **What did the user change of Neovim's defaults?** `pristine_defaults()`
---     asks a clean child Neovim (`--clean`) for its mappings, and
---     `diff_defaults()` sets those against the live ones: a default someone
---     re-bound is `overridden`, one that is gone (removed, or set to `false` in
---     a plugin's spec) is `removed`.
---  3. **Is one action bound to several keys?** `action_duplicates()` groups
---     live mappings by description or by identical string target. That is a
---     list of *candidates*, never a verdict: two keys for one action is often
---     intended.
---
--- **What this does not see.** Neovim's built-in Normal-mode commands (`dd`,
--- `<C-w>`, `gg`) are not mappings, so they are neither listed nor compared.
--- A mapping that was overwritten is gone from `nvim_get_keymap()` -- only the
--- tap can say it ever existed. Buffer-local mappings are read for loaded
--- buffers only (`opts.buffers`).
---
--- ```lua
--- local rt = require("lib.nvim.bindings.keymap.runtime")
--- local live = rt.snapshot()
--- local pristine, err = rt.pristine_defaults()
--- if pristine then
---   local d = rt.diff_defaults(pristine, live)
---   print(#d.overridden, #d.removed)
--- end
--- ```
---@see lib.nvim.bindings.keymap.tap
---@see lib.nvim.bindings.keymap.registry

local lhs_mod = require("lib.nvim.bindings.keymap.lhs")

local M = {}

local MODES = { "n", "x", "s", "o", "i", "c", "t", "l" }

--- Runs inside the child Neovim. Kept as data so it can be written next to the
--- cache and run with `-l`; everything it needs is in the child's own `vim`.
local PROBE = [[
local out = {}
for _, m in ipairs({ "n", "x", "s", "o", "i", "c", "t", "l" }) do
  for _, km in ipairs(vim.api.nvim_get_keymap(m)) do
    if km.abbr ~= 1 then
      out[#out + 1] = {
        mode = m,
        lhs = km.lhs,
        rhs = km.rhs ~= "" and km.rhs or nil,
        callback = km.callback ~= nil or nil,
        desc = km.desc,
        sid = km.sid,
        lnum = km.lnum,
        expr = km.expr == 1 or nil,
      }
    end
  end
end
io.stdout:write(vim.json.encode(out))
]]

---@type { tag: string, entries: Lib.Keymap.RuntimeEntry[] }|nil
local memo

---@type table<integer, string|false>
local script_names = {}

---@internal
--- The file a script id stands for, or nil when there is none (sid 0, the
--- negative ids Neovim uses for "set from the command line", a script that is
--- gone). Cached: script ids are never reused within a session.
---@param sid integer|nil
---@return string|nil
local function script_name(sid)
  if type(sid) ~= "number" or sid <= 0 then
    return nil
  end
  local cached = script_names[sid]
  if cached ~= nil then
    return cached or nil
  end
  local ok, info = pcall(vim.fn.getscriptinfo, { sid = sid })
  local name = ok and type(info) == "table" and info[1] and info[1].name or nil
  script_names[sid] = name or false
  return name
end

---@internal
---@param path string
---@return string
local function slashes(path)
  return (path:gsub("\\", "/"))
end

---@internal
---@param source string|nil
---@return boolean
local function under_runtime(source)
  local rt = vim.env.VIMRUNTIME
  if not source or not rt or rt == "" then
    return false
  end
  local a, b = slashes(source), slashes(rt)
  if vim.fn.has("win32") == 1 then
    a, b = a:lower(), b:lower()
  end
  return a:sub(1, #b + 1) == b .. "/"
end

---@internal
--- `mode \0 scope \0 key` for everything lib.nvim's registry has bound.
---@return table<string, true>
local function lib_index()
  local idx = {}
  local ok, all = pcall(function()
    return require("lib.nvim.bindings.keymap.registry").registered()
  end)
  if not ok then
    return idx
  end
  for _, entries in pairs(all) do
    for _, e in ipairs(entries) do
      if e.bound and e.lhs then
        local key = lhs_mod.normalize(e.lhs)
        for _, m in ipairs(lhs_mod.modes(e.mode)) do
          idx[table.concat({ m, lhs_mod.scope(e.buffer), key }, "\0")] = true
        end
      end
    end
  end
  return idx
end

---@internal
--- A file that exists on disk (as opposed to the made-up paths Neovim reports
--- for its own embedded Lua, or a script that is gone).
---@type table<string, boolean>
local real_files = {}

---@param source string|nil
---@return boolean
local function is_real_file(source)
  if not source then
    return false
  end
  if real_files[source] == nil then
    real_files[source] = vim.uv.fs_stat(source) ~= nil
  end
  return real_files[source]
end

---@internal
--- What makes two mappings "the same one" for the purpose of recognising a
--- default: mode, key, target and description.
---@param e { mode: string, key: string, rhs?: string, desc?: string, callback?: boolean, expr?: boolean }
---@return string
local function content_key(e)
  return table.concat({
    e.mode,
    e.key,
    e.rhs or "",
    e.desc or "",
    e.callback and "cb" or "",
    e.expr and "expr" or "",
  }, "\0")
end

---@internal
---@param km table  # One `nvim_get_keymap()` entry.
---@param mode string
---@param buffer integer|nil
---@param lib table<string, true>
---@param defaults table<string, true>
---@return Lib.Keymap.RuntimeEntry
local function entry_of(km, mode, buffer, lib, defaults)
  local key = lhs_mod.normalize(km.lhs)
  local source = script_name(km.sid)
  local entry = {
    mode = mode,
    lhs = km.lhs,
    key = key,
    rhs = (type(km.rhs) == "string" and km.rhs ~= "") and km.rhs or nil,
    callback = km.callback ~= nil,
    desc = (type(km.desc) == "string" and km.desc ~= "") and km.desc or nil,
    sid = km.sid,
    lnum = km.lnum,
    source = source,
    origin = "other",
    buffer = buffer,
    expr = km.expr == 1,
  }
  if km.sid == 1 or under_runtime(source) then
    entry.origin = "builtin"
  elseif buffer == nil and defaults[content_key(entry)] and not is_real_file(source) then
    -- A Neovim whose own Lua is compiled into the binary stamps its defaults
    -- with no usable script id. Recognised by content instead -- but only when
    -- no file of the user's claims the mapping.
    entry.origin = "builtin"
  elseif lib[table.concat({ mode, lhs_mod.scope(buffer), key }, "\0")] then
    entry.origin = "lib"
  end
  return entry
end

---@internal
--- The last recorded binding of each key, from the keymap tap, as `mode \0 scope \0 key`; nil
--- when the tap has recorded nothing. A key whose last event is a deletion is not live and is left out.
---@return table<string, Lib.Keymap.TapEvent>|nil
local function tap_index()
  local ok, tap = pcall(require, "lib.nvim.bindings.keymap.tap")
  if not ok then
    return nil
  end
  local events = tap.log()
  if #events == 0 then
    return nil
  end
  local last = {}
  for _, e in ipairs(events) do
    last[table.concat({ e.mode, lhs_mod.scope(e.buffer), e.key }, "\0")] = e.op == "set" and e
      or nil
  end
  return last
end

---@internal
--- Put the tap's source on an entry. The script stamp (`sid`/`lnum`) names the script that was
--- being sourced when the key was bound, which for everything bound from a plugin spec during
--- startup is `init.lua:0`; the tap read the real call site off the stack. Neovim's own defaults
--- keep their stamp, and an event without a `file:line` source changes nothing.
---@param entry Lib.Keymap.RuntimeEntry
---@param tapped table<string, Lib.Keymap.TapEvent>|nil
local function overlay_source(entry, tapped)
  if not tapped or entry.origin == "builtin" then
    return
  end
  local ev = tapped[table.concat({ entry.mode, lhs_mod.scope(entry.buffer), entry.key }, "\0")]
  if not ev or not ev.source then
    return
  end
  local file, line = ev.source:match("^(.*):(%d+)$")
  if not file then
    return
  end
  entry.source, entry.lnum, entry.via, entry.source_from =
    slashes(file), tonumber(line), ev.via, "tap"
end

---Every mapping in effect right now.
---
---Global mappings of the modes n, x, s, o, i, c, t and l (abbreviations are not
---mappings and are left out); with `opts.buffers`, the buffer-local ones of
---every loaded buffer as well. What is listed is what *wins*: a mapping that
---was overwritten is not here.
---
---Neovim's own defaults are recognised by their script id; on a build that does
---not stamp them, by content against `opts.defaults` (default: the cached
---`pristine_defaults()`, never started just for this).
---
---`source`/`lnum` are Neovim's script stamp. With the keymap tap installed they are
---the call site the tap recorded instead (`source_from == "tap"`, plus `via`): the
---stamp is the script being sourced at the time, which is not where a plugin spec
---that ran in the middle of `init.lua` bound its key.
---@param opts? { buffers?: boolean, defaults?: Lib.Keymap.RuntimeEntry[] }
---@return Lib.Keymap.RuntimeEntry[]
function M.snapshot(opts)
  opts = opts or {}
  local lib = lib_index()
  local tapped = tap_index()
  ---@type table<string, true>
  local defaults = {}
  for _, d in ipairs(opts.defaults or M.cached_defaults() or {}) do
    defaults[content_key({
      mode = d.mode,
      key = d.key or lhs_mod.normalize(d.lhs),
      rhs = d.rhs,
      desc = d.desc,
      callback = d.callback,
      expr = d.expr,
    })] =
      true
  end
  local out = {}
  for _, mode in ipairs(MODES) do
    for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
      if km.abbr ~= 1 then
        out[#out + 1] = entry_of(km, mode, nil, lib, defaults)
      end
    end
  end
  if opts.buffers then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
        for _, mode in ipairs(MODES) do
          for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
            if km.abbr ~= 1 then
              out[#out + 1] = entry_of(km, mode, buf, lib, defaults)
            end
          end
        end
      end
    end
  end
  for _, entry in ipairs(out) do
    overlay_source(entry, tapped)
  end
  return out
end

---@internal
--- The running Neovim's version, e.g. `0.12.2` or `0.13.0-dev`.
---@return string
local function version_tag()
  local v = vim.version()
  return ("%d.%d.%d%s"):format(
    v.major,
    v.minor,
    v.patch,
    v.prerelease and ("-" .. tostring(v.prerelease)) or ""
  )
end

---@internal
--- What the defaults cache is keyed by: the version plus the build, since two
--- nightlies share a version string and not their mappings.
---@return string
local function cache_tag()
  local build = vim.version().build
  return version_tag() .. (build and ("+" .. tostring(build)) or "")
end

---@internal
---@param raw table[]
---@return Lib.Keymap.RuntimeEntry[]
local function to_entries(raw)
  local out = {}
  for _, km in ipairs(raw) do
    if type(km) == "table" and type(km.lhs) == "string" and type(km.mode) == "string" then
      out[#out + 1] = {
        mode = km.mode,
        lhs = km.lhs,
        key = lhs_mod.normalize(km.lhs),
        rhs = type(km.rhs) == "string" and km.rhs or nil,
        callback = km.callback == true,
        desc = (type(km.desc) == "string" and km.desc ~= "") and km.desc or nil,
        sid = type(km.sid) == "number" and km.sid or nil,
        lnum = type(km.lnum) == "number" and km.lnum or nil,
        origin = "builtin",
        expr = km.expr == true,
      }
    end
  end
  return out
end

---@internal
---@return string
local function cache_dir()
  return vim.fn.stdpath("cache") .. "/lib.nvim"
end

---@internal
---@param tag string
---@return string
local function cache_file(tag)
  local safe = tag:gsub("[^%w%.%-+]", "_")
  return ("%s/keymap-defaults-%s.json"):format(cache_dir(), safe)
end

---@internal
--- The cached defaults of this Neovim, from memory or from the cache file;
--- never starts a process.
---@param tag string
---@return Lib.Keymap.RuntimeEntry[]|nil
local function read_cache(tag)
  if memo and memo.tag == tag then
    return memo.entries
  end
  local f = io.open(cache_file(tag), "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  local ok, raw = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if ok and type(raw) == "table" and #raw > 0 then
    memo = { tag = tag, entries = to_entries(raw) }
    return memo.entries
  end
  return nil
end

---The defaults `pristine_defaults()` already has in memory or in its cache
---file, or `nil`. Never starts a child Neovim, so it is cheap enough to call
---from anywhere.
---@return Lib.Keymap.RuntimeEntry[]|nil
function M.cached_defaults()
  return read_cache(cache_tag())
end

---The global mappings a pristine Neovim of this version has.
---
---Asks a child Neovim started with `--clean` (no config, no plugin manager)
---and caches the answer per Neovim version in `stdpath("cache")`, so the
---child runs once per upgrade. Blocking while the child runs (a fraction of a
---second).
---
---Never raises and never notifies: a missing executable, a timeout or
---unreadable output come back as `nil, err`, and the caller decides what to
---tell the user.
---@param opts? { refresh?: boolean, timeout?: integer } # `timeout` in ms, default 10000.
---@return Lib.Keymap.RuntimeEntry[]|nil entries
---@return string|nil err
function M.pristine_defaults(opts)
  opts = opts or {}
  local tag = cache_tag()
  if not opts.refresh and memo and memo.tag == tag then
    return memo.entries
  end

  local dir = cache_dir()
  if not opts.refresh then
    local cached = read_cache(tag)
    if cached then
      return cached
    end
  end

  local script = dir .. "/keymap-defaults-probe.lua"
  pcall(vim.fn.mkdir, dir, "p")
  local f = io.open(script, "w")
  if not f then
    return nil, "cannot write the probe script under " .. dir
  end
  f:write(PROBE)
  f:close()

  local started, proc = pcall(vim.system, {
    vim.v.progpath,
    "--clean",
    "--headless",
    "-n",
    "-i",
    "NONE",
    "-l",
    script,
  }, { text = true })
  if not started then
    return nil, "cannot start " .. tostring(vim.v.progpath) .. ": " .. tostring(proc)
  end
  local res = proc:wait(opts.timeout or 10000)
  if not res then
    -- `wait(timeout)` returns nothing when the child outlives the timeout and the
    -- SIGKILL that follows has not been reaped within the same time again.
    pcall(proc.kill, proc, 9)
    res = proc:wait(2000)
  end
  if not res then
    return nil, "the clean Neovim did not finish in time"
  end
  if res.code ~= 0 then
    local why = res.signal ~= 0 and ("signal " .. res.signal) or ("exit code " .. res.code)
    return nil, ("the clean Neovim failed (%s): %s"):format(why, vim.trim(res.stderr or ""))
  end
  local ok, raw =
    pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
  if not ok or type(raw) ~= "table" then
    return nil, "the clean Neovim printed no readable mapping list"
  end
  local entries = to_entries(raw)
  if #entries == 0 then
    return nil, "the clean Neovim reported no mappings"
  end

  local out = io.open(cache_file(tag), "w")
  if out then
    out:write(res.stdout)
    out:close()
  end
  memo = { tag = tag, entries = entries }
  return entries
end

---@internal
---@param e Lib.Keymap.RuntimeEntry
---@return string
local function identity(e)
  return e.mode .. "\0" .. (e.key or lhs_mod.normalize(e.lhs))
end

---@internal
---@param a Lib.Keymap.RuntimeEntry
---@param b Lib.Keymap.RuntimeEntry
---@return boolean
local function same_content(a, b)
  return a.rhs == b.rhs
    and (a.desc or "") == (b.desc or "")
    and (a.callback or false) == (b.callback or false)
    and (a.expr or false) == (b.expr or false)
end

---Set a pristine Neovim's mappings against the live ones.
---
---- `overridden`: the same mode and key is bound now, but not by Neovim's
---  default any more (`origin` is not `builtin`), or its target or description
---  differ.
---- `removed`: the default has no live counterpart -- deleted, or switched off
---  (`false` in a plugin's keymap spec), or its plugin is not loaded here.
---
---`<Plug>(...)` mappings are skipped -- they are how a bundled plugin (matchit)
---wires its real keys, not keys anyone presses.
---
---Pure: tables in, table out. Only global live mappings count (a
---buffer-local one does not replace a default, it shadows it in one buffer).
---@param pristine Lib.Keymap.RuntimeEntry[]
---@param live Lib.Keymap.RuntimeEntry[]
---@return Lib.Keymap.DefaultsDiff
function M.diff_defaults(pristine, live)
  ---@type table<string, Lib.Keymap.RuntimeEntry>
  local now = {}
  for _, e in ipairs(live) do
    if e.buffer == nil then
      now[identity(e)] = e
    end
  end

  local overridden, removed, unchanged = {}, {}, 0
  for _, d in ipairs(pristine) do
    local lv = now[identity(d)]
    if (d.key or d.lhs):find("^<Plug>") then
      -- An implementation detail of a bundled plugin (matchit): nobody types it, and
      -- switching the plugin off would otherwise list a dozen of them as "removed".
    elseif not lv then
      removed[#removed + 1] = d
    elseif (lv.origin ~= nil and lv.origin ~= "builtin") or not same_content(d, lv) then
      overridden[#overridden + 1] = { default = d, live = lv }
    else
      unchanged = unchanged + 1
    end
  end

  local function order(a, b)
    return (a.key or a.lhs) .. a.mode < (b.key or b.lhs) .. b.mode
  end
  table.sort(removed, order)
  table.sort(overridden, function(a, b)
    return order(a.default, b.default)
  end)
  return { overridden = overridden, removed = removed, unchanged = unchanged }
end

---@internal
--- A description without the decoration plugins put in front of it, so
--- `[files] open` and `files: open` and `open` compare equal.
---@param desc string|nil
---@return string|nil
local function normalize_desc(desc)
  if not desc or desc == "" then
    return nil
  end
  local d = desc:gsub("^%[[^%]]+%]%s*", ""):gsub("^[%w%._%-/]+:%s*", "")
  d = d:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return d ~= "" and d or nil
end

---Mappings that look like one action on several keys.
---
---Groups live mappings of the same mode and scope by normalized description
---(a leading `[plugin] ` or `plugin: ` is dropped) and, separately, by
---identical string target. A group with more than one key is a *candidate*:
---two keys for one action is often exactly what was meant, and `<Nop>` is
---skipped because it is shared by design. Neovim's own defaults are left out
---unless `opts.builtin` is set.
---@param live Lib.Keymap.RuntimeEntry[]
---@param opts? { builtin?: boolean }
---@return Lib.Keymap.DuplicateCandidate[]
function M.action_duplicates(live, opts)
  opts = opts or {}
  ---@type table<string, Lib.Keymap.DuplicateCandidate>
  local groups = {}
  local order = {}

  ---@param kind "desc"|"rhs"
  ---@param e Lib.Keymap.RuntimeEntry
  ---@param value string
  local function add(kind, e, value)
    local gk = table.concat({ kind, e.mode, lhs_mod.scope(e.buffer), value }, "\0")
    local g = groups[gk]
    if not g then
      g = { kind = kind, mode = e.mode, buffer = e.buffer, value = value, entries = {} }
      groups[gk] = g
      order[#order + 1] = gk
    end
    for _, seen in ipairs(g.entries) do
      if (seen.key or seen.lhs) == (e.key or e.lhs) then
        return
      end
    end
    g.entries[#g.entries + 1] = e
  end

  for _, e in ipairs(live) do
    if opts.builtin or e.origin ~= "builtin" then
      local d = normalize_desc(e.desc)
      if d then
        add("desc", e, d)
      end
      if e.rhs and e.rhs ~= "" and not e.callback and e.rhs:lower() ~= "<nop>" then
        add("rhs", e, e.rhs)
      end
    end
  end

  local out = {}
  for _, gk in ipairs(order) do
    local g = groups[gk]
    if #g.entries > 1 then
      table.sort(g.entries, function(a, b)
        return (a.key or a.lhs) < (b.key or b.lhs)
      end)
      out[#out + 1] = g
    end
  end
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end
    if a.mode ~= b.mode then
      return a.mode < b.mode
    end
    return a.value < b.value
  end)
  return out
end

---@internal
---@param e Lib.Keymap.RuntimeEntry
---@return string
local function what_of(e)
  local what = e.rhs or (e.callback and "<Lua function>") or "<nothing>"
  if e.desc then
    what = what .. "  (" .. e.desc .. ")"
  end
  return what
end

---@internal
---@param e Lib.Keymap.RuntimeEntry
---@return string
local function where_of(e)
  if not e.source then
    return ""
  end
  return ("  [%s%s]"):format(slashes(e.source), e.lnum and (":" .. e.lnum) or "")
end

---The defaults report as printable lines.
---@param diff Lib.Keymap.DefaultsDiff
---@param info? { version?: string, total?: integer }
---@return string[]
function M.defaults_lines(diff, info)
  info = info or {}
  local out = {}
  out[#out + 1] = ("Neovim defaults%s%s against this session:"):format(
    info.version and (" (" .. info.version .. ")") or "",
    info.total and (", " .. info.total .. " mappings") or ""
  )
  out[#out + 1] = ("  %d unchanged, %d overridden, %d removed."):format(
    diff.unchanged or 0,
    #diff.overridden,
    #diff.removed
  )
  if #diff.overridden > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "overridden (a default that now does something else):"
    for _, o in ipairs(diff.overridden) do
      out[#out + 1] = ("  %-4s %s"):format(o.default.mode, o.default.key or o.default.lhs)
      out[#out + 1] = ("       was: %s"):format(what_of(o.default))
      out[#out + 1] = ("       now: %s%s"):format(what_of(o.live), where_of(o.live))
    end
  end
  if #diff.removed > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "removed (a default that is not bound any more):"
    for _, r in ipairs(diff.removed) do
      out[#out + 1] = ("  %-4s %-10s was: %s"):format(r.mode, r.key or r.lhs, what_of(r))
    end
  end
  return out
end

---The duplicate candidates as printable lines.
---@param candidates Lib.Keymap.DuplicateCandidate[]
---@return string[]
function M.duplicate_lines(candidates)
  local out = {}
  if #candidates == 0 then
    out[#out + 1] = "no action is bound to more than one key (by description or by target)."
    return out
  end
  out[#out + 1] = ("%d candidate(s) -- one action on several keys; often intended:"):format(
    #candidates
  )
  for _, c in ipairs(candidates) do
    out[#out + 1] = ("  %-4s %s: %s%s"):format(
      c.mode,
      c.kind == "desc" and "same description" or "same target",
      c.value,
      c.buffer and (" (buffer " .. c.buffer .. ")") or ""
    )
    for _, e in ipairs(c.entries) do
      out[#out + 1] = ("       %-14s%s"):format(e.key or e.lhs, where_of(e))
    end
  end
  return out
end

---The running Neovim's version tag, as used in the defaults cache file name.
---@return string
function M.version_tag()
  return version_tag()
end

return M
