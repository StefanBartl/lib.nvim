-- TESTS/stdpath_config_root_spec.lua — lib.nvim.fs.stdpath_config_root.
--
-- The module exists because two root resolvers each compared a directory
-- against `vim.fn.stdpath("config")` with a plain string compare, and
-- `~/.config/nvim` is a symlink into a dotfiles repo on a very large share of
-- real setups. `stdpath("config")` reports that symlink verbatim while the
-- directory on the other side comes from a buffer name — and Unix Neovim
-- canonicalizes a path on the way into a buffer name. Two spellings of one
-- directory, no common prefix, a silent `false`, and the rule "the Neovim
-- config directory is a root of its own" quietly stops holding for exactly the
-- people whose config is version-controlled.
--
-- So the cases below need a *real* symlink. A junction is a different object
-- with different resolution semantics and would not pin the same thing.

local stdpath_config_root = require("lib.nvim.fs.stdpath_config_root")
local normkey = require("lib.nvim.fs.normkey")
local norm = vim.fs.normalize

--- Run `fn` with `stdpath("config")` answering `link`, restoring the real one
--- afterwards whatever happens — a leaked stub would redirect every later spec
--- in the run, and the runner shares one Neovim instance across all of them.
---@param link string
---@param fn fun(): nil
local function with_stdpath_config(link, fn)
  local orig = vim.fn.stdpath
  vim.fn.stdpath = function(what)
    if what == "config" then
      return link
    end
    return orig(what)
  end
  local ok, err = pcall(fn)
  vim.fn.stdpath = orig
  assert(ok, err)
end

--- Build `<base>/dotfiles/nvim` plus a `<base>/config_link` symlink to it, and
--- hand `fn` both spellings of that one directory.
---
--- Returns false when the symlink could not be created — having already said
--- so, loudly. See `report_skip` below for why that is not silent.
---@param fn fun(link: string, resolved: string): nil
---@return boolean ran
---@return string|nil err
local function with_symlinked_config(fn)
  local base = norm(vim.fn.tempname())
  vim.fn.mkdir(base .. "/dotfiles/nvim/lua", "p")
  base = normkey(base)

  local link = base .. "/config_link"
  local ok, err = (vim.uv or vim.loop).fs_symlink(
    base .. "/dotfiles/nvim",
    link,
    { dir = true, junction = false }
  )
  if ok ~= true then
    pcall(vim.fn.delete, base, "rf")
    return false, tostring(err)
  end

  local ran, ferr = pcall(fn, norm(link), normkey(link))
  pcall(vim.fn.delete, base, "rf")
  assert(ran, ferr)
  return true
end

--- Announce a skip so it cannot be read as a pass.
---
--- `TESTS/run.lua` prints `ok <spec>` for any spec that returns without
--- raising, so a spec that quietly skipped itself is indistinguishable in the
--- tally from one that ran — it reports confidence it never earned. The rules
--- here are `lsp.nvim`'s `probe_live_spec.lua` ones, for the same reason:
--- name the cause, write it to stderr as well as stdout, and **raise instead
--- of skipping under `CI` on any platform that is not Windows**.
---
--- The gate is on whether a symlink can actually be *made*, not on the
--- platform. That distinction earns its keep: creating one on Windows needs
--- `SeCreateSymbolicLinkPrivilege` (Developer Mode or elevation), so a blanket
--- `has("win32")` skip is the obvious move — and it would be wrong. Measured
--- on this workflow's own runners: ubuntu, macos *and* windows-latest all
--- create it, so all three run these cases. A plain platform skip would have
--- thrown away the Windows coverage that works.
---
--- Windows stays the one platform allowed to skip, because it is the one where
--- the privilege can genuinely be absent — a developer machine without
--- Developer Mode. Linux and macOS have no such excuse, and they are the
--- platforms that matter here: they are the ones whose Neovim canonicalizes a
--- buffer name, which is what puts the two spellings on opposite sides of the
--- comparison to begin with. The Windows escape hatch is kept rather than
--- tightened to match what the runner does today, since a future runner image
--- could drop the privilege and that should read as a skip rather than a
--- failure about the wrong thing.
---@param why string
local function report_skip(why)
  local message = (
    "stdpath_config_root_spec: SKIPPED — needs a real directory symlink, "
    .. "which this machine refused: %s"
  ):format(why)
  io.stderr:write("\n" .. message .. "\n")
  io.stdout:write(message .. "\n")

  local ci = vim.env.CI
  if ci ~= nil and ci ~= "" and ci ~= "false" and vim.fn.has("win32") ~= 1 then
    error("outside Windows a symlink must be creatable under CI, so: " .. message, 0)
  end
end

---@param H table
return function(H)
  -- ── no symlink involved: unchanged behaviour ──────────────────────────
  --
  -- Pinned first and without a symlink, because the fix must not rewrite the
  -- root for the setups that never had the problem. Every stub in this block
  -- is already `vim.fs.normalize`d (it comes from `norm(vim.fn.tempname())`),
  -- so `raw == norm` holds throughout and these cases cannot tell "returns
  -- raw" apart from "returns normalized" -- the case right after this block
  -- exists for exactly that distinction.
  do
    local raw = norm(vim.fn.tempname())
    vim.fn.mkdir(raw .. "/lua", "p")

    with_stdpath_config(raw, function()
      H.eq(stdpath_config_root(raw .. "/lua"), raw, "a directory inside the config dir")
      H.eq(stdpath_config_root(raw), raw, "the config dir itself")
    end)

    vim.fn.delete(raw, "rf")
  end

  -- ── raw vs normalized: the case the block above cannot see ────────────
  --
  -- Every stub elsewhere in this file is already `vim.fs.normalize`d (it
  -- comes from `norm(vim.fn.tempname())`), so none of them can tell "returns
  -- raw" apart from "returns normalized" -- an earlier version of this module
  -- returned `stdpath("config")` verbatim on a plain match, and every one of
  -- those cases stayed green regardless. This stub is deliberately not
  -- normalized: a doubled *interior* separator, which `vim.fs.normalize`
  -- collapses on every platform (unlike a native-Windows separator, which
  -- only Windows itself converts -- that shape is the second case below).
  --
  -- Doubling the LAST separator specifically, not e.g. every one of them:
  -- `vim.fs.normalize` special-cases a path that starts with `//` and
  -- preserves it (POSIX gives that leading form implementation-defined
  -- meaning, akin to a UNC root) -- measured, `//tmp/x` normalizes to
  -- `//tmp/x`, not `/tmp/x`. Doubling every separator would double the
  -- leading one on a POSIX `base`, and the stub would never resolve back to
  -- `base` at all -- a self-inflicted failure on every non-Windows runner,
  -- not evidence of anything about this module. Doubling only an interior one
  -- avoids the special case while still being unnormalized.
  do
    local base = norm(vim.fn.tempname())
    vim.fn.mkdir(base .. "/lua", "p")
    local unnormalized = base:gsub("/([^/]+)$", "//%1")

    with_stdpath_config(unnormalized, function()
      local dir = base .. "/lua"
      local root = stdpath_config_root(dir)
      H.eq(root, base, "returns the normalized spelling, not the doubled-separator one")
      H.eq(root, dir:sub(1, #root), "and that spelling is a genuine prefix of dir")
    end)

    vim.fn.delete(base, "rf")
  end

  -- The concrete, real-machine shape of the case above: `stdpath("config")`
  -- comes back with native separators on every call on Windows, measured
  -- (`vim.fn.stdpath("config")` -> `C:\Users\...\nvim`), which is exactly the
  -- un-normalized-raw-value scenario the case above covers abstractly. `dir`
  -- here is forward-slash (both production callers build it through
  -- `vim.fs.normalize`/`vim.fs.dirname`), so a backslash root returned
  -- verbatim would not be a string-prefix of it at all -- handing an LSP a
  -- root it cannot use. Windows-only: `vim.fs.normalize` only treats `\` as a
  -- separator when `win` is true (Neovim's own `vim.fs.normalize`, gated on
  -- the host, not on an option this module passes), so a backslash-laden stub
  -- would not reproduce anything on Linux/macOS -- it would just be a filename
  -- containing literal backslash characters there.
  if vim.fn.has("win32") == 1 then
    local base = norm(vim.fn.tempname())
    vim.fn.mkdir(base .. "/lua", "p")
    local native = base:gsub("/", "\\")

    with_stdpath_config(native, function()
      local dir = base .. "/lua"
      local root = stdpath_config_root(dir)
      H.eq(root, base, "returns the normalized spelling, not the native one")
      H.eq(root, dir:sub(1, #root), "and that spelling is a genuine prefix of dir")
    end)

    vim.fn.delete(base, "rf")
  end

  do
    local outside = norm(vim.fn.tempname())
    local config = norm(vim.fn.tempname())
    vim.fn.mkdir(outside .. "/lua", "p")
    vim.fn.mkdir(config, "p")

    with_stdpath_config(config, function()
      H.eq(stdpath_config_root(outside .. "/lua"), nil, "a directory outside answers nil")
    end)

    vim.fn.delete(outside, "rf")
    vim.fn.delete(config, "rf")
  end

  -- A sibling whose name merely starts with the config directory's name is not
  -- inside it. `is_subpath` already appends a separator for this; asserted
  -- here because this module is what decides an LSP's project boundary, and
  -- getting it wrong would hand the server the wrong tree entirely.
  do
    local base = norm(vim.fn.tempname())
    vim.fn.mkdir(base .. "/nvim", "p")
    vim.fn.mkdir(base .. "/nvim-extra", "p")

    with_stdpath_config(base .. "/nvim", function()
      H.eq(stdpath_config_root(base .. "/nvim-extra"), nil, "a name-prefix sibling is not inside")
    end)

    vim.fn.delete(base, "rf")
  end

  -- An empty `stdpath("config")` cannot be answered for. Without the guard,
  -- `is_subpath` appends a separator to the empty base and every absolute
  -- POSIX path comes back true — every file on the machine reported as part of
  -- the Neovim config.
  do
    with_stdpath_config("", function()
      H.eq(stdpath_config_root("/anywhere/at/all"), nil, "an empty config path answers nil")
    end)
  end

  do
    H.eq(stdpath_config_root(nil), nil, "nil answers nil")
    H.eq(stdpath_config_root(""), nil, "an empty dir answers nil")
  end

  -- ── the symlinked-dotfiles case ───────────────────────────────────────
  local ran, err = with_symlinked_config(function(link, resolved)
    with_stdpath_config(link, function()
      -- The bug, straight out: the spelling a Unix buffer name carries.
      H.eq(
        stdpath_config_root(resolved .. "/lua"),
        resolved,
        "the canonical spelling of the config dir is recognized as being inside it"
      )

      -- And the reason it is the canonical spelling that comes back rather
      -- than the raw one. A root has to be a prefix of the file it is a root
      -- *for*: handing an LSP `~/.config/nvim` for a buffer at
      -- `~/dotfiles/nvim/...` is worse than the miss it replaces. Measured
      -- against a real lua-language-server, it then indexes the tree through
      -- the symlink and answers textDocument/definition with the other
      -- spelling, so jumping to a definition opens a second buffer on a file
      -- that is already open.
      local dir = resolved .. "/lua"
      local root = stdpath_config_root(dir)
      H.eq(root, dir:sub(1, #root), "the returned root is a prefix of the directory asked about")

      -- The link spelling resolves too — both spellings of the one directory
      -- answer, each to a root that is a prefix of itself. `link` here is
      -- already normalized (`with_symlinked_config` hands back `norm(link)`),
      -- so this does not by itself distinguish "returns raw" from "returns
      -- normalized" -- the earlier native-separator case does that.
      H.eq(stdpath_config_root(link .. "/lua"), link, "the link spelling resolves to itself")
    end)
  end)

  if not ran then
    report_skip(err or "unknown")
  end

  -- ── the cache is keyed, not held ──────────────────────────────────────
  --
  -- The canonical spelling is resolved once per `stdpath("config")` value
  -- rather than once per session, so a later stub is seen instead of a stale
  -- answer being served.
  --
  -- Not order-dependent, despite running last: `first` and `second` are two
  -- fresh temp paths built inside this one block, and the switch from one to
  -- the other happens entirely within it, so the cache-hit-then-miss it
  -- exercises does not depend on whatever this spec (or an earlier one in the
  -- suite) already warmed the cache to. Placed last only because it is the
  -- one case whose name is directly about the cache, not because an earlier
  -- position would make it pass trivially -- it would not.
  do
    local first = norm(vim.fn.tempname())
    local second = norm(vim.fn.tempname())
    vim.fn.mkdir(first .. "/lua", "p")
    vim.fn.mkdir(second .. "/lua", "p")

    with_stdpath_config(first, function()
      H.eq(stdpath_config_root(first .. "/lua"), first, "resolves under the first config path")
    end)
    with_stdpath_config(second, function()
      H.eq(stdpath_config_root(second .. "/lua"), second, "and follows a changed one")
      H.eq(stdpath_config_root(first .. "/lua"), nil, "without still answering for the old one")
    end)

    vim.fn.delete(first, "rf")
    vim.fn.delete(second, "rf")
  end
end
