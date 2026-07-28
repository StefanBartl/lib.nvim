---@module 'lib.nvim.docmap.tagfiles'
--- Cross-project links for `requires_external` — Doxygen's `TAGFILES`
--- equivalent. A require that resolves to nothing *in this scan* may still
--- resolve inside another project's own committed `module_map.json`, if that
--- project is one of `opts.tag_files`. Where it does, the Deps view's
--- external box stops being an inert dead end and opens that project's
--- generated page instead.
---
--- The scenario this exists for: since `docmap.cli`/the pre-commit hook
--- template made docmap trivially reusable by another plugin, a tree of
--- several small plugins all depending on `lib.nvim` and all generating
--- their own map is now the normal case, not a hypothetical one. Every one
--- of those maps drew `lib.nvim.fs`, `lib.nvim.ui.kit`, etc. as a nameless
--- grey box — this resolves it against `lib.nvim`'s own map instead.
---
--- Local paths only, deliberately: `opts.tag_files` points at another
--- checkout's `docs/map`-shaped directory, read synchronously during
--- `scan_full()`/`generate()`, the same way `opts.root` itself is read. A
--- network fetch here would turn a deterministic `--check` into one that
--- depends on network availability and timing — the same reasoning that
--- keeps `render/dot.lua` unwired to a `dot` binary.
---
--- ```lua
--- require("lib.nvim.docmap").generate({
---   ...,
---   tag_files = { ["lib.nvim"] = "/path/to/lib.nvim/docs/map" },
--- })
--- ```
---
--- Every `requires_external` module starting with `"lib.nvim"` (as a whole
--- path segment — `lib.nvim.fs`, not `lib.nvimx`) is looked up in that
--- directory's `module_map.json`; modules that don't match any prefix, or
--- don't resolve to a real node once loaded, are left exactly as before.

local M = {}

---@param root string
---@param dir string
---@return string
local function abs(root, dir)
  if dir:match("^%a:[/\\]") or dir:sub(1, 1) == "/" then
    return (dir:gsub("\\", "/"))
  end
  return root .. "/" .. dir
end

---Decode a committed `module_map.json` into just enough shape to resolve
---names against — `order` + `nodes`, not the full rehydration
---`browse.source` does, since nothing here needs `edges` or stats.
---@param path string
---@return Lib.Docmap.IR|nil
local function load_ir(path)
  local read = require("lib.nvim.fs.read")
  local content = read(path)
  if not content then
    return nil
  end
  local ok, doc = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
    return nil
  end
  local nodes, order = {}, {}
  for i, n in ipairs(doc.nodes) do
    nodes[n.id] = n
    order[i] = n.id
  end
  doc.nodes, doc.order = nodes, order
  return doc
end

---Longest matching prefix in `tag_files` for `mod`, prefix-bounded the same
---way `Lib.Docmap.LayerRule` is: `lib.nvim` matches `lib.nvim.fs` but never
---`lib.nvimx`.
---@param mod string
---@param tag_files table<string, string>
---@return string? prefix
---@return string? dir
local function match_prefix(mod, tag_files)
  local best_prefix, best_dir
  for prefix, dir in pairs(tag_files) do
    if mod == prefix or mod:sub(1, #prefix + 1) == prefix .. "." then
      if not best_prefix or #prefix > #best_prefix then
        best_prefix, best_dir = prefix, dir
      end
    end
  end
  return best_prefix, best_dir
end

---Build `ir.tag_links`: every `requires_external` module that resolves
---inside a configured tag file, mapped to a title and a link into that
---project's own generated page. Mutates `ir` in place; a no-op when
---`opts.tag_files` is unset.
---
---Reuses `command.find_node`'s resolution order (declared `@module`, raw
---node id, namespace fallback) rather than a plain `==` on `module` — a
---`requires_external` entry that names a namespace (no `init.lua`, no
---`@module` of its own) would otherwise never resolve, the same gap that
---function existed to close for `:LibMap graph`/`why`.
---@param ir Lib.Docmap.IR
---@param opts Lib.Docmap.Opts
function M.resolve(ir, opts)
  local tag_files = opts.tag_files
  ir.tag_links = {}
  if not tag_files or not next(tag_files) then
    return
  end

  local find_node = require("lib.nvim.docmap.command").find_node
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local lua_root = opts.lua_root or "lua"

  local mods = {}
  for _, id in ipairs(ir.order) do
    for _, mod in ipairs(ir.nodes[id].requires_external or {}) do
      mods[mod] = true
    end
  end

  local ir_cache = {} ---@type table<string, Lib.Docmap.IR|false>
  for mod in pairs(mods) do
    local prefix, dir = match_prefix(mod, tag_files)
    if prefix and dir then
      local resolved_dir = abs(root, dir)
      if ir_cache[resolved_dir] == nil then
        ir_cache[resolved_dir] = load_ir(resolved_dir .. "/module_map.json") or false
      end
      local ext_ir = ir_cache[resolved_dir]
      if ext_ir then
        local node_id = find_node(ext_ir, mod, lua_root)
        if node_id then
          local node = ext_ir.nodes[node_id]
          ir.tag_links[mod] = {
            title = node.module or node.name,
            -- Bare `#<id>` — the pre-existing shorthand `parseState` already
            -- treats as "select this node in the Tree tab", the same shape a
            -- hand-typed or externally shared link uses. A node id is a
            -- filesystem path and may contain characters `id=<id>&...`
            -- would need to percent-encode; the bare form has no `&`/`=` to
            -- collide with in the first place.
            html = resolved_dir .. "/index.html#" .. node_id,
          }
        end
      end
    end
  end
end

return M
