---@module 'lib.nvim.fs.stdpath_config_root'
--- "Is this directory inside the Neovim config directory, and if so, what is
--- the root to hand an LSP?" -- the one question two root resolvers were each
--- answering with the same two lines, and getting wrong the same way.
---
--- The wrong answer came from comparing two spellings of one directory.
--- `vim.fn.stdpath("config")` is whatever Neovim was pointed at -- typically
--- `~/.config/nvim`, which on the very common dotfiles setup is a *symlink*
--- into a dotfiles repo. The directory on the other side of the comparison
--- comes from a buffer name, and Unix Neovim canonicalizes a path on the way
--- into a buffer name, so it reads `~/dotfiles/nvim/...`. Those two strings
--- have no common prefix, `is_subpath` answers a silent false, and the
--- documented rule "the config directory is a root of its own" never fires:
--- the caller falls through to its VCS search and roots the server at the
--- whole dotfiles repo.
---
--- ## Why the realpath happens here, once, and not at the call site
---
--- `lib.nvim.fs.is_subpath` takes an `opts` argument that routes both sides
--- through `lib.nvim.fs.normkey` (`uv.fs_realpath`) and would close the gap in
--- one character. It is deliberately not used here. `opts` resolves *both*
--- sides on *every* call, and a root resolver runs per buffer, for every file
--- in every project -- paying two syscalls each time, on paths that may sit on
--- a network share, to re-derive an answer that cannot change.
---
--- `stdpath("config")` is fixed for the session. So its canonical spelling is
--- resolved once and kept, and the comparison itself stays the pure string
--- compare it has always been. The cache is keyed on the raw value rather than
--- held unconditionally: a test that stubs `vim.fn.stdpath` -- which is the
--- only way to test any of this -- then gets a fresh resolution instead of a
--- stale one, with no cache-invalidation call to forget.
---
--- Both known spellings are tried, and that covers both platforms without
--- resolving `dir`: Unix hands the caller the canonical spelling (it
--- canonicalizes buffer names), Windows hands it the literal one (measured: it
--- does not). A `dir` in some third spelling -- behind a symlink of its own --
--- still misses, and still costs nothing.
---
--- ## Which spelling is returned
---
--- The canonical one, when it is the canonical one that matched. Returning the
--- raw `~/.config/nvim` against a buffer at `~/dotfiles/nvim/...` would hand
--- the server a root that is not a prefix of the file it is being asked about,
--- which is worse than the miss it replaces: measured against
--- `lua-language-server`, it indexes the tree through the symlink and answers
--- `textDocument/definition` with the *other* spelling of the file, so jumping
--- to a definition opens a second buffer on a file that is already open. With
--- the canonical spelling returned, one spelling is used throughout.
---
--- A plain match still returns the raw value byte for byte, so nothing that
--- resolved correctly before resolves differently now.
---
---@see lib.nvim.fs.polymorphic_rootresolver
---@see lib.nvim.fs.is_subpath

local is_subpath = require("lib.nvim.fs.is_subpath")
local normkey = require("lib.nvim.fs.normkey")

---@type string|nil # the raw `stdpath("config")` the two below were derived from
local cached_raw
---@type string|nil # `cached_raw` under `vim.fs.normalize`
local cached_norm
---@type string|nil # `cached_raw` under `normkey` (symlinks resolved)
local cached_real

--- The config directory in both spellings, resolving at most once per value.
---@return string raw # exactly what `stdpath("config")` returned
---@return string norm # `raw` normalized
---@return string real # `raw` canonicalized
local function spellings()
  local raw = vim.fn.stdpath("config") --[[@as string]]
  if raw ~= cached_raw then
    cached_raw = raw
    cached_norm = vim.fs.normalize(raw)
    cached_real = normkey(raw)
  end
  return cached_raw, cached_norm, cached_real
end

--- The Neovim config directory, if `dir` lies inside it.
---
--- @param dir string|nil directory to test; anything else answers nil
--- @return string|nil root the config directory, in a spelling that is a
---   prefix of `dir`; nil when `dir` is not inside it
return function(dir)
  if type(dir) ~= "string" or dir == "" then
    return nil
  end

  local raw, norm, real = spellings()

  -- An empty `stdpath("config")` cannot be answered for. Without this guard
  -- `is_subpath` appends a separator to the empty base and every absolute
  -- POSIX path comes back true -- every file on the machine reported as part
  -- of the Neovim config.
  if raw == "" then
    return nil
  end

  if is_subpath(dir, norm) then
    return raw
  end

  -- Only reachable when `dir` is spelled differently from `stdpath("config")`,
  -- which is the symlinked-dotfiles case. Skipped entirely when there is no
  -- symlink to see past, since the two spellings are then the same string.
  if real ~= "" and real ~= norm and is_subpath(dir, real) then
    return real
  end

  return nil
end
