---@module 'lib.nvim.cross.fs.wslpath'
--- Convert paths between their WSL (unix) and Windows forms via the `wslpath`
--- binary that ships with every WSL distribution.
---
--- Only meaningful inside a WSL session: on any other platform `wslpath` does
--- not exist and both converters return `nil` rather than erroring, so callers
--- can attempt a conversion unconditionally and treat `nil` as "not
--- convertible here". Callers that want to skip the spawn entirely should gate
--- on `lib.nvim.cross.platform.is_wsl` first.
---
--- Upstreamed from three independent copies of the same private helper found
--- across the author's plugins (`open.nvim`'s `handlers/filemanager.lua` and
--- `handlers/default.lua`, plus `lib.nvim.cross.open_default`'s own). Uses
--- `run_argv.run_blocking_captured` (argv table, no shell) so a path
--- containing spaces or shell metacharacters needs no quoting.

local M = {}

---@internal
---Run `wslpath` with `flag` on `path` and return the trimmed output.
---Blocking by design: callers need the converted path to build the very next
---argv, and the conversion is a single sub-millisecond spawn.
---@param flag string  `-w` (unix → Windows) or `-u` (Windows → unix)
---@param path string
---@return string|nil converted  nil when wslpath is absent or fails
local function convert(flag, path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local ok, out =
    require("lib.nvim.cross.run_argv").run_blocking_captured({ "wslpath", flag, path })
  if not ok then
    return nil
  end

  out = out:gsub("[\r\n]", "")
  return (out ~= "" and out) or nil
end

---Convert a WSL/unix path to its Windows equivalent (`/mnt/c/x` → `C:\x`).
---Returns nil for a Linux-side path with no Windows-side equivalent (e.g.
---something under `/home`), which is a meaningful answer, not just an error.
---@param unix_path string
---@return string|nil win_path
function M.to_win(unix_path)
  return convert("-w", unix_path)
end

---Convert a Windows path to its WSL/unix equivalent (`C:\x` → `/mnt/c/x`).
---@param win_path string
---@return string|nil unix_path
function M.to_unix(win_path)
  return convert("-u", win_path)
end

return M
