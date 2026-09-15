---@meta
---@module 'lib.nvim.config.repo_file.@types'

---@class Lib.Config.RepoFile.Result
---@field data table<string, any> Decoded object, filtered down to keys present in the caller's allowlist.
---@field refused string[] Keys present in the file but not in the allowlist, sorted.

---@alias Lib.Config.RepoFile.Reason
---| "empty" # No content (or only whitespace) -- not an error, nothing to report.
---| "read_failed" # Could not open/read the file.
---| "invalid_json" # Content is not valid JSON.
---| "not_object" # Valid JSON, but not a plain object (e.g. an array or a scalar).

---@class Lib.Config.RepoFile
---@field load fun(path: string, allowed: table<string, true>): Lib.Config.RepoFile.Result|nil, Lib.Config.RepoFile.Reason|nil, string|nil

return {}
