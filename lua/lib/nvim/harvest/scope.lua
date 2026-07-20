---@module 'lib.nvim.harvest.scope'
--- Resolve a "where should I look?" descriptor into a flat list of
--- `Lib.Harvest.Source` records (lines + provenance).
---
--- This is the step every "collect X from somewhere, then show/export it"
--- feature reimplements: markdown.nvim alone had two near-identical copies
--- (`commands/links.lua`'s `collect()` for `%`/`cwd`/`<file>`, and
--- `commands/markdown_links.lua`'s `scan()` for a directory tree). Both
--- hardcoded their own file filter, their own ignore handling, and their own
--- "read the file, remember which file it was" bookkeeping. Callers here get
--- that once and stay free to do whatever they want with the lines.
---
--- Deliberately does *no* extraction: what counts as an interesting hit is
--- domain logic and stays with the caller.
---
---```lua
--- local scope = require("lib.nvim.harvest.scope")
--- local srcs = scope.resolve("buffer")
--- local srcs = scope.resolve("cwd", { match = "%.md$" })
--- local srcs = scope.resolve("path", { path = "~/notes", recursive = true })
--- local srcs = scope.resolve("range", { line1 = 10, line2 = 20 })
---```

require("lib.nvim.harvest.@types")

local M = {}

local uv = vim.uv or vim.loop

local DEFAULT_MAX_FILES = 2000
local DEFAULT_MAX_FILESIZE = 1024 * 1024 -- 1 MiB

--- Default prune predicate: lib.nvim's shared basename ignore list, so a
--- harvest over a repo skips `.git`, `node_modules`, … the same way every
--- other lib.nvim-based tool does.
---@return fun(abs: string, is_dir: boolean): boolean
local function default_ignore()
  local ok, list = pcall(require, "lib.nvim.fs.ignore.list")
  local names = (ok and type(list.basenames) == "table") and list.basenames or {}
  local set = {}
  for _, n in ipairs(names) do
    set[n] = true
  end
  return function(abs, _is_dir)
    return set[vim.fn.fnamemodify(abs, ":t")] == true
  end
end

--- Read a file into a Source, or nil when it is unreadable, too large, or
--- looks binary. Binary detection is a NUL-byte probe of the first chunk:
--- cheap, and enough to keep a stray `.png` out of a text harvest.
---@param path string
---@param max_filesize integer
---@return Lib.Harvest.Source|nil
local function read_source(path, max_filesize)
  local st = uv.fs_stat(path)
  if not st or st.type ~= "file" then
    return nil
  end
  if st.size > max_filesize then
    return nil
  end

  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local data = uv.fs_read(fd, st.size, 0)
  uv.fs_close(fd)
  if not data then
    return nil
  end
  if data:find("\0", 1, true) then
    return nil -- binary
  end

  local lines = vim.split(data:gsub("\r\n", "\n"), "\n", { plain = true })
  -- A trailing newline yields a final empty element; drop it so line numbers
  -- stay honest and callers don't scan a phantom line.
  if lines[#lines] == "" then
    lines[#lines] = nil
  end

  return { file = vim.fs.normalize(path), lines = lines, first = 1 }
end

---@param bufnr integer
---@return Lib.Harvest.Source|nil
local function buffer_source(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return {
    file = name ~= "" and vim.fs.normalize(name) or nil,
    bufnr = bufnr,
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
    first = 1,
  }
end

--- Collect readable text files under `root`.
---@param root string
---@param opts Lib.Harvest.ScopeOpts
---@return Lib.Harvest.Source[]
local function dir_sources(root, opts)
  local collect_recursive = require("lib.nvim.fs.collect_recursive")
  local ignore = opts.ignore or default_ignore()
  local max_files = opts.max_files or DEFAULT_MAX_FILES
  local max_filesize = opts.max_filesize or DEFAULT_MAX_FILESIZE

  local paths
  if opts.recursive == false then
    -- Shallow: one scandir pass, no descent.
    paths = {}
    local handle = uv.fs_scandir(root)
    if handle then
      while true do
        local name, kind = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        local abs = root .. "/" .. name
        if kind ~= "directory" and not ignore(abs, false) then
          paths[#paths + 1] = abs
        end
      end
    end
  else
    paths = collect_recursive.files(root, { ignore = ignore })
  end

  table.sort(paths)

  local out = {}
  for _, p in ipairs(paths) do
    if #out >= max_files then
      break
    end
    if not opts.match or vim.fn.fnamemodify(p, ":t"):match(opts.match) then
      local src = read_source(p, max_filesize)
      if src then
        out[#out + 1] = src
      end
    end
  end
  return out
end

--- Resolve `kind` into sources.
---@param kind Lib.Harvest.ScopeKind|string|nil
---@param opts Lib.Harvest.ScopeOpts|nil
---@return Lib.Harvest.Source[] sources, string|nil err
function M.resolve(kind, opts)
  opts = opts or {}
  kind = kind or "buffer"

  if kind == "buffer" or kind == "%" then
    local src = buffer_source(opts.bufnr or vim.api.nvim_get_current_buf())
    -- Spelled out rather than `src and nil or "..."`: that idiom cannot yield
    -- nil, since `and nil` collapses to nil and `or` then always takes the
    -- right-hand branch — so every successful resolve would report an error.
    if not src then
      return {}, "invalid buffer"
    end
    return { src }, nil
  end

  if kind == "range" then
    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return {}, "invalid buffer"
    end
    local total = vim.api.nvim_buf_line_count(bufnr)
    local l1 = math.max(1, opts.line1 or 1)
    local l2 = math.min(total, opts.line2 or total)
    if l2 < l1 then
      return {}, "empty range"
    end
    local name = vim.api.nvim_buf_get_name(bufnr)
    return { {
      file = name ~= "" and vim.fs.normalize(name) or nil,
      bufnr = bufnr,
      lines = vim.api.nvim_buf_get_lines(bufnr, l1 - 1, l2, false),
      -- `first` is what lets a caller report real buffer line numbers for a
      -- partial scan; without it every hit in a range would report as if the
      -- selection started at line 1.
      first = l1,
    } }, nil
  end

  if kind == "buffers" then
    local out = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
        local src = buffer_source(b)
        if src then
          out[#out + 1] = src
        end
      end
    end
    return out, nil
  end

  if kind == "cwd" then
    local root = vim.fs.normalize(vim.fn.getcwd())
    return dir_sources(root, vim.tbl_extend("keep", opts, { recursive = true })), nil
  end

  if kind == "path" then
    local raw = opts.path
    if not raw or raw == "" then
      return {}, "path scope needs a path"
    end
    local p = vim.fs.normalize(vim.fn.expand(raw))
    local st = uv.fs_stat(p)
    if not st then
      return {}, ("no such file or directory: %s"):format(raw)
    end
    if st.type == "directory" then
      return dir_sources(p, opts), nil
    end
    local src = read_source(p, opts.max_filesize or DEFAULT_MAX_FILESIZE)
    if not src then
      return {}, ("not a readable text file: %s"):format(raw)
    end
    return { src }, nil
  end

  return {}, ("unknown scope '%s'"):format(tostring(kind))
end

--- Convenience: treat a free-form token the way a user command would.
--- `""`/`"%"` → buffer, `"cwd"`/`"buffers"` → themselves, anything else → a path.
---@param token string|nil
---@param opts Lib.Harvest.ScopeOpts|nil
---@return Lib.Harvest.Source[] sources, string|nil err
function M.resolve_token(token, opts)
  opts = opts or {}
  if not token or token == "" or token == "%" then
    return M.resolve("buffer", opts)
  end
  if token == "cwd" or token == "buffers" or token == "buffer" or token == "range" then
    return M.resolve(token, opts)
  end
  return M.resolve("path", vim.tbl_extend("force", opts, { path = token }))
end

return M
