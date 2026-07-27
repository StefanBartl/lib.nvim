---@module 'lib.nvim.docmap.browse.source'
--- Where the browser's IR comes from: the generated artifact by default, a
--- live `docmap.install()` handle on request.
---
--- Artifact-first is a measured decision, not a stylistic one. Scanning
--- lib.nvim costs ~0.65s of *blocking* editor time; decoding
--- `module_map.json` costs ~0.01s. Two thirds of a second between pressing a
--- key and seeing a window is the difference between "opens" and "hangs", so
--- the fast path is the default and the live path is opt-in.
---
--- The cost of that choice is staleness: the artifact shows the tree as of
--- the last `:LibMap`. Rather than silently showing wrong data, `M.stale()`
--- compares its mtime against the newest source file so the caller can say
--- so in the status line.

local M = {}

local uv = vim.uv or vim.loop

---Normalize a repo root the same way `docmap.registry` does, so a handle
---installed there and an artifact read here agree on the key.
---@param root string
---@return string
function M.norm_root(root)
  return (root:gsub("\\", "/"):gsub("/+$", ""))
end

---@param opts Lib.Docmap.Browse.Opts
---@return string
function M.artifact_path(opts)
  return M.norm_root(opts.root) .. "/" .. (opts.out_dir or "docs/map") .. "/module_map.json"
end

---Turn a decoded artifact into the in-memory IR shape every reader expects.
---
---The two are deliberately *not* the same document. `docmap.to_json` writes
---`nodes` as an array in walk order — that is what makes the file
---byte-deterministic, since a JSON object's key order would not be — and
---carries no `order` key, because the array *is* the order. In memory,
---`ir.nodes` is a map keyed by id and `ir.order` is the walk. Rehydrating
---here means the rest of the browser reads one shape regardless of whether
---the IR came off disk or out of a live handle.
---@param doc table Decoded artifact.
---@return Lib.Docmap.IR
function M.rehydrate(doc)
  local nodes, order = {}, {}
  for i, n in ipairs(doc.nodes or {}) do
    nodes[n.id] = n
    order[i] = n.id
  end
  doc.nodes = nodes
  doc.order = order
  doc.edges = doc.edges or {}
  return doc
end

---Read and decode `module_map.json`.
---@param opts Lib.Docmap.Browse.Opts
---@return Lib.Docmap.IR|nil ir
---@return string|nil err
function M.load_artifact(opts)
  local path = M.artifact_path(opts)
  local read = require("lib.nvim.fs.read")

  local content = read(path)
  if not content then
    return nil, ("no map at %s — run :LibMap first"):format(path)
  end

  -- `luanil` matters here, it is not a style choice: the artifact writes a
  -- literal `null` for every absent optional field (`module`, `parent`,
  -- `types_detail`, …). Without it those decode to `vim.NIL`, which is a
  -- *truthy* userdata — so `node.module or node.name` would render "userdata:
  -- 0x…" and `types_detail == nil` (the "LuaLS never ran" signal) would never
  -- be true. Dropping the keys instead restores exactly the in-memory
  -- semantics.
  local ok, doc = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok or type(doc) ~= "table" or type(doc.nodes) ~= "table" or type(doc.root) ~= "string" then
    return nil, ("map at %s is not a readable docmap artifact"):format(path)
  end

  return M.rehydrate(doc)
end

---True when the artifact is older than the newest Lua source under `source`.
---
---Walks the source tree and stats each file rather than trusting a directory
---mtime: on every platform this repo runs on, a directory's mtime does not
---move when a file *inside* it is edited in place, so a directory-only check
---would report "fresh" for exactly the edit-then-browse case this exists to
---catch.
---@param opts Lib.Docmap.Browse.Opts
---@return boolean stale
function M.stale(opts)
  local st = uv.fs_stat(M.artifact_path(opts))
  if not st then
    return true
  end
  local map_mtime = st.mtime.sec

  local source_dir = M.norm_root(opts.root) .. "/" .. (opts.source or "lua")
  local ok, files = pcall(function()
    return require("lib.nvim.fs.collect_recursive").files(source_dir)
  end)
  if not ok then
    return false
  end

  for _, p in ipairs(files) do
    if p:sub(-4) == ".lua" then
      local fs = uv.fs_stat(p)
      if fs and fs.mtime.sec > map_mtime then
        return true
      end
    end
  end
  return false
end

---Acquire an IR for the browser.
---
---`opts.live` installs (or reuses) a watching `docmap.install()` handle and
---returns its IR; everything else reads the artifact. The handle is returned
---alongside so the caller can subscribe to `on_change` — the whole point of
---the live mode.
---@param opts Lib.Docmap.Browse.Opts
---@return Lib.Docmap.IR|nil ir
---@return Lib.Docmap.Handle|nil handle
---@return string|nil err_or_hint
function M.acquire(opts)
  if opts.live then
    local docmap = require("lib.nvim.docmap")
    local registry = require("lib.nvim.docmap.registry")
    local root = M.norm_root(opts.root)

    -- Reuse an already-installed handle rather than installing a second one:
    -- `install()` replaces on collision, which would tear down a watch some
    -- other caller (a plugin's own setup) is still relying on.
    local handle = registry.get(root)
    if not handle then
      handle = docmap.install(vim.tbl_extend("force", opts, { root = root, watch = true }))
    end
    return handle.ir(), handle, nil
  end

  local ir, err = M.load_artifact(opts)
  if not ir then
    return nil, nil, err
  end
  return ir, nil, M.stale(opts) and "map is stale — run :LibMap" or nil
end

return M
