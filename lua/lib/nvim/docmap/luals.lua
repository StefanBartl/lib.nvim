---@module 'lib.nvim.docmap.luals'
--- Enriches the docmap IR with `lua-language-server --doc` output: parsed
--- `@class`/`@alias` definitions (name, description, fields) attached to the
--- node that owns the file, plus directed type-reference edges extracted from
--- field types — "this class's field points at that class." This is the data
--- the Hierarchy tab's dashed edges draw from; the header scanner alone has
--- no notion of type relationships, only filesystem/prose facts.
---
--- Deliberately a separate step from `scan()`, not folded into it: a full-tree
--- `--doc` run costs real seconds (verified: ~1.5s over a 267-entry subtree,
--- more over the whole repo), so it must stay opt-in (`opts.luals`) rather
--- than making every `:LibMap` slower. `scan_full()` in `init.lua` is what
--- wires this in when requested.
---
--- Every shape below was checked against real `--doc` output, not assumed —
--- see the file-path and class/alias-discriminator notes inline.

local M = {}

local mkdirp = require("lib.nvim.fs.mkdirp")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---True when `lua-language-server` is on PATH.
---@return boolean
function M.available()
  return vim.fn.executable("lua-language-server") == 1
end

---Run `lua-language-server --doc` over `root/source` and return its parsed
---`doc.json`.
---
---Blocking (the CLI/`:LibMap full` callers need a result before continuing),
---but built on the async `spawn_capture` + a bounded `vim.wait` rather than a
---bare `vim.system(...):wait()`, so a hung `lua-language-server` process times
---out instead of freezing the caller indefinitely.
---@param root string Absolute repository root.
---@param source string Directory to scan, relative to `root`.
---@param opts? { timeout_ms?: integer }
---@return table? doc_json Parsed `doc.json` array, or nil on failure.
---@return string? err Set when `doc_json` is nil.
function M.run(root, source, opts)
  opts = opts or {}
  if not M.available() then
    return nil, "lua-language-server not found on PATH"
  end

  local timeout_ms = opts.timeout_ms or 60000
  local scan_dir = root .. "/" .. source
  local out_dir = vim.fn.tempname()
  local ok_mk, mk_err = mkdirp(out_dir)
  if not ok_mk then
    return nil, "cannot create temp output dir: " .. tostring(mk_err)
  end

  local result
  spawn_capture(
    { "lua-language-server", "--doc=" .. scan_dir, "--doc_out_path=" .. out_dir, "--logpath=" .. out_dir .. "/log" },
    { timeout_ms = timeout_ms },
    function(res)
      result = res
    end
  )

  -- spawn_capture's own on_done is vim.schedule'd; poll past the process
  -- timeout by a margin so the scheduler tick always has a chance to land.
  local settled = vim.wait(timeout_ms + 3000, function()
    return result ~= nil
  end, 50)

  if not settled or not result then
    return nil, "lua-language-server --doc did not respond within " .. timeout_ms .. "ms"
  end
  if result.timed_out then
    return nil, "lua-language-server --doc timed out after " .. timeout_ms .. "ms"
  end
  if not result.ok then
    return nil, ("lua-language-server --doc exited %d: %s"):format(result.code, result.stderr ~= "" and result.stderr or "(no stderr)")
  end

  local doc_path = out_dir .. "/doc.json"
  local fd = io.open(doc_path, "rb")
  if not fd then
    return nil, "doc.json not found at " .. doc_path .. " after a successful exit"
  end
  local raw = fd:read("*a")
  fd:close()

  local decode_ok, data = pcall(vim.json.decode, raw)
  if not decode_ok then
    return nil, "doc.json parse failed: " .. tostring(data)
  end
  if type(data) ~= "table" then
    return nil, "doc.json did not decode to an array"
  end

  return data, nil
end

---Extract the class-shaped identifiers referenced in a raw LuaCATS type
---string (e.g. `"table<string, Lib.Docmap.Node>"` -> `{"Lib.Docmap.Node"}`),
---restricted to names actually present in `known`. A substring scan rather
---than a real type-grammar parser: good enough because class names are
---dotted and namespaced (`Lib.Docmap.Node`, not `Node`), so collisions with
---generic type syntax (`table<`, `string[]`, `fun(...)`) don't happen — none
---of those tokens are valid class names to begin with.
---@param view string?
---@param known table<string, boolean>
---@return string[]
local function referenced_classes(view, known)
  local out = {}
  if type(view) ~= "string" then
    return out
  end
  local seen = {}
  for ident in view:gmatch("[%w_]+%.[%w_%.]+") do
    if known[ident] and not seen[ident] then
      seen[ident] = true
      out[#out + 1] = ident
    end
  end
  return out
end

---Merge parsed `doc.json` into `ir`, mutating it in place: attaches
---`node.types_detail` and populates `ir.edges`.
---
---`doc.json`'s `defines[].file` is relative to the `--doc=<dir>` argument
---`run()` was given (verified: scanning `lua/lib/nvim/docmap` reports
---`"@types/init.lua"`, not a repo-relative or absolute path) — `source` is
---what turns that back into the repo-relative path `ir.nodes[*].types`
---already uses, which is how the two get matched up.
---@param ir Lib.Docmap.IR
---@param doc_json table Parsed `doc.json` array, as returned by `run()`.
---@param source string The same `source` passed to `run()`.
function M.merge(ir, doc_json, source)
  ---@type table<string, Lib.Docmap.Node>
  local by_types_file = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, tpath in ipairs(node.types or {}) do
      by_types_file[tpath] = node
    end
  end

  ---@type table<string, boolean>
  local known_classes = {}
  for _, entry in ipairs(doc_json) do
    if type(entry.name) == "string" then
      known_classes[entry.name] = true
    end
  end

  ---@type table<string, Lib.Docmap.Node>
  local class_owner = {}

  for _, entry in ipairs(doc_json) do
    local define = entry.defines and entry.defines[1]
    -- "doc.class" vs "doc.alias" is LuaLS's own discriminator (verified: an
    -- ---@alias entry's defines[1].type is literally "doc.alias"). Anything
    -- else (doc.class members that aren't top-level types, etc.) is skipped.
    if define and type(define.file) == "string" and (define.type == "doc.class" or define.type == "doc.alias") then
      local rel_file = source .. "/" .. define.file
      local node = by_types_file[rel_file]
      if node then
        local fields = {}
        for _, f in ipairs(entry.fields or {}) do
          fields[#fields + 1] = {
            name = f.name,
            view = (f.extends and f.extends.view) or "",
            desc = f.desc or "",
          }
        end

        node.types_detail = node.types_detail or {}
        table.insert(node.types_detail, {
          name = entry.name,
          kind = define.type == "doc.class" and "class" or "alias",
          desc = entry.desc or "",
          file = rel_file,
          fields = fields,
        })
        class_owner[entry.name] = node
      end
    end
  end

  -- Second pass: now that every class's owning node is known, resolve field
  -- types into edges. Two passes because a field can reference a class
  -- defined later in doc_json's array order.
  ir.edges = ir.edges or {}
  local seen_edge = {}

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, ty in ipairs(node.types_detail or {}) do
      for _, field in ipairs(ty.fields) do
        for _, ref_name in ipairs(referenced_classes(field.view, known_classes)) do
          if ref_name ~= ty.name then
            local target = class_owner[ref_name]
            if target and target.id ~= node.id then
              local key = node.id .. "|" .. target.id .. "|" .. field.name
              if not seen_edge[key] then
                seen_edge[key] = true
                ir.edges[#ir.edges + 1] = { from = node.id, to = target.id, via = field.name }
              end
            end
          end
        end
      end
    end
  end

  table.sort(ir.edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    if a.to ~= b.to then
      return a.to < b.to
    end
    return a.via < b.via
  end)
end

return M
