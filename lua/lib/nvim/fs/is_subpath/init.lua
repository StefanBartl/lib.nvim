---@module 'lib.nvim.fs.is_subpath'

-- `vim.fs.normalize` always returns forward-slash paths on every OS, so the
-- separator appended to `base` below must be "/" too — not the native
-- `package.config:sub(1,1)`, which would never match the normalized prefix on
-- Windows.
local norm = vim.fs.normalize
local normkey = require("lib.nvim.fs.normkey")

-- Without `opts` this stays a pure `vim.fs.normalize` string compare: no
-- syscalls, safe in a `BufReadPost`/`BufWritePost` hot path, and byte-for-byte
-- the behavior every existing caller already has. What that cannot do is see
-- past two different spellings of the same directory: `vim.fs.normalize` is a
-- string operation, so a Windows 8.3 short name (`C:/Users/STEFAN~1/...`, which
-- is what `vim.fn.tempname()` hands back) or a symlinked prefix (`/var` ->
-- `/private/var` on macOS) compares unequal against its long/real form and the
-- answer is a silent false. Callers comparing against a path from a foreign
-- source -- `tempname()`, an LSP root, a `getcwd()` inherited from another
-- process -- pass `opts` to route both sides through `lib.nvim.fs.normkey`,
-- which resolves that via `uv.fs_realpath`.
---@param path string
---@param base string
---@param opts? Lib.Fs.IsSubpathOpts # absent: normalize only. Present: canonicalize both sides via `normkey` (`realpath` defaults to true there too).
---@return boolean
return function(path, base, opts)
  if opts then
    local o = { realpath = opts.realpath ~= false }
    path, base = normkey(path, o), normkey(base, o)
  else
    path, base = norm(path), norm(base)
  end
  if path == base then
    return true
  end
  if #path <= #base then
    return false
  end
  if base:sub(-1) ~= "/" then
    base = base .. "/"
  end
  return path:sub(1, #base) == base
end
