---@module 'lib.nvim.docmap.scan'
--- Filesystem walk + leading-comment-block parser producing the docmap IR.
---
--- Deliberately does **not** parse Lua. It reads only each file's leading
--- comment block — everything before the first non-comment line — which is
--- reliable because the `---@module` convention is uniform, and which costs
--- ~200 lines instead of a Lua front end. Anything needing real name
--- resolution (classes, fields, signatures) is left to `docmap.luals`, which
--- delegates to `lua-language-server --doc`.
---
--- The walk is generic: nothing here knows about `lib.nvim` specifically, so
--- another plugin can point it at its own tree via `opts.root`/`opts.source`.

local M = {}

local uv = vim.uv or vim.loop

---Normalize to forward slashes; every path in the IR is stored this way so
---the artifact is byte-identical regardless of which OS generated it.
---@param p string
---@return string
local function slash(p)
  return (p:gsub("\\", "/"))
end

---Strip a trailing separator.
---@param p string
---@return string
local function chomp(p)
  return (p:gsub("/+$", ""))
end

---@param path string
---@return boolean
local function is_dir(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

---@param path string
---@return boolean
local function is_file(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "file"
end

---Read a file's first `limit` lines without slurping the whole thing.
---@param path string
---@param limit integer
---@return string[]
local function head_lines(path, limit)
  local out = {}
  local fd = io.open(path, "r")
  if not fd then
    return out
  end
  for line in fd:lines() do
    out[#out + 1] = line
    if #out >= limit then
      break
    end
  end
  fd:close()
  return out
end

---Split a prose blob into a one-sentence summary and the remaining body.
---
---The summary is what lands in tree rows and generated tables, so it is
---capped: a "sentence" that runs past `max` characters is almost always a
---module that never wrote a real summary line, and truncating it produces a
---better table than letting one row swallow the layout.
---
---Exported (not local) so `docmap.functions` can apply the same summary-line
---logic to a function's doc-comment prose instead of duplicating it.
---@param prose string
---@return string summary
---@return string body
function M.split_summary(prose)
  if prose == "" then
    return "", ""
  end

  -- First blank-line-delimited paragraph is the summary candidate.
  local first_para, rest = prose:match("^(.-)\n%s*\n(.*)$")
  if not first_para then
    first_para, rest = prose, ""
  end

  local flat = first_para:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  -- Prefer a real sentence boundary: ". " not preceded by a single capital
  -- (crude initials guard) and not inside `code`.
  local sentence = flat:match("^(.-[%.!?])%s")
  local summary = sentence or flat

  local max = 160
  if #summary > max then
    summary = summary:sub(1, max - 1):gsub("%s+%S*$", "") .. "…"
  end

  local body = rest
  if sentence and #sentence < #flat then
    body = flat:sub(#sentence + 1):gsub("^%s+", "") .. (rest ~= "" and ("\n\n" .. rest) or "")
  end

  return summary, (body:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Parse the leading comment block of a Lua file.
---@param path string
---@return { module: string?, summary: string, body: string, tags: table<string, string> }
function M.parse_header(path)
  local lines = head_lines(path, 200)

  local module_path, meta
  local prose = {}
  local tags = {}
  local seen_module = false

  for _, line in ipairs(lines) do
    -- Stop at the first line that is not a comment and not blank: the header
    -- block is over and everything past it is code.
    if not line:match("^%s*%-%-") and line:match("%S") then
      break
    end

    local mod = line:match("^%-%-%-@module%s+['\"]([^'\"]+)['\"]")
    if mod then
      module_path = mod
      seen_module = true
    elseif line:match("^%-%-%-@meta") then
      meta = true
    else
      -- A tagged annotation ends the prose block for our purposes; we only
      -- want the free text that documents the module itself.
      local tag, value = line:match("^%-%-%-@(%a+)%s*(.*)$")
      if tag then
        if value ~= "" and tags[tag] == nil then
          tags[tag] = value
        end
      else
        local text = line:match("^%s*%-%-%-?%s?(.*)$")
        if text and seen_module then
          prose[#prose + 1] = text
        end
      end
    end
  end

  -- `@brief`/`@description` exist in a handful of files as a competing
  -- convention; treat them as prose so those modules are not blank on the map.
  local blob = table.concat(prose, "\n")
  if blob:match("^%s*$") then
    blob = tags.brief or tags.description or ""
  end

  local summary, body = M.split_summary(blob)
  return { module = module_path, summary = summary, body = body, tags = tags, meta = meta }
end

---Classify a module's export shape from its tail.
---@param path string
---@return "function"|"table"|"other"|"none"
local function export_shape(path)
  local fd = io.open(path, "r")
  if not fd then
    return "none"
  end
  local last
  for line in fd:lines() do
    if line:match("^return%s") or line:match("^return$") then
      last = line
    end
  end
  fd:close()

  if not last then
    return "none"
  end
  if last:match("^return%s+function") then
    return "function"
  end
  if last:match("^return%s*{") then
    return "table"
  end
  if last:match("^return%s+%u?%w*%s*$") then
    return "table"
  end
  return "other"
end

---List entries of `dir`, sorted, so generated output is deterministic.
---@param dir string
---@return { name: string, type: string }[]
local function entries(dir)
  local out = {}
  local iter = vim.fs.dir(dir)
  if not iter then
    return out
  end
  for name, type_ in iter do
    out[#out + 1] = { name = name, type = type_ }
  end
  table.sort(out, function(a, b)
    if (a.type == "directory") ~= (b.type == "directory") then
      return a.type == "directory"
    end
    return a.name < b.name
  end)
  return out
end

---Cheap line count for a file the walk does not otherwise read — currently
---only `@types/` members, which carry no functions and so never go through
---`docmap.functions` (which counts its own lines from the source it already
---has in memory).
---@param path string
---@return integer
local function count_lines(path)
  local n = 0
  local fd = io.open(path, "r")
  if not fd then
    return 0
  end
  for _ in fd:lines() do
    n = n + 1
  end
  fd:close()
  return n
end

---An empty tally, so every node starts from the same shape and the
---aggregation below can add without presence checks.
---@return Lib.Docmap.Stats
local function zero_stats()
  return {
    modules = 0,
    namespaces = 0,
    files_lua = 0,
    files_md = 0,
    files_other = 0,
    lines = 0,
    functions = 0,
    symbols = 0,
    types = 0,
  }
end

---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.IR
function M.scan(opts)
  local root = chomp(slash(opts.root))
  local source = chomp(slash(opts.source or "lua"))
  local abs_source = root .. "/" .. source
  local types_dir = opts.types_dir or "@types"

  assert(is_dir(abs_source), "docmap: source directory not found: " .. abs_source)

  local index = {} ---@type table<string, Lib.Docmap.Node>
  local order = {} ---@type string[]
  local counts = { module = 0, namespace = 0, file = 0 }

  ---Build one node from a directory.
  ---@param abs string
  ---@param rel string Path relative to `root`
  ---@param parent_id string?
  ---@param depth integer
  ---@return string id
  local function walk_dir(abs, rel, parent_id, depth)
    local id = rel
    local name = rel:match("([^/]+)$") or opts.title or rel

    local init = abs .. "/init.lua"
    local has_init = is_file(init)
    local header = has_init and M.parse_header(init) or nil

    -- `@types/` is an attribute of its module, not a node of its own: a
    -- module's types belong to it, and promoting them to siblings doubles the
    -- tree for no navigational gain.
    local type_files = {}
    local abs_types = abs .. "/" .. types_dir
    if is_dir(abs_types) then
      for _, e in ipairs(entries(abs_types)) do
        if e.type == "file" and e.name:match("%.lua$") then
          type_files[#type_files + 1] = rel .. "/" .. types_dir .. "/" .. e.name
        end
      end
    end

    local readme = is_file(abs .. "/README.md") and (rel .. "/README.md") or nil

    local kind = has_init and "module" or "namespace"
    counts[kind] = counts[kind] + 1

    local fns, calls, requires, syms, loc = {}, {}, {}, {}, 0
    if has_init then
      fns, calls, requires, syms, loc = require("lib.nvim.docmap.functions").scan_file(init)
    end

    -- Own tally for this directory: what sits directly in it, plus its
    -- `@types/` members, which are files of this module rather than nodes of
    -- their own and would otherwise be counted nowhere.
    local own = zero_stats()
    own[kind == "module" and "modules" or "namespaces"] = 1
    own.functions = #fns
    own.symbols = #syms
    if has_init then
      own.files_lua = 1
      own.lines = loc
    end
    for _, t in ipairs(type_files) do
      own.files_lua = own.files_lua + 1
      own.lines = own.lines + count_lines(root .. "/" .. t)
    end

    -- Listed once and reused by both the tally and the child walk below: an
    -- earlier version called `entries(abs)` twice per directory, which is a
    -- second full directory read for every one of ~150 directories.
    local dir_entries = entries(abs)
    for _, e in ipairs(dir_entries) do
      if e.type ~= "directory" and not e.name:match("%.lua$") then
        if e.name:lower():match("%.md$") then
          own.files_md = own.files_md + 1
        else
          own.files_other = own.files_other + 1
        end
      end
    end

    ---@type Lib.Docmap.Node
    local node = {
      id = id,
      kind = kind,
      name = name,
      path = rel,
      source = has_init and (rel .. "/init.lua") or nil,
      module = header and header.module or nil,
      summary = header and header.summary or "",
      body = header and header.body or "",
      readme = readme,
      types = type_files,
      export = has_init and export_shape(init) or nil,
      parent = parent_id,
      depth = depth,
      children = {},
      functions = fns,
      symbols = syms,
      stats = own,
      requires = {},
      required_by = {},
      requires_external = {},
      requires_raw = requires,
      calls_raw = calls,
    }

    index[id] = node
    order[#order + 1] = id

    for _, e in ipairs(dir_entries) do
      local child_abs = abs .. "/" .. e.name
      local child_rel = rel .. "/" .. e.name

      if e.type == "directory" then
        if e.name ~= types_dir then
          node.children[#node.children + 1] = walk_dir(child_abs, child_rel, id, depth + 1)
        end
      elseif e.name:match("%.lua$") and e.name ~= "init.lua" then
        -- Helper files are real, documented units and stay visible as leaves
        -- rather than being folded into the parent's detail pane.
        local h = M.parse_header(child_abs)
        counts.file = counts.file + 1
        local leaf_fns, leaf_calls, leaf_requires, leaf_syms, leaf_loc =
          require("lib.nvim.docmap.functions").scan_file(child_abs)
        local leaf_stats = zero_stats()
        leaf_stats.files_lua = 1
        leaf_stats.lines = leaf_loc
        leaf_stats.functions = #leaf_fns
        leaf_stats.symbols = #leaf_syms
        ---@type Lib.Docmap.Node
        local leaf = {
          id = child_rel,
          kind = "file",
          name = e.name,
          path = child_rel,
          source = child_rel,
          module = h.module,
          summary = h.summary,
          body = h.body,
          readme = nil,
          types = {},
          export = export_shape(child_abs),
          parent = id,
          depth = depth + 1,
          children = {},
          functions = leaf_fns,
          symbols = leaf_syms,
          stats = leaf_stats,
          requires = {},
          required_by = {},
          requires_external = {},
          requires_raw = leaf_requires,
          calls_raw = leaf_calls,
        }
        index[child_rel] = leaf
        order[#order + 1] = child_rel
        node.children[#node.children + 1] = child_rel
      end
    end

    return id
  end

  local root_id = walk_dir(abs_source, source, nil, 0)
  index[root_id].name = opts.title or index[root_id].name

  ---@type Lib.Docmap.IR
  local ir = {
    meta = {
      title = opts.title or source,
      source = source,
      types_dir = types_dir,
      repo_url = opts.repo_url,
      branch = opts.branch or "main",
      schema = 2,
      counts = counts,
    },
    root = root_id,
    order = order,
    nodes = index,
    edges = {},
  }

  -- Both graph stages run here rather than in `scan_full`, unlike the LuaLS
  -- merge: they need no external tool, they cost only in-memory resolution
  -- over data the walk already collected, and running them here means every
  -- caller of `scan()` — checks, renderers, a live handle — sees the same
  -- fully-formed IR instead of some seeing a half-built one. Order matters:
  -- call resolution reads the require aliases `deps` indexes.
  require("lib.nvim.docmap.deps").build(ir)
  require("lib.nvim.docmap.calls").build(ir, opts)

  -- Roll the per-directory tallies up the tree. Reverse `order` is a valid
  -- post-order here because `walk_dir` appends a node before descending into
  -- it, so every child sits after its parent — walking backwards means a node
  -- is only ever added to its parent once its own subtree is complete.
  for i = #order, 1, -1 do
    local node = index[order[i]]
    local parent = node.parent and index[node.parent]
    if parent then
      for key, value in pairs(node.stats) do
        parent.stats[key] = parent.stats[key] + value
      end
    end
  end

  return ir
end

return M
