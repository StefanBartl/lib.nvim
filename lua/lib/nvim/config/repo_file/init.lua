---@module 'lib.nvim.config.repo_file'
--- Read a repository-local JSON config file and split its keys into
--- `allowed` (the repository's own business, e.g. `servers`/`formatter`)
--- and everything else -- the shape `documentation.nvim`'s `.docmap.json`
--- loader and `lsp.nvim`'s `.nvim-lsp.json` loader each built independently
--- before this module existed, one allowlist + one warning apart.
---
--- This module only does the mechanical part: read, decode, split. It does
--- not find the file (that varies -- an upward walk from cwd, a fixed
--- `<root>/.foo.json`, a caller-resolved project root) and it does not
--- format a warning (the exact wording -- one combined message vs. two
--- separate "wrong owner" / "not an option at all" categories -- is a
--- decision each consumer already made for its own users). A caller wraps
--- this with its own path resolution and its own notify calls.

require("lib.nvim.config.repo_file.@types")

local read = require("lib.nvim.fs.read")

local M = {}

---Read `path` as a JSON object and split its keys into `allowed` vs.
---everything else. Never throws.
---
---A `null` value in the file is dropped rather than kept as a sentinel --
---in a config file, JSON `null` reads as "no opinion, leave the default",
---not as an explicit data value. That is `vim.json.decode`'s own `luanil`
---option, deliberately *not* `lib.nvim.json.decode`'s `lib.lua.null`
---sentinel: the sentinel is the right default for *data* a plugin goes on
---to re-encode or display, which a discarded config option never is.
---@param path string absolute path to an existing file
---@param allowed table<string, true>
---@return Lib.Config.RepoFile.Result|nil result
---@return Lib.Config.RepoFile.Reason|nil reason
---@return string|nil detail only set for "read_failed"/"invalid_json"
function M.load(path, allowed)
  local content, read_err = read(path)
  if not content then
    return nil, "read_failed", read_err
  end

  if content:match("^%s*$") then
    -- An empty file is a plausible placeholder ("I will fill this in
    -- later"), not a mistake -- nothing for a caller to warn about.
    return nil, "empty", nil
  end

  local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok then
    return nil, "invalid_json", tostring(decoded)
  end
  if type(decoded) ~= "table" or vim.islist(decoded) then
    return nil, "not_object", nil
  end

  ---@type table<string, any>
  local data = {}
  ---@type string[]
  local refused = {}
  for key, value in pairs(decoded) do
    if allowed[key] then
      data[key] = value
    else
      refused[#refused + 1] = tostring(key)
    end
  end
  table.sort(refused)

  return { data = data, refused = refused }, nil, nil
end

---@type Lib.Config.RepoFile
return M
