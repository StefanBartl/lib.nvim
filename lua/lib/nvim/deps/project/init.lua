---@module 'lib.nvim.deps.project'
--- The project view of "what is missing": not "this buffer needs a parser"
--- (that is `lib.nvim.treesitter.parser_policy`, per filetype, when it is
--- needed) but "this root holds files of kinds X, Y and Z, and for them the
--- parsers A, B and the tools C, D are not here".
---
---   scan(root)      async, bounded walk (`deps.project.walk`), counts files
---                   per extension / file name, cached per root (a `:cd` back
---                   to a known root costs nothing)
---   report(scan)    kind -> filetype (`vim.filetype.match`) -> treesitter
---                   language, and the caller's filetype -> tools table
---                   (`report_async`: the same after one Mason registry
---                   refresh, for a machine where Mason never fetched it)
---   lines(report)   the report as text
---   install(report) ONE question, then the existing confirmed ways
---
--- Requiring this module registers nothing and touches nothing; `setup()`
--- only does something with `auto = true`. **Nothing here installs
--- silently**: parsers go through `parser_policy.install`, `bin` tools
--- through `deps.install.run` (a terminal with the command typed, not
--- submitted), Mason packages through the registry API -- each only after
--- `install()` asked, once, with everything it is about to do on screen.
---
--- What a filetype wants is the CALLER's knowledge, handed in as a table
--- `{ [filetype] = tools[] }` (`register_tools`, or `opts.tools`). An entry
--- is a `Lib.Deps.Tool` (`bin`, `pkg`, … as in a plugin's `docs/install.json`)
--- or `{ mason = "package" }`. lsp.nvim registers the Mason packages of its
--- `ensure_install` lists; any plugin can register what its `install.json`
--- already says, keyed by the filetypes that need it.

require("lib.nvim.deps.project.@types")

local M = {}

---@internal
---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[lib.nvim.deps.project]")
end

---@type integer
local DEFAULT_TTL = 600

-- --------------------------------------------------------------------- scan

---@type table<string, Lib.Deps.Project.Scan> root -> last complete scan
local CACHE = {}

---@type table<string, { waiters: (fun(scan: Lib.Deps.Project.Scan))[], cancel: fun() }> root -> walk in progress
local INFLIGHT = {}

---@internal
---@param root string
---@return string
local function normalize(root)
  local n = vim.fs.normalize(root)
  if #n > 1 and n:sub(-1) == "/" and not n:match("^%a:/$") then
    n = n:sub(1, -2)
  end
  return n
end

---The key a file counts under: `"*.lua"` for a file with an extension (the
---last one, lower-cased), the bare name (`"Makefile"`, `".gitignore"`) for one
---without.
---@param path string
---@return string key
function M.key_of(path)
  return require("lib.nvim.deps.project.walk").key_of(path)
end

---Count `paths` per kind. Pure; the shape `scan` caches and `report` reads.
---@param root string
---@param paths string[]
---@param errors? string[]|nil
---@return Lib.Deps.Project.Scan
function M.count(root, paths, errors)
  local walk = require("lib.nvim.deps.project.walk")
  local keys = {}
  for _, path in ipairs(paths) do
    walk.add(keys, path)
  end
  return {
    root = normalize(root),
    total = #paths,
    keys = keys,
    errors = errors,
    at = os.time(),
  }
end

---Basenames of `lib.nvim.fs.ignore.list` that ARE project content for this
---question: `.github` holds the workflows (YAML) a project ships.
---@type string[]
M.IGNORE_KEEP = { ".github" }

---The default walk filter: the basenames of `lib.nvim.fs.ignore.list`
---(VCS directories, dependency stores, caches, editor state and the build
---output names `build`, `dist`, `out`, `target`, `bin`, `obj` -- a `bin/` of
---scripts is pruned too) except `IGNORE_KEEP`, applied to directories and
---files alike, case-insensitively where the file system is (Windows).
---@return fun(abs_path: string, is_dir: boolean): boolean
function M.default_ignore()
  local list = require("lib.nvim.fs.ignore.list")
  local set = list.as_set()
  for _, name in ipairs(M.IGNORE_KEEP) do
    set[list.normalize(name)] = nil
  end
  return function(abs_path)
    return set[list.normalize(abs_path:match("([^/\\]+)$") or abs_path)] == true
  end
end

---@internal
---Would a cached scan answer a request with these limits? A complete scan
---answers anything; a truncated one only a request whose limits are not
---larger than the ones it stopped at.
---@param hit Lib.Deps.Project.Scan
---@param limits Lib.Deps.Project.Limits
---@return boolean
local function covers(hit, limits)
  if not hit.truncated then
    return true
  end
  local had = hit.limits or {}
  for _, key in ipairs({ "max_files", "max_depth", "max_ms" }) do
    if (limits[key] or 0) > (had[key] or 0) then
      return false
    end
  end
  return true
end

---Count the files under `root`, asynchronously, and remember the answer.
---
---The walk (`deps.project.walk`) keeps only counts, and stops at
---`max_files` files, `max_ms` milliseconds, or prunes below `max_depth`
---levels (defaults `walk.DEFAULTS`); `scan.truncated` names the limit that
---cut it short. A walk that raised (a throwing `opts.ignore`) is delivered
---with `scan.failed`, so no caller ever waits forever.
---
---A repeat call within `ttl_seconds` (default 600) answers from the cache
---without touching the disk, so wiring this to `DirChanged` does not rescan
---on every `:cd`; `refresh = true` walks again. Cached: every scan whose
---root could be read -- also one where some subdirectory could not
---(`scan.errors`), and a truncated one (it answers later requests with the
---same or smaller limits). Not cached: an unreadable root (a momentarily
---unreadable root would otherwise answer "nothing here" for the whole TTL)
---and a failed walk. Two callers asking for the same root while a walk is
---running share it (with the first caller's limits).
---
---`on_done` always runs on the main loop, also for a cache hit.
---@param root string
---@param opts? Lib.Deps.Project.ScanOpts
---@param on_done fun(scan: Lib.Deps.Project.Scan)
---@return fun() cancel stop waiting; `on_done` will not fire (the walk itself stops once nobody waits)
function M.scan(root, opts, on_done)
  opts = opts or {}
  root = normalize(root)
  local ttl = opts.ttl_seconds or DEFAULT_TTL
  local defaults = require("lib.nvim.deps.project.walk").DEFAULTS
  ---@type Lib.Deps.Project.Limits
  local limits = {
    max_files = opts.max_files or defaults.max_files,
    max_depth = opts.max_depth or defaults.max_depth,
    max_ms = opts.max_ms or defaults.max_ms,
  }

  local hit = CACHE[root]
  if hit and not opts.refresh and os.time() - hit.at < ttl and covers(hit, limits) then
    local cancelled = false
    vim.schedule(function()
      if not cancelled then
        on_done(hit)
      end
    end)
    return function()
      cancelled = true
    end
  end

  local flight = INFLIGHT[root]
  if not flight then
    flight = { waiters = {}, cancel = function() end }
    INFLIGHT[root] = flight
    local walk_opts = {
      ignore = opts.ignore or M.default_ignore(),
      max_files = limits.max_files,
      max_depth = limits.max_depth,
      max_ms = limits.max_ms,
    }
    flight.cancel = require("lib.nvim.deps.project.walk").run(root, walk_opts, function(result)
      if INFLIGHT[root] == flight then
        INFLIGHT[root] = nil
      end
      ---@type Lib.Deps.Project.Scan
      local scan = {
        root = root,
        total = result.total,
        keys = result.keys,
        errors = result.errors,
        truncated = result.truncated,
        failed = result.failed,
        limits = limits,
        at = os.time(),
      }
      if not result.failed and not result.root_unreadable then
        CACHE[root] = scan
      end
      for _, waiter in ipairs(flight.waiters) do
        waiter(scan)
      end
    end)
  end

  local mine = on_done
  flight.waiters[#flight.waiters + 1] = mine
  return function()
    for i, waiter in ipairs(flight.waiters) do
      if waiter == mine then
        table.remove(flight.waiters, i)
        break
      end
    end
    if #flight.waiters == 0 and INFLIGHT[root] == flight then
      INFLIGHT[root] = nil
      flight.cancel()
    end
  end
end

---Forget the cached scan of `root` (or of every root).
---@param root? string
---@return nil
function M.forget(root)
  if root then
    CACHE[normalize(root)] = nil
  else
    CACHE = {}
  end
end

-- -------------------------------------------------------------- tools table

---@type table<string, Lib.Deps.Project.ToolMap|fun(): Lib.Deps.Project.ToolMap>
local REGISTERED = {}

---Say which tools a filetype wants. `owner` names the plugin (registering
---again under the same name replaces its table). The table may be a function,
---called at report time, for a plugin whose list is only known after its own
---`setup()`.
---
---```lua
---require("lib.nvim.deps.project").register_tools("lsp.nvim", {
---  lua = { { mason = "lua-language-server" }, { mason = "stylua" } },
---  python = { { mason = "pyright" } },
---  markdown = { { bin = "pandoc", why = "Export", pkg = { winget = "JohnMacFarlane.Pandoc" } } },
---})
---```
---@param owner string
---@param tools Lib.Deps.Project.ToolMap|fun(): Lib.Deps.Project.ToolMap
---@return fun() unregister
function M.register_tools(owner, tools)
  REGISTERED[owner] = tools
  return function()
    if REGISTERED[owner] == tools then
      REGISTERED[owner] = nil
    end
  end
end

---Owners that registered a tools table, sorted.
---@return string[]
function M.registered()
  local out = {}
  for owner in pairs(REGISTERED) do
    out[#out + 1] = owner
  end
  table.sort(out)
  return out
end

---@internal
---@param source Lib.Deps.Project.ToolMap|fun(): Lib.Deps.Project.ToolMap|nil
---@param label string
---@param problems string[]
---@return Lib.Deps.Project.ToolMap
local function resolve_source(source, label, problems)
  if type(source) == "function" then
    local ok, value = pcall(source)
    if not ok then
      problems[#problems + 1] = ("%s: tools function failed: %s"):format(label, tostring(value))
      return {}
    end
    source = value
  end
  if type(source) ~= "table" then
    return {}
  end
  return source
end

---@internal
---Normalize one caller-supplied entry; nil plus a reason when it is unusable.
---@param entry any
---@return { id: string, kind: "bin"|"mason", tool: Lib.Deps.Project.ToolEntry }|nil normalized
---@return string|nil problem
local function normalize_entry(entry)
  if type(entry) ~= "table" then
    return nil, "entry is not a table"
  end
  if type(entry.mason) == "string" and entry.mason ~= "" then
    return { id = entry.mason, kind = "mason", tool = entry }, nil
  end
  if type(entry.bin) == "string" and entry.bin ~= "" then
    local tool = vim.tbl_extend("force", {}, entry)
    tool.pkg = type(entry.pkg) == "table" and entry.pkg or {}
    tool.why = type(entry.why) == "string" and entry.why or ""
    tool.required = entry.required == true
    return { id = entry.bin, kind = "bin", tool = tool }, nil
  end
  return nil, "entry has neither `bin` nor `mason`"
end

-- ------------------------------------------------------------------- report

---@internal
---Kind -> filetype for every counted kind, via `vim.filetype.match` on one
---real sample path of that kind. Two paths of one extension can in principle
---resolve differently (a pattern keyed on a directory); the sample decides.
---@param keys table<string, Lib.Deps.Project.KeyCount>
---@return table<string, integer> files_by_filetype
---@return integer unmapped
local function by_filetype(keys)
  local files, unmapped = {}, 0
  for _, entry in pairs(keys) do
    local ok, ft = pcall(vim.filetype.match, { filename = entry.sample })
    if ok and type(ft) == "string" and ft ~= "" then
      files[ft] = (files[ft] or 0) + entry.count
    else
      unmapped = unmapped + entry.count
    end
  end
  return files, unmapped
end

---Turn a scan into the report: which languages the root needs and which of
---their parsers are missing, which tools its filetypes want and which of
---those are missing. Reads state (installed parsers, PATH, Mason), changes
---none.
---@param scan Lib.Deps.Project.Scan
---@param opts? Lib.Deps.Project.ReportOpts
---@return Lib.Deps.Project.Report
function M.report(scan, opts)
  opts = opts or {}
  local policy = require("lib.nvim.treesitter.parser_policy")
  local detect = require("lib.nvim.deps.detect")
  local mason = require("lib.nvim.deps.project.mason")

  local files_of, unmapped = by_filetype(scan.keys)

  -- Deterministic order everywhere below: filetypes by name.
  local fts = vim.tbl_keys(files_of)
  table.sort(fts)

  local declined = {}
  for _, lang in ipairs(policy.declined()) do
    declined[lang] = true
  end

  ---@type table<string, Lib.Deps.Project.Language>
  local by_lang = {}
  for _, ft in ipairs(fts) do
    local lang = vim.treesitter.language.get_lang(ft)
    if lang and lang ~= "" then
      local entry = by_lang[lang]
      if not entry then
        entry = { lang = lang, filetypes = {}, files = 0, state = policy.status(lang) }
        if entry.state == "available" and declined[lang] then
          entry.state = "declined"
        end
        by_lang[lang] = entry
      end
      entry.filetypes[#entry.filetypes + 1] = ft
      entry.files = entry.files + files_of[ft]
    end
  end

  local function by_files(a, b)
    if a.files ~= b.files then
      return a.files > b.files
    end
    return (a.lang or a.id) < (b.lang or b.id)
  end

  local languages, missing_parsers = {}, {}
  for _, entry in pairs(by_lang) do
    languages[#languages + 1] = entry
  end
  table.sort(languages, by_files)
  for _, entry in ipairs(languages) do
    if entry.state == "available" or entry.state == "declined" then
      missing_parsers[#missing_parsers + 1] = entry
    end
  end

  -- The caller's tools: everything registered, then `opts.tools`.
  local problems = {}
  local maps = {}
  if opts.registered ~= false then
    for _, owner in ipairs(M.registered()) do
      maps[#maps + 1] = resolve_source(REGISTERED[owner], owner, problems)
    end
  end
  if opts.tools ~= nil then
    maps[#maps + 1] = resolve_source(opts.tools, "opts.tools", problems)
  end

  ---@type table<string, Lib.Deps.Project.ToolStatus>
  local seen = {}
  local tools = {}
  for _, ft in ipairs(fts) do
    for _, map in ipairs(maps) do
      local list = map[ft]
      if type(list) == "table" then
        for _, raw in ipairs(list) do
          local norm, problem = normalize_entry(raw)
          if not norm then
            problems[#problems + 1] = ("%s: %s"):format(ft, problem)
          else
            local ident = norm.kind .. ":" .. norm.id
            local status = seen[ident]
            if not status then
              local state
              if norm.kind == "mason" then
                state = mason.status(norm.id)
              else
                state = detect.found(norm.tool) and "present" or "missing"
              end
              status = {
                id = norm.id,
                kind = norm.kind,
                tool = norm.tool,
                filetypes = {},
                files = 0,
                state = state,
              }
              seen[ident] = status
              tools[#tools + 1] = status
            end
            if not vim.list_contains(status.filetypes, ft) then
              status.filetypes[#status.filetypes + 1] = ft
              status.files = status.files + files_of[ft]
            end
          end
        end
      end
    end
  end
  table.sort(tools, by_files)

  local missing_tools = {}
  for _, status in ipairs(tools) do
    if status.state == "missing" then
      missing_tools[#missing_tools + 1] = status
    end
  end

  return {
    root = scan.root,
    total = scan.total,
    errors = scan.errors,
    truncated = scan.truncated,
    failed = scan.failed,
    limits = scan.limits,
    languages = languages,
    missing_parsers = missing_parsers,
    tools = tools,
    missing_tools = missing_tools,
    unmapped = unmapped,
    problems = problems,
  }
end

---`report()`, but with a Mason registry that has been fetched at least once.
---
---On a fresh machine Mason has never fetched its registry, and until it has,
---every package reads as `unavailable` -- nothing would ever be offered. So
---when the report holds an `unavailable` Mason entry, the registry is
---refreshed once (`deps.project.mason.refresh`: Mason's own age-gated
---`registry.refresh`, a download of the registry index only when it is
---missing or stale; nothing is installed) and the report is built again.
---Without such an entry `on_done` is called right away, before this returns.
---@param scan Lib.Deps.Project.Scan
---@param opts? Lib.Deps.Project.ReportOpts
---@param on_done fun(report: Lib.Deps.Project.Report)
---@return nil
function M.report_async(scan, opts, on_done)
  local report = M.report(scan, opts)
  for _, status in ipairs(report.tools) do
    if status.kind == "mason" and status.state == "unavailable" then
      require("lib.nvim.deps.project.mason").refresh(function()
        on_done(M.report(scan, opts))
      end)
      return
    end
  end
  on_done(report)
end

-- -------------------------------------------------------------------- lines

---@internal
---@param ft_list string[]
---@param files integer
---@return string
local function wanted_by(ft_list, files)
  return ("%s, %d file%s"):format(table.concat(ft_list, "/"), files, files == 1 and "" or "s")
end

---The report as text.
---@param report Lib.Deps.Project.Report
---@param opts? Lib.Deps.ManagerOpts
---@return string[] lines
function M.lines(report, opts)
  local out = {}
  local function add(s)
    out[#out + 1] = s
  end

  add("# Project scan — " .. report.root)
  add("")
  add(
    ("Files: %d  ·  languages: %d  ·  parsers missing: %d  ·  tools missing: %d"):format(
      report.total,
      #report.languages,
      #report.missing_parsers,
      #report.missing_tools
    )
  )
  if report.unmapped > 0 then
    add(("%d file(s) have no known filetype and were not considered."):format(report.unmapped))
  end
  if report.errors then
    add(
      ("%d director%s could not be read; the counts are partial."):format(
        #report.errors,
        #report.errors == 1 and "y" or "ies"
      )
    )
  end
  if report.truncated then
    local limits = report.limits or {}
    local why = {
      max_files = ("it stopped after %s files"):format(tostring(limits.max_files)),
      max_ms = ("it stopped after %s ms"):format(tostring(limits.max_ms)),
      max_depth = ("directories deeper than %s levels were skipped"):format(
        tostring(limits.max_depth)
      ),
    }
    add(
      ("The walk was cut short (%s); the counts are partial."):format(
        why[report.truncated] or report.truncated
      )
    )
  end
  if report.failed then
    add(("The walk failed: %s; the counts are partial."):format(report.failed))
  end
  add("")

  if #report.missing_parsers > 0 then
    add("## Treesitter parsers not installed")
    add("")
    for _, entry in ipairs(report.missing_parsers) do
      add(
        ("- %s  (%s)%s"):format(
          entry.lang,
          wanted_by(entry.filetypes, entry.files),
          entry.state == "declined" and '  — you said "Never"; not offered' or ""
        )
      )
    end
    add("")
  end

  if #report.missing_tools > 0 then
    local plan_tools = {}
    add("## Tools missing")
    add("")
    for _, status in ipairs(report.missing_tools) do
      local why = status.tool.why
      add(
        ("- [missing] %s  (%s)%s%s"):format(
          status.id,
          wanted_by(status.filetypes, status.files),
          status.kind == "mason" and "  — Mason package" or "",
          (type(why) == "string" and why ~= "") and ("  — " .. why) or ""
        )
      )
      if status.kind == "bin" then
        plan_tools[#plan_tools + 1] = status.tool
      end
    end
    if #plan_tools > 0 then
      local plan = require("lib.nvim.deps.install").plan(plan_tools, opts)
      local pm = require("lib.nvim.deps.pm")
      if plan.manager and #plan.commands > 0 then
        add("")
        add(("Install the `bin` tools with %s:"):format(plan.manager.id))
        for _, argv in ipairs(plan.commands) do
          add("    " .. pm.render(argv))
        end
      elseif not plan.manager then
        add("")
        add("No supported package manager found — the `bin` tools must be installed by hand.")
      end
      if plan.manager and #plan.unsupported > 0 then
        local names = {}
        for _, tool in ipairs(plan.unsupported) do
          names[#names + 1] = tool.bin
        end
        add("")
        add(
          ("No %s package is declared for: %s"):format(plan.manager.id, table.concat(names, ", "))
        )
      end
    end
    add("")
  end

  local unusable = {}
  for _, status in ipairs(report.tools) do
    if status.state == "unavailable" then
      unusable[#unusable + 1] = status.id
        .. " (not in the Mason registry — typo, or never fetched)"
    elseif status.state == "unknown" then
      unusable[#unusable + 1] = status.id .. " (Mason not loadable)"
    end
  end
  if #unusable > 0 then
    add("## Could not be checked")
    add("")
    for _, line in ipairs(unusable) do
      add("- " .. line)
    end
    add("")
  end

  if #report.problems > 0 then
    add("## Tools table problems")
    add("")
    for _, problem in ipairs(report.problems) do
      add("- " .. problem)
    end
    add("")
  end

  if #report.missing_parsers == 0 and #report.missing_tools == 0 then
    if report.errors or report.truncated or report.failed then
      add("Nothing missing for the files that were counted — the scan was partial (see above).")
    elseif #unusable > 0 then
      add('Nothing missing among what could be checked — see "Could not be checked".')
    else
      add("Nothing missing for the files in this root.")
    end
  else
    add("`:Lib deps project install` asks once, then installs what is listed above.")
  end
  return out
end

---One line for a notification, or nil when nothing is missing.
---@param report Lib.Deps.Project.Report
---@return string|nil
function M.summary(report)
  local parsers, tools = {}, {}
  for _, entry in ipairs(report.missing_parsers) do
    if entry.state == "available" then
      parsers[#parsers + 1] = entry.lang
    end
  end
  for _, status in ipairs(report.missing_tools) do
    tools[#tools + 1] = status.id
  end
  if #parsers == 0 and #tools == 0 then
    return nil
  end
  local parts = {}
  if #parsers > 0 then
    parts[#parts + 1] = "parsers: " .. table.concat(parsers, ", ")
  end
  if #tools > 0 then
    parts[#parts + 1] = "tools: " .. table.concat(tools, ", ")
  end
  -- The tail names the root; a filesystem or drive root has none.
  local name = vim.fn.fnamemodify(report.root, ":t")
  return ("%s — missing %s  (:Lib deps project)"):format(
    name ~= "" and name or report.root,
    table.concat(parts, "; ")
  )
end

-- ------------------------------------------------------------------ install

---What `install` would do, and the question it would ask. Pure.
---@param report Lib.Deps.Project.Report
---@param opts? Lib.Deps.ManagerOpts
---@return Lib.Deps.Project.InstallPlan
function M.install_plan(report, opts)
  local parsers, declined = {}, {}
  for _, entry in ipairs(report.missing_parsers) do
    if entry.state == "declined" then
      declined[#declined + 1] = entry.lang
    else
      parsers[#parsers + 1] = entry.lang
    end
  end

  local mason, tools = {}, {}
  for _, status in ipairs(report.missing_tools) do
    if status.kind == "mason" then
      mason[#mason + 1] = status.id
    else
      tools[#tools + 1] = status.tool
    end
  end

  local plan = #tools > 0 and require("lib.nvim.deps.install").plan(tools, opts) or nil

  local text = { ("Install what %s is missing?"):format(report.root), "" }
  if #parsers > 0 then
    text[#text + 1] = "Treesitter parsers (installed in the background):"
    text[#text + 1] = "  " .. table.concat(parsers, ", ")
  end
  if #mason > 0 then
    text[#text + 1] = "Mason packages (installed in the background, headless):"
    text[#text + 1] = "  " .. table.concat(mason, ", ")
  end
  if plan then
    local pm = require("lib.nvim.deps.pm")
    if #plan.commands > 0 then
      text[#text + 1] = "Tools (typed into a terminal for you to submit):"
      for _, argv in ipairs(plan.commands) do
        text[#text + 1] = "  " .. pm.render(argv)
      end
    end
    if #plan.unsupported > 0 then
      local names = {}
      for _, tool in ipairs(plan.unsupported) do
        names[#names + 1] = tool.bin
      end
      text[#text + 1] = "Not covered (no package for this host): " .. table.concat(names, ", ")
    end
  end
  if #declined > 0 then
    text[#text + 1] = 'Left out, you said "Never": ' .. table.concat(declined, ", ")
  end

  local empty = #parsers == 0 and #mason == 0 and not (plan and #plan.commands > 0)
  return {
    parsers = parsers,
    mason = mason,
    tools = tools,
    plan = plan,
    declined = declined,
    text = table.concat(text, "\n"),
    empty = empty,
  }
end

---Ask once, then start everything `install_plan` lists. Returns what was
---started, or nil when there was nothing to do or the user said no.
---
---The question is the shared dialog (`lib.nvim.ui.dialog.yesno`, "No" first and
---focused), so the answer comes on a later loop turn: the return value is `nil`
---while it is open, and `opts.on_done(started)` says how it ended (`nil` for
---nothing to do or a no). When nothing is asked, `on_done` runs before this returns.
---
---  * parsers   -> `parser_policy.install` (nvim-treesitter, background)
---  * Mason     -> the registry API, headless (see `deps.project.mason`)
---  * `bin`     -> `deps.install.run`: a terminal with the command typed and
---                 NOT submitted, so a `sudo` prompt is answered by you
---@param report Lib.Deps.Project.Report
---@param opts? Lib.Deps.Project.InstallOpts
---@return { parsers: string[], mason: string[], terminal: boolean }|nil started
function M.install(report, opts)
  opts = opts or {}
  local plan = M.install_plan(report, opts)

  ---@param started { parsers: string[], mason: string[], terminal: boolean }|nil
  ---@return { parsers: string[], mason: string[], terminal: boolean }|nil
  local function done(started)
    if opts.on_done then
      opts.on_done(started)
    end
    return started
  end

  if plan.empty then
    notify().info("Nothing to install for " .. report.root .. ".")
    return done(nil)
  end

  local function start()
    local started = { parsers = {}, mason = {}, terminal = false }

    local policy = require("lib.nvim.treesitter.parser_policy")
    for _, lang in ipairs(plan.parsers) do
      if policy.install(lang) then
        started.parsers[#started.parsers + 1] = lang
      end
    end

    if #plan.mason > 0 then
      started.mason = vim.deepcopy(plan.mason)
      require("lib.nvim.deps.project.mason").install(plan.mason, function(name, ok, err)
        if ok then
          notify().info(("Mason package '%s' installed"):format(name))
        else
          notify().warn(("Mason package '%s' not installed: %s"):format(name, tostring(err)))
        end
      end)
    end

    -- Last: it opens a split and starts insert mode.
    if plan.plan and #plan.plan.commands > 0 then
      started.terminal = require("lib.nvim.deps.install").run(plan.plan, { confirm = false })
    end

    return done(started)
  end

  if opts.confirm ~= false then
    require("lib.nvim.ui.dialog").yesno(plan.text, "install", function(yes)
      if yes then
        start()
      else
        done(nil)
      end
    end)
    return nil
  end
  return start()
end

-- ---------------------------------------------------------------- surfaces

---@internal
---@param report Lib.Deps.Project.Report
---@param opts? Lib.Deps.Project.InstallOpts
local function open_view(report, opts)
  local lines = M.lines(report, opts)
  local ok_kit, kit = pcall(require, "lib.nvim.ui.kit")
  local surf = ok_kit
      and kit.viewer({
        lines = lines,
        title = "project scan",
        filetype = "lib-deps-view",
        width = 84,
      })
    or nil
  if not surf then
    require("lib.nvim.window.open_named_scratch")(
      "lib.nvim://deps/project",
      lines,
      { filetype = "markdown", modifiable = false }
    )
    return
  end
  vim.keymap.set("n", "I", function()
    M.install(report, opts)
  end, { buffer = surf.bufnr, desc = "Install what this project is missing" })
end

---`:Lib deps project [refresh|install]`: scan `root` (default: the current
---directory), then show the report, or ask and install.
---@param root? string
---@param action? "refresh"|"install"|nil
---@param opts? Lib.Deps.Project.ReportOpts
---@return nil
function M.run(root, action, opts)
  root = root or vim.fn.getcwd()
  local n = notify()
  n.info("Scanning " .. normalize(root) .. " …")
  M.scan(root, { refresh = action == "refresh" }, function(scan)
    M.report_async(scan, opts, function(report)
      if action == "install" then
        M.install(report)
      else
        open_view(report)
      end
    end)
  end)
end

-- ------------------------------------------------------------------ trigger

local AUGROUP = "lib.nvim.deps.project"

---@type Lib.Deps.Project.SetupOpts
local SETUP = {}

---@type table<string, string> root -> the summary last announced for it
local ANNOUNCED = {}

---The walk limits of a scan the trigger starts (each overridable through
---`setup`): a `:cd` is not a request to walk a whole disk.
---@type Lib.Deps.Project.Limits
M.TRIGGER_LIMITS = { max_files = 20000, max_depth = 12, max_ms = 5000 }

---@type fun()|nil cancels the trigger's scan that is still running
local PENDING

---@internal
---@param a string
---@param b string
---@return boolean
local function same_path(a, b)
  if package.config:sub(1, 1) == "\\" then
    return a:lower() == b:lower()
  end
  return a == b
end

---Is `root` too broad to scan just because the working directory went there:
---the home directory, a filesystem or drive root (`/`, `C:/`), a UNC share
---root (`//server/share`). The trigger skips these; `:Lib deps project`
---still scans them when asked.
---@param root string
---@return boolean
function M.is_broad_root(root)
  root = normalize(root)
  if root == "/" or root:match("^%a:/?$") or root:match("^//[^/]+/[^/]+$") then
    return true
  end
  local uv = vim.uv or vim.loop
  local home = uv.os_homedir()
  if home == nil or home == "" then
    return false
  end
  if same_path(normalize(home), root) then
    return true
  end
  -- The directory a `DirChanged` names is resolved (macOS: `/var` is
  -- `/private/var`), the home directory may not be: compare real paths too.
  local real_home, real_root = uv.fs_realpath(home), uv.fs_realpath(root)
  return real_home ~= nil
    and real_root ~= nil
    and same_path(normalize(real_home), normalize(real_root))
end

---@internal
---@param root string
local function check(root)
  -- A newer directory supersedes the scan of the previous one.
  if PENDING then
    local cancel = PENDING
    PENDING = nil
    cancel()
  end
  if M.is_broad_root(root) then
    return
  end
  local scan_opts = {
    ttl_seconds = SETUP.ttl_seconds,
    max_files = SETUP.max_files or M.TRIGGER_LIMITS.max_files,
    max_depth = SETUP.max_depth or M.TRIGGER_LIMITS.max_depth,
    max_ms = SETUP.max_ms or M.TRIGGER_LIMITS.max_ms,
  }
  local cancel
  cancel = M.scan(root, scan_opts, function(scan)
    if PENDING == cancel then
      PENDING = nil
    end
    M.report_async(scan, { tools = SETUP.tools }, function(report)
      local summary = M.summary(report)
      if summary and ANNOUNCED[scan.root] ~= summary then
        ANNOUNCED[scan.root] = summary
        notify().info(summary)
      end
    end)
  end)
  PENDING = cancel
end

---Configure the optional trigger. With `auto = true` the current directory
---is scanned now and every `DirChanged` after, and one notification per root
---(again only when what is missing changes) says what is missing -- it never
---installs. Its scans are bounded (`TRIGGER_LIMITS`, or `max_files`,
---`max_depth`, `max_ms` here), the scan of a directory that is left before it
---finished is cancelled, and broad roots (`is_broad_root`: home, `/`, a drive)
---are not scanned at all. Calling `setup()` again replaces the previous
---setup; without `auto` it turns the trigger off.
---@param opts? Lib.Deps.Project.SetupOpts
---@return nil
function M.setup(opts)
  opts = opts or {}
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  if PENDING then
    local cancel = PENDING
    PENDING = nil
    cancel()
  end
  SETUP = opts
  if not opts.auto then
    return
  end
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    desc = "lib.nvim.deps.project: scan the new directory for missing parsers and tools",
    callback = function()
      check(vim.v.event.cwd or vim.fn.getcwd())
    end,
  })
  check(vim.fn.getcwd())
end

---Forget the announcements `setup({ auto = true })` made, so the next check
---of a root announces again.
---@return nil
function M.reset_announced()
  ANNOUNCED = {}
end

---@type Lib.Deps.Project
return M
