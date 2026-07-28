---@module 'lib.nvim.docmap.coverage'
--- Auto-derived test coverage — R2 of the docmap roadmap. `@test` already
--- exists as a manual tag (see `docs/ANNOTATIONS.md`), and has exactly zero
--- real hits in this tree: a doc-comment tag that duplicates what the actual
--- test file already says is a second source of truth, and second sources
--- of truth drift. This measures instead of asking anyone to remember.
---
--- Same technique `calls.lua`'s `identifier_counts` uses for "used as a
--- value" — count how often a function's bare name is mentioned in a file —
--- pointed at the test tree instead of the source tree. Coarse in the same
--- direction on purpose: `M.read` and an unrelated local `read` both count,
--- so a function can show `tested = true` on a name collision it did not
--- earn. That errs toward "tested", which is the safe direction for a signal
--- that only ever adds a badge and never fails `--check` — the same
--- reasoning `dead-function` and `undocumented-param` already follow.
---
--- What this cannot see: a function exercised only *indirectly* (called by
--- another function that a spec does name) never lights up. That is a real
--- blind spot, not a bug — the same one `calls.lua` has for dynamic
--- dispatch — so `tested = false` means "not found by name in a spec file",
--- not "definitely untested". Silence, not a red badge, is how the renderer
--- treats it.

local M = {}

local IDENT_QUERY = vim.treesitter.query.parse("lua", "(identifier) @id")

---Every identifier mentioned in `src`, by name — `calls.identifier_counts`
---duplicated rather than reused across a require, since `calls.lua` frames
---it as "used as a value" over the *source* tree and this reads over the
---*test* tree; two different questions sharing one small query.
---@param src string
---@return table<string, boolean>
local function mentioned_names(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "lua")
  if not ok then
    return {}
  end
  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or not trees or not trees[1] then
    return {}
  end
  local root = trees[1]:root()

  local names = {}
  for id, node in IDENT_QUERY:iter_captures(root, src) do
    if IDENT_QUERY.captures[id] == "id" then
      names[vim.treesitter.get_node_text(node, src)] = true
    end
  end
  return names
end

---Last dot/colon-separated segment: `M.scan_full` / `M:put` -> `scan_full`
---/ `put`. What a spec file actually writes when it calls a function whose
---owning table is a local import, not the file's own `M`.
---@param name string
---@return string
local function bare(name)
  return name:match("([%w_]+)$") or name
end

---Every `.lua` file under `dir`, recursively — `lib.nvim.fs.collect_recursive`
---already exists for exactly this and is already a dependency of
---`browse/source.lua`'s staleness check.
---@param dir string
---@return string[]
local function lua_files(dir)
  local ok, files = pcall(function()
    return require("lib.nvim.fs.collect_recursive").files(dir)
  end)
  if not ok then
    return {}
  end
  local out = {}
  for _, p in ipairs(files) do
    if p:sub(-4) == ".lua" then
      out[#out + 1] = p
    end
  end
  return out
end

---Mark every function in `ir` with `fn.tested`: its bare name is mentioned
---somewhere under `opts.tests_dir`. Mutates `ir` in place; a no-op (every
---function left `tested = false`) when the directory does not exist —
---another plugin reusing docmap may keep its tests elsewhere, or not have
---this default layout, and that is not an error.
---@param ir Lib.Docmap.IR
---@param opts Lib.Docmap.Opts
function M.resolve(ir, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local tests_dir = root .. "/" .. (opts.tests_dir or "docs/TESTS")

  local mentioned = {}
  for _, path in ipairs(lua_files(tests_dir)) do
    local fd = io.open(path, "rb")
    if fd then
      local src = fd:read("*a")
      fd:close()
      for name in pairs(mentioned_names(src)) do
        mentioned[name] = true
      end
    end
  end

  for _, id in ipairs(ir.order) do
    for _, fn in ipairs(ir.nodes[id].functions) do
      fn.tested = mentioned[bare(fn.name)] or false
    end
  end
end

---Aggregate `tested` over the whole IR — the single number the future
---Analysis tab's coverage panel would show, and useful on its own from the
---CLI without any UI: `#tested / #total`.
---@param ir Lib.Docmap.IR
---@return integer tested
---@return integer total
function M.summary(ir)
  local tested, total = 0, 0
  for _, id in ipairs(ir.order) do
    for _, fn in ipairs(ir.nodes[id].functions) do
      total = total + 1
      if fn.tested then
        tested = tested + 1
      end
    end
  end
  return tested, total
end

return M
