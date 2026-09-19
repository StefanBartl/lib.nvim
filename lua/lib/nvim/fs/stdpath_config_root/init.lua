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
--- resolved once and kept, and the comparison itself stays a pure string
--- compare. The cache is keyed on the raw value rather than held
--- unconditionally: a test that stubs `vim.fn.stdpath` -- which is the only
--- way to test any of this -- then gets a fresh resolution instead of a stale
--- one, with no cache-invalidation call to forget. All three spellings are
--- written together, from locals computed before any of them is assigned: a
--- `vim.fs.normalize`/`normkey` call that raised partway through used to be
--- able to leave `cached_raw` updated while `cached_norm`/`cached_real` still
--- held the previous value's derivation -- three spellings describing two
--- different directories. Neither call raises in practice, so this was never
--- observed, but the fix costs nothing and removes the question.
---
--- Both known spellings are tried, and that covers both platforms without
--- resolving `dir`: Unix hands the caller the canonical spelling (it
--- canonicalizes buffer names), Windows hands it the literal one (measured: it
--- does not). A `dir` in some third spelling -- behind a symlink of its own --
--- still misses, and still costs nothing.
---
--- ## Which spelling is returned
---
--- The normalized one, on either branch -- never the raw value. An earlier
--- version returned `stdpath("config")` verbatim on a plain match, reasoning
--- that "nothing that resolved correctly before resolves differently now".
--- That missed that `is_subpath` matches on the *normalized* form while the
--- verbatim value can still differ from it: `vim.fn.stdpath("config")` comes
--- back with native separators (backslashes, measured, on every call on
--- Windows), so the returned root was not actually a prefix of the `dir` it
--- was a root *for* -- the exact defect the symlink branch exists to avoid,
--- reappearing in the branch that was supposed to be the safe one. Measured
--- consequence: `lsp.nvim`'s `build_library` concatenates the root with a
--- forward slash, so a backslash root produced a second, differently-spelled
--- workspace-library entry for the same directory lua_ls already had. Unix is
--- unaffected -- `vim.fs.normalize` is a no-op there for any path already
--- free of `~`, `//`, and `./`, which every `stdpath("config")` is -- so this
--- only ever changes the separators of the value Windows gets back, not which
--- directory is named.
---
---@see lib.nvim.fs.polymorphic_rootresolver
---@see lib.nvim.fs.is_subpath

local normkey = require("lib.nvim.fs.normkey")

---@type string|nil # the raw `stdpath("config")` the two below were derived from
local cached_raw
---@type string|nil # `cached_raw` under `vim.fs.normalize`
local cached_norm
---@type string|nil # `cached_raw` under `normkey` (symlinks resolved)
local cached_real

--- The config directory in both spellings, resolving at most once per value.
---
--- All three are written together at the end, from locals -- not assigned as
--- each is computed -- so a call that raises midway (it does not, in
--- practice; see the module docstring) leaves the previous, self-consistent
--- triple in place rather than a mix of two directories' spellings.
---@return string raw # exactly what `stdpath("config")` returned
---@return string norm # `raw` normalized
---@return string real # `raw` canonicalized
local function spellings()
  local raw = vim.fn.stdpath("config") --[[@as string]]
  if raw ~= cached_raw then
    local norm = vim.fs.normalize(raw)
    local real = normkey(raw)
    cached_raw, cached_norm, cached_real = raw, norm, real
  end
  -- The casts are honest, not silencing: `cached_raw` starting `nil` is what
  -- makes the `~=` above true and the branch run on the very first call, so
  -- by the time any `return` executes here, all three have been assigned --
  -- luals just cannot see across the branch to know that.
  -- stylua: ignore
  return cached_raw --[[@as string]], cached_norm --[[@as string]], cached_real --[[@as string]]
end

--- `is_subpath(path, base)` re-normalizes *both* arguments on every call --
--- cheap in isolation, but wasted here: `norm`/`real` below are already
--- normalized, and re-normalizing them was measured as the bulk of this
--- module's per-call cost. `path` is normalized once by the caller instead,
--- and this compares two already-normalized strings directly -- the same
--- equality/length/prefix logic `is_subpath` itself uses, just without the
--- redundant second pass.
---@param path string # already normalized
---@param base string # already normalized
---@return boolean
local function prefix_match(path, base)
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

--- The Neovim config directory, if `dir` lies inside it.
---
--- @param dir string|nil directory to test; anything else answers nil
--- @return string|nil root the config directory, normalized, in a spelling
---   that is a genuine prefix of `dir`; nil when `dir` is not inside it
return function(dir)
  if type(dir) ~= "string" or dir == "" then
    return nil
  end

  local raw, norm, real = spellings()

  -- An empty `stdpath("config")` cannot be answered for. Without this guard
  -- every absolute POSIX path would come back a match below -- every file on
  -- the machine reported as part of the Neovim config.
  if raw == "" then
    return nil
  end

  local ndir = vim.fs.normalize(dir)

  if prefix_match(ndir, norm) then
    return norm
  end

  -- Only reachable when `dir` is spelled differently from `stdpath("config")`,
  -- which is the symlinked-dotfiles case. Skipped entirely when there is no
  -- symlink to see past, since the two spellings are then the same string --
  -- `real` cannot be empty here: `raw` is non-empty (guarded above), and
  -- `normkey` only ever answers `""` for a non-string or empty input.
  if real ~= norm and prefix_match(ndir, real) then
    return real
  end

  return nil
end
