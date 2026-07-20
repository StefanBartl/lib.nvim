---@module 'lib.nvim.docmap.config'
--- lib.nvim's own docmap configuration, plus the repo-specific drift checks
--- that would not make sense for another plugin.
---
--- This file is the *only* place in `docmap` that knows anything about
--- lib.nvim's layout. Everything else takes it as options, which is what lets
--- another plugin reuse the generator: it writes its own equivalent of this
--- file and passes the result to `docmap.generate`.

local M = {}

---The aggregate `Lib` class declares one `---@field` per exported key. Each of
---those must actually be wired into the export strategies, or the published
---type is a lie — which is exactly what happened to `find_root`: declared on
---the class, present in none of `MODULE_MAP`/eager/lazy, so `lib.find_root`
---evaluated to `nil` while LSP happily completed it.
---
---Resolution is checked against the **loaded library**, not against the
---strategy source. An early regex version of this check reported
---`json_decode_to_string_array` as missing because it is wired through
---`SPECIAL_HANDLERS` in a `{ mod = …, key = … }` shape the pattern did not
---match — a false positive that a source-scanning check will keep producing
---as the strategies grow shapes. Indexing the real table is ground truth: it
---is exactly what a consumer observes, and it costs nothing here because the
---repo is already on the runtimepath.
---@param root string
---@return Lib.Docmap.Check
local function aggregator_check(root)
  ---@param _ir Lib.Docmap.IR
  ---@return Lib.Docmap.Finding[]
  return function(_ir)
    local findings = {}

    local fd = io.open(root .. "/lua/lib/@types/all_functions.lua", "r")
    if not fd then
      return findings
    end
    local types_src = fd:read("*a")
    fd:close()

    local ok, lib = pcall(require, "lib")
    if not ok or type(lib) ~= "table" then
      return findings
    end

    for name in types_src:gmatch("%-%-%-@field%s+([%w_]+)") do
      -- Indexing rather than rawget on purpose: the lazy and metatable
      -- strategies resolve through __index, and __index is what users hit.
      local got_ok, value = pcall(function()
        return lib[name]
      end)
      if not got_ok or value == nil then
        findings[#findings + 1] = {
          severity = "error",
          check = "type-not-exported",
          node = "lua/lib/@types",
          message = ("Lib class declares '%s' but require('lib').%s is nil"):format(name, name),
        }
      end
    end

    table.sort(findings, function(a, b)
      return a.message < b.message
    end)
    return findings
  end
end

---Build lib.nvim's docmap options.
---@param root string Absolute repository root
---@return Lib.Docmap.Opts
function M.build(root)
  root = root:gsub("\\", "/"):gsub("/+$", "")
  return {
    root = root,
    source = "lua/lib",
    lua_root = "lua",
    title = "lib.nvim",
    types_dir = "@types",
    out_dir = "docs/map",
    repo_url = "https://github.com/StefanBartl/lib.nvim",
    branch = "main",
    extra_checks = { aggregator_check(root) },
  }
end

return setmetatable(M, {
  __call = function(_, root)
    return M.build(root)
  end,
})
