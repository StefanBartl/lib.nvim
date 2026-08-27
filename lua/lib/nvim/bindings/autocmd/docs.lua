---@module 'lib.nvim.bindings.autocmd.docs'
--- Write what is registered into `bindings/autocmd/` as markdown, one file per
--- event family.
---
--- The want behind it: a plugin's `bindings/` folder should be where you look
--- to find out what the plugin binds, autocmds included -- without moving the
--- autocmds themselves away from the features that own them, which is what
--- makes them readable in the first place. So the folder gets *references*,
--- generated from `lib.nvim.bindings.autocmd`'s registry, and the code stays
--- where it is.
---
--- Markdown, not Lua. A `.lua` file that is really a listing would pretend to
--- be code that runs, and the next reader would look for its callers.
---
--- **Deliberately not automatic.** An earlier shape of this idea had `setup()`
--- write the files whenever the feature was enabled. That is wrong twice over:
--- writing files is a side effect a plugin should not perform unasked, and the
--- directory it would write into is the *installed* plugin directory -- your
--- repo while developing, and a plugin-manager-owned (often read-only) tree
--- for everybody else. So this is a function a plugin exposes behind its own
--- command, or calls from CI, and never from `setup()`.
---
--- **What the output is and is not.** It is what *this session* registered,
--- which depends on the config that ran: a plugin whose features are half
--- switched off registers half the autocmds. The generated header says so and
--- records the run's own settings where the caller passes them. Treat it as a
--- snapshot of one configuration, not as the plugin's full surface.

local M = {}

--- Event families, in output order. First match wins, so the specific
--- prefixes come before the general ones.
---@type { file: string, title: string, match: fun(event: string): boolean }[]
local FAMILIES = {
  {
    file = "buffer.md",
    title = "Buffer",
    match = function(e)
      return e:match("^Buf") ~= nil
    end,
  },
  {
    file = "window.md",
    title = "Window & Tab",
    match = function(e)
      return e:match("^Win") ~= nil or e:match("^Tab") ~= nil
    end,
  },
  {
    file = "cursor.md",
    title = "Cursor & Text",
    match = function(e)
      return e:match("^Cursor") ~= nil or e:match("^Text") ~= nil or e:match("^Insert") ~= nil
    end,
  },
  {
    file = "filetype.md",
    title = "FileType & Syntax",
    match = function(e)
      return e == "FileType" or e == "Syntax" or e == "ColorScheme"
    end,
  },
  {
    file = "lifecycle.md",
    title = "Session lifecycle",
    match = function(e)
      return e:match("^Vim") ~= nil or e:match("^Session") ~= nil or e:match("^Focus") ~= nil
    end,
  },
  {
    file = "other.md",
    title = "Everything else",
    match = function()
      return true
    end,
  },
}

---@internal
--- Which family an event belongs to.
---@param event string
---@return integer index into FAMILIES
local function family_index(event)
  for i, fam in ipairs(FAMILIES) do
    if fam.match(event) then
      return i
    end
  end
  return #FAMILIES
end

---@internal
--- Which family a record belongs to, by its first event.
---@param record Lib.Autocmd.Record
---@return integer index into FAMILIES
local function family_of(record)
  return family_index(record.events[1] or "")
end

---@internal
--- A path relative to `root`, with forward slashes, when it is inside it.
---@param abs string
---@param root string|nil
---@return string
local function relativize(abs, root)
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

---@internal
--- Was this source path produced inside `root`?
---
--- The registry is global: one session holds records and dispatcher handlers
--- from every plugin that loaded. Writing one repo's docs means keeping only
--- what came out of that repo.
---@param abs string
---@param root string|nil
---@return boolean
local function is_under(abs, root)
  if not root or root == "" then
    return true
  end
  local path = (abs or ""):gsub("\\", "/")
  local prefix = root:gsub("\\", "/"):gsub("/+$", "") .. "/"
  return path:sub(1, #prefix) == prefix
end

---@internal
--- List the handlers behind every dispatcher whose events land in this family.
---
--- A dispatcher is one autocmd fanning out to N handlers, so the record table
--- above can only ever show a single row for it. Left at that, a generated
--- page would say "one autocmd on BufEnter" for a plugin where ten features
--- are listening -- the same failure this whole generator exists to prevent,
--- just one level down. So the handlers get their own table, with the file
--- that registered each one.
---@param lines string[]
---@param title string
---@param opts Lib.Autocmd.Docs.Opts
---@return nil
local function render_dispatchers(lines, title, opts)
  local ok, dispatcher = pcall(require, "lib.nvim.bindings.autocmd.dispatcher")
  if not ok or type(dispatcher.registry) ~= "function" then
    return
  end

  ---@type { entry: Lib.Autocmd.Dispatcher.Entry, handlers: Lib.Autocmd.Dispatcher.HandlerInfo[] }[]
  local shown = {}
  for _, entry in ipairs(dispatcher.registry()) do
    -- A dispatcher belongs to a family the same way a record does: by its
    -- first event. `docs` writes one repo at a time, so handlers registered
    -- from elsewhere are filtered out by source path, not by dispatcher --
    -- two plugins may legitimately share one.
    local fam = FAMILIES[family_index(entry.events[1] or "")]
    if fam and fam.title == title then
      local mine = {}
      for _, h in ipairs(entry.handlers) do
        if is_under(h.src, opts.root) then
          mine[#mine + 1] = h
        end
      end
      if #mine > 0 then
        shown[#shown + 1] = { entry = entry, handlers = mine }
      end
    end
  end

  if #shown == 0 then
    return
  end

  lines[#lines + 1] = "## Dispatched handlers"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "One autocmd per dispatcher, fanning out to the handlers below"
  lines[#lines + 1] = "(`lib.nvim.bindings.autocmd.dispatcher`). They run in the order shown."
  lines[#lines + 1] = ""

  for _, d in ipairs(shown) do
    lines[#lines + 1] = ("### `%s` — `%s`%s"):format(
      d.entry.name,
      table.concat(d.entry.events, "`, `"),
      d.entry.attached and "" or " _(registered, not attached)_"
    )
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| Key | What | Priority | Once | Source |"
    lines[#lines + 1] = "| --- | --- | ---: | --- | --- |"
    for _, h in ipairs(d.handlers) do
      lines[#lines + 1] = ("| `%s` | %s | %d | %s | `%s` |"):format(
        table.concat(h.keys, "`, `"),
        h.desc or "_(no desc)_",
        h.priority,
        h.once and "per buffer" or "-",
        relativize(h.src, opts.root)
      )
    end
    lines[#lines + 1] = ""
  end
end

---@internal
---@param records Lib.Autocmd.Record[]
---@param title string
---@param opts Lib.Autocmd.Docs.Opts
---@return string[]
local function render(records, title, opts)
  local lines = {
    ("# %s autocommands"):format(title),
    "",
    "<!-- GENERATED by lib.nvim.bindings.autocmd.docs — do not edit by hand. -->",
    "",
  }

  if opts.note then
    lines[#lines + 1] = opts.note
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "Registered in the session that generated this file. A configuration that"
  lines[#lines + 1] = "switches features off registers fewer of them, so this is a snapshot of one"
  lines[#lines + 1] = "setup, not the plugin's full surface."
  lines[#lines + 1] = ""

  -- The registry only knows what went through this module. Autocmds created
  -- straight from `vim.api` are real, they fire, and they are invisible here.
  -- Saying so is the difference between an incomplete document and a wrong
  -- one: a reader who is not told assumes the table is the whole list.
  if opts.unregistered and opts.unregistered > 0 then
    lines[#lines + 1] = ("> **Incomplete.** This repository also calls `nvim_create_autocmd` directly in %d place(s)."):format(
      opts.unregistered
    )
    lines[#lines + 1] =
      "> Those autocmds fire but are not registered through `lib.nvim.bindings.autocmd`,"
    lines[#lines + 1] =
      "> so they cannot appear below. Route them through the module to have them listed."
    lines[#lines + 1] = ""
  end

  if #records == 0 then
    lines[#lines + 1] = "_None._"
    lines[#lines + 1] = ""
    return lines
  end

  table.sort(records, function(a, b)
    local ae, be = a.events[1] or "", b.events[1] or ""
    if ae ~= be then
      return ae < be
    end
    return (a.group or "") < (b.group or "")
  end)

  lines[#lines + 1] = "| Event | Group | Scope | What | Source |"
  lines[#lines + 1] = "| --- | --- | --- | --- | --- |"

  for _, r in ipairs(records) do
    local scope = "-"
    if r.buffer then
      scope = "buffer-local"
    elseif type(r.pattern) == "table" then
      scope = table.concat(r.pattern, ", ")
    elseif r.pattern then
      scope = tostring(r.pattern)
    end
    lines[#lines + 1] = ("| `%s` | `%s` | %s | %s | `%s` |"):format(
      table.concat(r.events, "`, `"),
      r.group or "-",
      scope,
      r.desc or "_(no desc)_",
      relativize(r.src, opts.root)
    )
  end

  lines[#lines + 1] = ""

  render_dispatchers(lines, title, opts)

  return lines
end

---@internal
--- The repository root a path belongs to: the directory holding the `lua/`
--- that the path sits under.
---
--- Derived from a source path rather than from `cwd`, because the answer has
--- to be right when the call comes from a plugin's own command while the
--- editor's cwd is some unrelated project.
---@param path string
---@return string|nil root
---@return string|nil plugin  # the first directory under `lua/`
local function repo_of(path)
  local p = (path or ""):gsub("\\", "/")
  local root, rest = p:match("^(.*)/lua/(.+)$")
  if not root then
    return nil, nil
  end
  local plugin = rest:match("^([^/]+)")
  return root, plugin
end

---@internal
--- Where the caller of `write`/`check` lives.
---
--- Level 4: getinfo -> this -> defaults() -> write/check -> the caller.
---@return string
local function caller_file()
  local info = debug.getinfo(4, "S")
  return ((info and info.source) or ""):gsub("^@", "")
end

---@internal
--- Fill in what was not given.
---
--- Every field has one sensible answer in almost every case, and spelling all
--- four out at each call site is four chances to get one subtly wrong -- the
--- `filter` especially, which people write as a group-name prefix and which
--- is then quietly wrong for any group that does not follow the convention.
---@param opts Lib.Autocmd.Docs.Opts|nil
---@return Lib.Autocmd.Docs.Opts
local function defaults(opts)
  opts = vim.deepcopy(opts or {})

  local root, plugin = repo_of(caller_file())
  -- A caller outside any `lua/` tree -- the user command below, a scratch
  -- buffer, `nvim -l` -- has no source path to derive from. The editor's cwd
  -- is where a developer running this by hand is sitting; the plugin name
  -- then comes from reading `<root>/lua` a few lines down.
  if not root then
    root = (vim.fn.getcwd():gsub("\\", "/"))
  end

  opts.root = opts.root or root

  if not plugin and opts.root then
    -- One directory under `<root>/lua` is the plugin; more than one and we
    -- cannot pick, so the caller has to say.
    local entries = vim.fn.readdir(opts.root .. "/lua") or {}
    local dirs = {}
    for _, e in ipairs(entries) do
      if vim.fn.isdirectory(opts.root .. "/lua/" .. e) == 1 then
        dirs[#dirs + 1] = e
      end
    end
    if #dirs == 1 then
      plugin = dirs[1]
    end
  end

  if not opts.dir and opts.root and plugin then
    opts.dir = ("%s/lua/%s/bindings/autocmd"):format(opts.root, plugin)
  end

  -- Filter by SOURCE, not by group name. A record belongs to this repo if it
  -- was created from a file inside it -- which is exactly the question, and
  -- true regardless of what the plugin calls its augroups. The group-prefix
  -- version everyone writes by hand silently drops every group that does not
  -- happen to start with the plugin's name.
  if not opts.filter and opts.root then
    local prefix = opts.root:gsub("/+$", "") .. "/"
    opts.filter = function(r)
      local src = (r.src or ""):gsub("\\", "/")
      return src:sub(1, #prefix) == prefix
    end
  end

  return opts
end

--- Every field is optional; see `defaults()` for what each is inferred from.
--- Pass one only where the guess would be wrong -- a repo with several plugins
--- under `lua/`, say, or a note recording which configuration was used.
---@class Lib.Autocmd.Docs.Opts
---@field dir? string         # Target directory. Default: `<root>/lua/<plugin>/bindings/autocmd`.
---@field filter? fun(record: Lib.Autocmd.Record): boolean  # Default: every record created from a file inside `root`.
---@field root? string        # Repo root. Default: derived from the caller's own source path, else cwd.
---@field note? string        # An extra paragraph for the header, e.g. which config produced this.
---@field unregistered? integer # Direct `nvim_create_autocmd` call sites in the repo; rendered as a warning. Counted automatically when `root` is known.

---@internal
--- The rendered files as `{ [filename] = content }`, without touching disk.
---@param opts Lib.Autocmd.Docs.Opts
---@return table<string, string>
local function build(opts)
  local au = require("lib.nvim.bindings.autocmd")
  local records = au.registered()

  local buckets = {}
  for i = 1, #FAMILIES do
    buckets[i] = {}
  end

  for _, r in ipairs(records) do
    if not opts.filter or opts.filter(r) then
      local i = family_of(r)
      buckets[i][#buckets[i] + 1] = r
    end
  end

  local out = {}
  for i, fam in ipairs(FAMILIES) do
    -- An empty family gets no file rather than a file saying "none": a
    -- directory listing should answer "what kinds of event does this plugin
    -- react to" at a glance, and six files of which four say nothing does not.
    if #buckets[i] > 0 then
      out[fam.file] = table.concat(render(buckets[i], fam.title, opts), "\n")
    end
  end
  return out
end

---Write the files. Creates `opts.dir` if needed.
---@param opts Lib.Autocmd.Docs.Opts|nil
---@return boolean ok
---@return string|nil err
---@return string[] written  # Filenames, for a caller that wants to report them.
function M.write(opts)
  vim.validate("opts", opts, { "table", "nil" })
  opts = defaults(opts)
  if type(opts.dir) ~= "string" then
    return false, "could not infer the target directory — pass `dir`", {}
  end

  local files = build(opts)
  if vim.tbl_isempty(files) then
    return false, "nothing registered — call this after setup(), not before", {}
  end

  if vim.fn.isdirectory(opts.dir) == 0 and vim.fn.mkdir(opts.dir, "p") == 0 then
    return false, ("could not create %s"):format(opts.dir), {}
  end

  local written = {}
  for name, content in pairs(files) do
    local path = opts.dir .. "/" .. name
    local fd, err = io.open(path, "w")
    if not fd then
      return false, ("could not write %s: %s"):format(path, tostring(err)), written
    end
    fd:write(content)
    fd:close()
    written[#written + 1] = name
  end

  table.sort(written)
  return true, nil, written
end

---Compare what is on disk against what would be written, without writing.
---
---For the same reason `:DocMap --check` exists: a generated file committed to
---a repository is a claim, and a claim nobody verifies goes stale. Run it in
---CI and the drift is a failed job instead of a wrong document.
---
---Pass the **same** `opts` you passed to `write` -- `note` and `root` are part
---of the rendered output, so a check with different ones reports drift that
---is not there.
---@param opts Lib.Autocmd.Docs.Opts|nil
---@return boolean up_to_date
---@return string[] stale  # Filenames that differ or are missing.
function M.check(opts)
  vim.validate("opts", opts, { "table", "nil" })
  opts = defaults(opts)
  if type(opts.dir) ~= "string" then
    return false, { "could not infer the target directory — pass `dir`" }
  end

  local files = build(opts)
  local stale = {}
  for name, content in pairs(files) do
    local fd = io.open(opts.dir .. "/" .. name, "r")
    if not fd then
      stale[#stale + 1] = name
    else
      local on_disk = fd:read("*a")
      fd:close()
      if on_disk ~= content then
        stale[#stale + 1] = name
      end
    end
  end
  table.sort(stale)
  return #stale == 0, stale
end

---@internal
--- One line with comments and string literals removed.
---
--- Both matter, and both were found the hard way. `debugging.nvim` mentions
--- `nvim_create_autocmd` thirteen times and creates none -- it is a module
--- that *scans* for them, so every occurrence is a string literal.
--- `buffer-ctx.nvim` emits one inside a boilerplate template. A plain
--- substring count called those repositories the two worst offenders; they
--- are the two cleanest.
---@param line string
---@return string
local function code_only(line)
  line = line:gsub("%-%-.*$", "")
  local out, i, n = {}, 1, #line
  while i <= n do
    local ch = line:sub(i, i)
    if ch == '"' or ch == "'" then
      local quote, j = ch, i + 1
      while j <= n do
        local c = line:sub(j, j)
        if c == "\\" then
          j = j + 2
        elseif c == quote then
          break
        else
          j = j + 1
        end
      end
      i = j + 1
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Marker a plugin can put on a line to say "this one is deliberate".
---
--- Needed for the soft-dependency pattern: a wrapper that prefers this module
--- and falls back to `vim.api` when lib is not installed has a native call
--- site that is *correct*. Counting it would tell the reader a document is
--- incomplete when it is not.
local IGNORE = "lib%-docs: fallback"

---@internal
--- How many autocmds this repository creates without going through the module.
---
--- A static scan, deliberately: those call sites leave no runtime trace to
--- count, which is the whole problem with them. Cheap enough (one pass over
--- the repo's own `lua/`) to run on every write, and the number is only used
--- to warn.
---
--- No call-parenthesis is required, so that
--- `local au = vim.api.nvim_create_autocmd` followed by `au(...)` is counted
--- once rather than missed entirely.
---@param root string
---@return integer
local function count_unregistered(root)
  local n = 0
  local files = vim.fn.globpath(root .. "/lua", "**/*.lua", false, true) or {}
  for _, file in ipairs(files) do
    local fd = io.open(file, "r")
    if fd then
      local previous = ""
      for line in fd:lines() do
        if
          code_only(line):find("nvim_create_autocmd", 1, true)
          and not line:find(IGNORE)
          and not previous:find(IGNORE)
        then
          n = n + 1
        end
        previous = line
      end
      fd:close()
    end
  end
  return n
end

---@class Lib.Autocmd.Docs.AllOpts
---@field under? string   # Only repositories inside this directory. Without it, every repo that registered anything -- including plugins you did not write.
---@field note? string    # Passed through to every repo's header.
---@field dry_run? boolean # Report what would be written, write nothing.

---@class Lib.Autocmd.Docs.AllResult
---@field root string
---@field plugin string
---@field dir string
---@field written string[]
---@field records integer
---@field unregistered integer
---@field err string|nil

---Write `bindings/autocmd` for **every** repository that registered something
---in this session.
---
---The set of repositories comes from the records themselves -- each one knows
---the file it was created from -- and not from scanning a directory. That
---distinction is the point: a directory scan would find repositories that are
---installed but never loaded, and writing their docs would produce an empty
---or truncated file where a correct one already sits. A plugin that did not
---load simply does not appear, which is the honest outcome.
---
---For the same reason this is not a substitute for running it per repo: a
---lazy-loaded plugin whose trigger has not fired yet has registered nothing.
---Load what you want documented first.
---@param opts Lib.Autocmd.Docs.AllOpts|nil
---@return Lib.Autocmd.Docs.AllResult[]  # One entry per repository, sorted by name.
function M.write_all(opts)
  vim.validate("opts", opts, { "table", "nil" })
  opts = opts or {}

  local under = opts.under and (opts.under:gsub("\\", "/"):gsub("/+$", "") .. "/") or nil
  local au = require("lib.nvim.bindings.autocmd")

  ---@type table<string, { plugin: string, n: integer }>
  local repos = {}
  for _, r in ipairs(au.registered()) do
    local root, plugin = repo_of(r.src or "")
    if root and plugin and (not under or root:sub(1, #under) == under) then
      repos[root] = repos[root] or { plugin = plugin, n = 0 }
      repos[root].n = repos[root].n + 1
    end
  end

  local roots = vim.tbl_keys(repos)
  table.sort(roots)

  local results = {}
  for _, root in ipairs(roots) do
    local info = repos[root]
    local dir = ("%s/lua/%s/bindings/autocmd"):format(root, info.plugin)
    local prefix = root .. "/"
    local per_repo = {
      dir = dir,
      root = root,
      note = opts.note,
      unregistered = count_unregistered(root),
      filter = function(r)
        return ((r.src or ""):gsub("\\", "/")):sub(1, #prefix) == prefix
      end,
    }

    local ok, err, written = true, nil
    if opts.dry_run then
      written = vim.tbl_keys(build(per_repo))
      table.sort(written)
    else
      ok, err, written = M.write(per_repo)
    end

    results[#results + 1] = {
      root = root,
      plugin = info.plugin,
      dir = dir,
      written = written,
      records = info.n,
      unregistered = per_repo.unregistered,
      err = (not ok) and err or nil,
    }
  end

  return results
end

---Register `:LibAutocmdDocs` (write) and `:LibAutocmdDocsCheck` (verify).
---
---Opt-in, and meant for a **developer's own config**, not for a plugin to
---ship: it is a tool for the person editing the repo, and every plugin
---registering its own copy would put N identical commands in everyone's
---editor. One line in your config gives you the command in every session:
---
---```lua
---require("lib.nvim.bindings.autocmd").docs.create_usercmd()
---```
---
---Run it with the repo as cwd, after the plugin has loaded.
---@param name string|nil  # Base name, default "LibAutocmdDocs".
---@return nil
function M.create_usercmd(name)
  local base = name or "LibAutocmdDocs"
  local usercmd = require("lib.nvim.bindings.usercmd")
  local notify = require("lib.nvim.notify").create("[lib.autocmd.docs]")

  usercmd.create(base, function()
    local ok, err, written = M.write()
    if not ok then
      notify.warn(err or "could not write")
      return
    end
    notify.info(("wrote %d file(s): %s"):format(#written, table.concat(written, ", ")))
  end, { desc = "Write the registered autocmds into bindings/autocmd as markdown" })

  usercmd.create(base .. "Check", function()
    local up_to_date, stale = M.check()
    if up_to_date then
      notify.info("bindings/autocmd is up to date")
    else
      notify.warn("stale: " .. table.concat(stale, ", "))
    end
  end, { desc = "Check bindings/autocmd against what is registered" })
end

return M
