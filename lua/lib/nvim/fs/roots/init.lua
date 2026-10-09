---@module 'lib.nvim.fs.roots'
--- Named root directories (`$REPOS_DIR`, `$NVIM_CONFIG_DIR`, user-defined ones) kept in one
--- place, and the four things every plugin does with them:
---
---   * `expand(s)`  `$NAME/rest`, `${NAME}/rest`, `%NAME%\rest`, `~/rest` -> absolute path. Works
---                  for a root that has no real environment variable (`NVIM_CONFIG_DIR` is
---                  `stdpath("config")`, an `extra` root is a plain config value) and for
---                  `${NAME}`, which `vim.fn.expand` does not understand.
---   * `fold(abs)`  absolute path -> `$NAME/rest` -- what an action that hands an ABSOLUTE path to
---                  the user (clipboard, inserted links) writes, so the text means the same on a
---                  machine whose checkout sits on another drive.
---   * `remap(abs)` an absolute path recorded on ANOTHER machine -> where it would live under this
---                  machine's roots.
---   * `names()` / `roots()` what is known.
---
--- Why this is not just `vim.fn.expand`: measured on Neovim 0.12.2 / Windows, `expand`,
--- `vim.fs.normalize`, `glob` and `:edit` expand `$VAR` but NOT `${VAR}`; `filereadable`,
--- `isdirectory`, `readfile`, `io.open` and `vim.uv.fs_*` expand nothing; `fnamemodify(p, ":p")`
--- prepends the cwd to `$VAR/x`; and `vim.fs.normalize` expands `$X` in the MIDDLE of a path
--- too (`C:/data/$X/y` turns to garbage). Patching Neovim globally is not an option, so the rule
--- for callers is: **expand first, then normalize** -- and for a path that comes out of a buffer,
--- `vim.fs.normalize(p, { expand_env = false })`.
---
--- Only a LEADING reference is expanded: a root is an absolute path, so substituting one in the
--- middle of a string can only ever produce garbage. Anything unknown comes back unchanged.
---
--- Who configures what: `setup` belongs to the user's config -- it REPLACES the configuration, so
--- a plugin calling it would wipe the user's. A plugin adds its own roots with `register` (they
--- survive `setup`) and tunes a single call with the `names` / `nvim_config` options of
--- `roots` / `fold` / `folder` / `root_of`.
---
--- State is the configuration plus the registered roots; the roots themselves are re-read on every
--- call, so a changed environment is seen. For tests, `setup({ source = ... })` replaces the
--- environment AND `stdpath("config")` as the origin of every value -- there is deliberately no
--- silent fallback to the `stdpath` of whatever sandbox the test runs in.

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")
local drive_upper = require("lib.nvim.cross.fs.separators.drive_upper")
local is_windows = require("lib.nvim.cross.platform.is_windows")

local uv = vim.uv or vim.loop

local M = {}

local NVIM_CONFIG_NAME = "NVIM_CONFIG_DIR"

-- Set next to `NVIM_CONFIG_DIR` by `export_env`, to the value that was exported. A child process
-- inherits both, so "the variable still holds what lib.nvim exported" tells an inherited, stale
-- value (a parent Neovim with another `NVIM_APPNAME`) from one the user set on purpose.
local EXPORT_MARKER = "LIB_NVIM_ROOTS_EXPORTED"

-- What `parse_ref` can read back. A root named otherwise (`MY-ROOT`, `a.b`, `1ST`) could be folded
-- to `$MY-ROOT/x` but never expanded again, so it is refused up front.
local NAME_PAT = "^[%a_][%w_]*$"

---@type string[]
local DEFAULT_VARS = { "REPOS_DIR" }

---@type Lib.Fs.Roots.Config
local DEFAULTS = {
  enable = true,
  vars = DEFAULT_VARS,
  nvim_config = true,
  extra = {},
}

---@type Lib.Fs.Roots.Config
local _cfg = DEFAULTS

-- Roots added by plugins (`register`), kept apart from `_cfg` so that `setup` does not drop them.
---@type table<string, string|(fun(): string?)>
local _registered = {}

-- `name_key`s whose definition is being evaluated right now. A root function may ask the registry
-- about another root (`function() return roots.expand("$REPOS_DIR/notes") end`); the guard keeps a
-- definition that asks about itself -- directly or through a cycle -- from recursing.
---@type table<string, true>
local _active = {}

---@param level integer  the caller's level as for `error` (1 = the function that calls `fail`)
---@param msg string
local function fail(level, msg)
  error("[lib.nvim.fs.roots] " .. msg, level + 1)
end

---Whether paths are spelled and compared the Windows way. `setup({ windows = ... })` overrides the
---platform so the Windows rules can be pinned from a Linux runner.
---@return boolean
local function win()
  if _cfg.windows ~= nil then
    return _cfg.windows == true
  end
  return is_windows()
end

---Lowercase for a case-insensitive comparison. `string.lower` only folds ASCII, which leaves a
---non-ASCII profile path (`C:/Users/Müller`) case-sensitive on Windows, so anything with a high
---byte goes through `vim.fn.tolower` (one of the few Vimscript functions a fast event may call,
---unlike `vim.env`); the common all-ASCII path stays in Lua.
---
---The result need NOT be as long as `s` (`İ` 2 bytes -> `i` 1, `Ⱥ` 2 -> `ⱥ` 3): never use an
---offset into the lowered string on the original one.
---@param s string
---@return string
local function lower(s)
  if not s:find("[\128-\255]") then
    return s:lower()
  end
  return vim.fn.tolower(s)
end

---@param s string
---@return string
local function fold_case(s)
  return win() and lower(s) or s
end

---Whether `p` can only be spelled the Windows way (`C:\x`, `\\server\share`) -- a POSIX filename
---may legitimately contain a backslash, a drive letter or a leading `\\` it cannot.
---@param p string
---@return boolean
local function windows_shaped(p)
  return p:match("^%a:[/\\]") ~= nil or p:match("^\\\\") ~= nil
end

---Backslashes to slashes -- on Windows always, elsewhere only for a spelling that can only be a
---Windows one.
---@param p string
---@return string
local function unify(p)
  if win() or windows_shaped(p) then
    return unify_slashes(p)
  end
  return p
end

---Whether `p` ends in a separator of its own platform.
---@param p string
---@return boolean
local function ends_with_sep(p)
  if p:sub(-1) == "/" then
    return true
  end
  return p:sub(-1) == "\\" and (win() or windows_shaped(p))
end

---Canonical spelling of an absolute path: forward slashes, one separator between segments, no
---trailing separator, `.` and `..` resolved lexically (a `..` cannot climb above the drive, the
---UNC share or the filesystem root), uppercase drive letter, a leading `//` (UNC) kept -- on
---Windows, or when it was spelled with backslashes; on POSIX `//a` is `/a`. The root of a drive or
---of the filesystem comes out as `C:` / `""`.
---
---nil when `s` is not absolute (`"not_absolute"`) or holds a NUL byte (`"invalid_path"`: no
---filesystem call can see past it, so what is checked and what is used would differ).
---
---`lib.nvim.cross.fs.separators.collapse_dots` does the dots, but converts every backslash of the
---path to a slash -- wrong for a POSIX filename that has one -- and drops the leading `//`.
---@param s string
---@return string|nil
---@return "not_absolute"|"invalid_path"|nil why
local function clean_abs(s)
  if s:find("\0", 1, true) then
    return nil, "invalid_path"
  end
  local unc_spelled = s:sub(1, 2) == "\\\\"
  s = unify(s)

  local prefix, tail
  if s:match("^%a:/") then
    prefix, tail = s:sub(1, 2), s:sub(3)
  elseif s:match("^//[^/]") and (win() or unc_spelled) then
    prefix, tail = s:match("^(//[^/]+/[^/]+)(.*)$")
    if not prefix then
      prefix, tail = s:match("^(//[^/]+)(.*)$")
    end
  elseif s:sub(1, 1) == "/" then
    prefix, tail = "", s
  else
    return nil, "not_absolute"
  end

  local segs = {}
  for seg in tail:gmatch("[^/]+") do
    if seg == ".." then
      segs[#segs] = nil
    elseif seg ~= "." then
      segs[#segs + 1] = seg
    end
  end
  local joined = prefix .. (#segs > 0 and "/" .. table.concat(segs, "/") or "")
  return (drive_upper(joined))
end

---Reference at the very start of `s`: `$NAME`, `${NAME}`, `%NAME%`. The reference must be followed
---by the end of the string or a separator, so `$REPOS_DIRX`, `$REPOS_DIR.bak` and `${A}b` are not
---references to `REPOS_DIR` / `A`. A backslash separates only where it is one (Windows): on POSIX
---`$REPOS_DIR\x` is a file called `$REPOS_DIR\x`.
---@param s string
---@return string|nil name
---@return string|nil rest  everything after the reference (empty, or starting with a separator)
local function parse_ref(s)
  local name, rest = s:match("^%$%{([%a_][%w_]*)%}(.*)$")
  if not name then
    name, rest = s:match("^%$([%a_][%w_]*)(.*)$")
  end
  if not name then
    name, rest = s:match("^%%([%a_][%w_]*)%%(.*)$")
  end
  if not name then
    return nil, nil
  end
  if rest ~= "" and not rest:match(win() and "^[/\\]" or "^/") then
    return nil, nil
  end
  return name, rest
end

---The home directory in canonical spelling (`""` for a home that is the filesystem root, so
---`home .. "/x"` stays `/x`); nil when there is none or it is not absolute.
---@return string|nil
local function home_dir()
  local home = uv.os_homedir()
  if not home or home == "" then
    return nil
  end
  return (clean_abs(home))
end

---@param s string
---@return string|nil home  the home directory when `s` is `~` or `~/...`
---@return string|nil rest
local function parse_tilde(s)
  if s:sub(1, 1) ~= "~" then
    return nil, nil
  end
  local rest = s:sub(2)
  if rest ~= "" and not rest:match(win() and "^[/\\]" or "^/") then
    return nil, nil
  end
  local home = home_dir()
  if not home then
    return nil, nil
  end
  return home, rest
end

---A value as configured -> a string to work with, or the reason there is none.
---@param v any  a value, or a function returning one
---@return string|nil value
---@return "error"|"bad_type"|nil problem  nil with no value = simply not there (unset or empty)
---@return string|nil detail
local function resolve_value(v)
  if type(v) == "function" then
    local ok, r = pcall(v)
    if not ok then
      return nil, "error", tostring(r)
    end
    v = r
  end
  if v == nil or v == "" then
    return nil, nil, nil
  end
  if type(v) ~= "string" then
    return nil, "bad_type", type(v)
  end
  return v, nil, nil
end

---The raw value of an environment-style name: from the process environment, or from the injected
---`source`. May still be a function (a `source` table can hold one); see `resolve_value`.
---@param name string
---@return any
local function read_env(name)
  local src = _cfg.source
  if src == nil then
    -- libuv, not `vim.env`: the latter is a Vimscript round trip per read and raises E5560 in a
    -- fast event; both see the same process environment.
    return uv.os_getenv(name)
  end
  if type(src) == "function" then
    local ok, v = pcall(src, name)
    return ok and v or nil
  end
  if type(src) == "table" then
    return src[name]
  end
  return nil
end

---@param name string
---@return string
local function name_key(name)
  return win() and name:upper() or name
end

local collect

---Resolve the value of a root to an absolute, forward-slash path without trailing slash.
---
---A leading `~` or `$VAR` / `${VAR}` / `%VAR%` in the value is expanded: `$NAME` first as a known
---root (so `NOTES = "$REPOS_DIR/notes"` works however REPOS_DIR is defined), else from the
---environment or the injected source. A relative value is refused: it would resolve against
---whatever the cwd happens to be, and a root that moves with `:cd` is no root. So are the
---filesystem root and a whole drive -- as a root they would fold every path.
---@param value string
---@return string|nil root
---@return "unresolved_var"|"not_absolute"|"too_broad"|"invalid_path"|nil problem
---@return string|nil detail
local function to_root(value)
  local s = value
  local home, hrest = parse_tilde(s)
  if home then
    s = home .. hrest
  elseif s:sub(1, 1) == "~" and (s == "~" or s:match(win() and "^~[/\\]" or "^~/")) then
    return nil, "unresolved_var", "~"
  else
    local name, rest = parse_ref(s)
    if name then
      local base
      for _, e in ipairs(collect(name_key(name))) do
        if e.root then
          base = e.root
          break
        end
      end
      base = base or resolve_value(read_env(name))
      if not base then
        return nil, "unresolved_var", name
      end
      s = base .. rest
    end
  end

  local abs, why = clean_abs(s)
  if not abs then
    return nil, why
  end
  if abs == "" or abs:match("^%a:$") then
    return nil, "too_broad"
  end
  return abs
end

---One configured name with what became of it.
---@param kind "extra"|"registered"|"var"|"nvim_config"
---@param name string
---@param fetch fun(): any  the configured value, or a function returning it
---@return Lib.Fs.Roots.Status
local function build(kind, name, fetch)
  local value, problem, detail = resolve_value(fetch())
  if not value then
    return { name = name, kind = kind, problem = problem or "unset", detail = detail }
  end
  local root, why, why_detail = to_root(value)
  if not root then
    return { name = name, kind = kind, raw = value, problem = why, detail = why_detail }
  end
  return { name = name, kind = kind, raw = value, root = root }
end

---Every configured name in precedence order -- user-defined `extra` roots (sorted by name, so a
---result never depends on table iteration order), then roots `register`ed by plugins (sorted
---too), then `vars`, then `opts.names`, then `$NVIM_CONFIG_DIR` -- with its outcome. The first
---USABLE definition of a name wins (an `extra` function that returns nothing does not shadow the
---environment variable of that name); when none is usable the first one is reported.
---
---`only` (a `name_key`) restricts this to the definitions of one name and resolves nothing else --
---what `match` needs, and `expand_path` calls it for every `$VAR` it meets.
---@param only? string
---@param opts? Lib.Fs.Roots.Opts
---@return Lib.Fs.Roots.Status[]
function collect(only, opts)
  opts = opts or {}
  local out, index = {}, {}

  ---@param kind "extra"|"registered"|"var"|"nvim_config"
  ---@param name string
  ---@param fetch fun(): any  Called only when the definition is actually wanted.
  local function add(kind, name, fetch)
    local key = name_key(name)
    if (only and key ~= only) or _active[key] then
      return
    end
    local at = index[key]
    if at and out[at].root then
      return
    end
    local e
    if name:match(NAME_PAT) then
      _active[key] = true
      local ok, res = pcall(build, kind, name, fetch)
      _active[key] = nil
      e = ok and res or { name = name, kind = kind, problem = "error", detail = tostring(res) }
    else
      e = { name = name, kind = kind, problem = "invalid_name" }
    end
    if not at then
      out[#out + 1] = e
      index[key] = #out
    elseif e.root then
      out[at] = e
    end
  end

  ---@param kind "extra"|"registered"
  ---@param defs table<string, any>
  local function add_table(kind, defs)
    local names = {}
    for name in pairs(defs) do
      if type(name) == "string" and name ~= "" and (not only or name_key(name) == only) then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      add(kind, name, function()
        return defs[name]
      end)
    end
  end

  add_table("extra", _cfg.extra)
  add_table("registered", _registered)

  ---@param list any
  local function add_vars(list)
    for _, name in ipairs(list or {}) do
      if type(name) == "string" and name ~= "" then
        add("var", name, function()
          return read_env(name)
        end)
      end
    end
  end
  add_vars(_cfg.vars)
  add_vars(opts.names)

  local want_nvim = opts.nvim_config
  if want_nvim == nil then
    want_nvim = _cfg.nvim_config
  end
  if want_nvim then
    add("nvim_config", NVIM_CONFIG_NAME, function()
      -- Injected source: the value comes from the source and nowhere else. Falling back to the
      -- `stdpath` of the process would hand a test the root of its sandbox.
      if _cfg.source == nil then
        return vim.fn.stdpath("config")
      end
      return read_env(NVIM_CONFIG_NAME)
    end)
  end

  return out
end

local SETUP_KEYS = { "enable", "vars", "nvim_config", "extra", "source", "windows" }

---Apply the configuration. Replaces the previous one entirely (roots that plugins `register`ed
---stay); `setup()` resets to the defaults. `vars` has no merged default on purpose: a user's
---`{ "A" }` must not silently keep a default's second entry. A value of the wrong type, or a key
---that does not exist (a typo such as `extras`), raises: silently using the defaults instead would
---hide it. `vars` and `extra` are copied; `source` is kept as given, so a test can still change it.
---@param cfg? Lib.Fs.Roots.Config
---@return nil
function M.setup(cfg)
  if cfg == nil then
    cfg = {}
  end
  if type(cfg) ~= "table" then
    fail(2, ("setup: cfg must be a table, got %s"):format(type(cfg)))
  end
  for key in pairs(cfg) do
    if not vim.tbl_contains(SETUP_KEYS, key) then
      fail(
        2,
        ("setup: unknown option `%s` (known: %s)"):format(
          tostring(key),
          table.concat(SETUP_KEYS, ", ")
        )
      )
    end
  end

  ---@param key string
  ---@param ... string  accepted types
  local function expect(key, ...)
    local v = cfg[key]
    if v ~= nil and not vim.tbl_contains({ ... }, type(v)) then
      fail(
        3,
        ("setup: `%s` must be %s, got %s"):format(key, table.concat({ ... }, " or "), type(v))
      )
    end
  end
  expect("enable", "boolean")
  expect("vars", "table")
  expect("nvim_config", "boolean")
  expect("extra", "table")
  expect("source", "table", "function")
  expect("windows", "boolean")

  _cfg = {
    enable = cfg.enable ~= false,
    vars = cfg.vars and vim.list_extend({}, cfg.vars) or DEFAULT_VARS,
    nvim_config = cfg.nvim_config ~= false,
    extra = cfg.extra and vim.tbl_extend("force", {}, cfg.extra) or {},
    source = cfg.source,
    windows = cfg.windows,
  }
end

---Add a root from a plugin, without touching what the user configured with `setup` -- which
---replaces, so two plugins calling it would erase each other. Registered roots survive `setup`;
---on a name the user defined too (`extra`), the user wins. Registering a name again replaces the
---earlier registration.
---@param name string  letters, digits and underscores, not starting with a digit
---@param value string|(fun(): string?)  absolute path (`~` / `$VAR` allowed) or a function returning one
---@return fun() unregister  removes this registration again (a no-op once replaced)
function M.register(name, value)
  if type(name) ~= "string" or not name:match(NAME_PAT) then
    fail(
      2,
      ("register: `name` must be letters, digits and underscores, got %q"):format(tostring(name))
    )
  end
  if type(value) ~= "string" and type(value) ~= "function" then
    fail(2, ("register: `value` must be a string or a function, got %s"):format(type(value)))
  end
  _registered[name] = value
  return function()
    if _registered[name] == value then
      _registered[name] = nil
    end
  end
end

---Remove a registered root. Returns whether there was one.
---@param name string
---@return boolean
function M.unregister(name)
  local had = _registered[name] ~= nil
  _registered[name] = nil
  return had
end

---Whether actions should write the env-var form of an absolute path (`fold`, `remap`).
---@return boolean
function M.enabled()
  return _cfg.enable
end

---@param fn string
---@param opts any
---@param allowed table<string, true>
---@return table
local function check_opts(fn, opts, allowed)
  if opts == nil then
    return {}
  end
  if type(opts) ~= "table" then
    fail(3, ("%s: opts must be a table, got %s"):format(fn, type(opts)))
  end
  for key in pairs(opts) do
    if not allowed[key] then
      fail(3, ("%s: unknown option `%s`"):format(fn, tostring(key)))
    end
  end
  return opts
end

local ROOTS_OPTS = { names = true, nvim_config = true }
local FOLD_OPTS = { names = true, nvim_config = true, force = true }

---Every root that currently has a value, as `{ name, root }` with `root` absolute, forward-slash
---and without a trailing slash (and an uppercase drive letter). Independent of `enable`: that
---switch decides whether callers FOLD, not which roots exist. Order: `extra` (alphabetical),
---`register`ed (alphabetical), `vars`, `opts.names`, `NVIM_CONFIG_DIR`; the first usable
---definition of a name wins, so an `extra` entry overrides an environment variable of that name.
---@param opts? Lib.Fs.Roots.Opts
---@return Lib.Fs.Roots.Root[]
function M.roots(opts)
  opts = check_opts("roots", opts, ROOTS_OPTS)
  local out = {}
  for _, e in ipairs(collect(nil, opts)) do
    if e.root then
      out[#out + 1] = { name = e.name, root = e.root }
    end
  end
  return out
end

---The names of the known roots, in the order of `roots()`.
---@return string[]
function M.names()
  local out = {}
  for _, r in ipairs(M.roots()) do
    out[#out + 1] = r.name
  end
  return out
end

---Every configured name, including the ones without a usable value (`problem`: `"unset"`,
---`"unresolved_var"`, `"error"`, `"bad_type"`, `"not_absolute"`, `"too_broad"`, `"invalid_path"`
---or `"invalid_name"`), plus `exists` for the ones that have one. For `:checkhealth` and `json()`.
---@return Lib.Fs.Roots.Status[]
function M.status()
  local out = collect()
  for _, e in ipairs(out) do
    if e.root then
      local st = uv.fs_stat(e.root)
      e.exists = st ~= nil and st.type == "directory"
      if not e.exists then
        e.problem = "missing_dir"
      end
      -- The registry takes this root from `stdpath("config")`; an environment variable of the same
      -- name that says something else is what `vim.fn.expand` would use. Worth a line in health.
      if e.kind == "nvim_config" and _cfg.source == nil then
        local env = resolve_value(uv.os_getenv(NVIM_CONFIG_NAME))
        local env_root = env and to_root(env)
        if env_root and fold_case(env_root) ~= fold_case(e.root) then
          e.env = env_root
        end
      end
    end
  end
  return out
end

---Detect a leading reference to a known root.
---@param s string
---@return string|nil name   the root's name as configured
---@return string|nil root   its absolute path
---@return string|nil rest   the rest of `s` after the reference, verbatim
function M.match(s)
  if type(s) ~= "string" then
    return nil, nil, nil
  end
  local ref, rest = parse_ref(s)
  if not ref then
    return nil, nil, nil
  end
  for _, e in ipairs(collect(name_key(ref))) do
    if e.root then
      return e.name, e.root, rest
    end
  end
  return nil, nil, nil
end

---A root ready to be compared against many paths.
---@class Lib.Fs.Roots.Prepared
---@field name string
---@field key string    the folded root as one string, for the byte-wise comparison
---@field segs string[] the folded root, segment by segment (`"/a/b"` -> `{ "", "a", "b" }`)
---@field n integer     number of segments: deeper = more specific
---@field idx integer   position in `roots()` order

---The key a path is compared by byte-wise, or nil when no byte-wise comparison is safe. POSIX:
---the path itself. Windows: its lowercase -- but only for an ASCII path, because the lowercase of
---anything else may have a different length (see `lower`) and then an offset into it means
---nothing in the original.
---@param abs string
---@param windows boolean
---@return string|nil
local function byte_key(abs, windows)
  if not windows then
    return abs
  end
  if abs:find("[\128-\255]") then
    return nil
  end
  return abs:lower()
end

---@param list Lib.Fs.Roots.Root[]
---@param windows boolean
---@param real boolean  the symlink-resolved spelling of each root instead (only those that differ)
---@return Lib.Fs.Roots.Prepared[]
local function prepare(list, windows, real)
  local out = {}
  for i, r in ipairs(list) do
    local root = r.root ---@type string|nil
    if real then
      -- A buffer name is canonical on Unix (`~/.config/nvim` -> `~/dotfiles/nvim` opens as the
      -- latter), so a root reached through a symlink would never match what it contains.
      local rp = uv.fs_realpath(r.root)
      rp = rp and clean_abs((rp:gsub("^\\\\%?\\", "")))
      if rp and (windows and lower(rp) or rp) ~= (windows and lower(r.root) or r.root) then
        root = rp
      else
        root = nil
      end
    end
    if root then
      local segs = vim.split(root, "/", { plain = true })
      if windows then
        for j, seg in ipairs(segs) do
          segs[j] = lower(seg)
        end
      end
      out[#out + 1] = {
        name = r.name,
        key = windows and lower(root) or root,
        segs = segs,
        n = #segs,
        idx = i,
      }
    end
  end
  -- Deepest root first, so a nested root beats the one around it. Two names for one directory have
  -- the same depth: the earlier one in `roots()` order wins, not whichever `sort` put first.
  table.sort(out, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return a.idx < b.idx
  end)
  return out
end

---How many leading bytes of the canonical path `abs` the root `r` covers: all of it when `abs` IS
---the root, the root's part when `abs` lies below it (so `abs:sub(n + 1)` is `""` or `"/rest"`);
---nil when it is somewhere else. Segment boundaries only: `/repos2` is not below `/repos`.
---@param r Lib.Fs.Roots.Prepared
---@param abs string
---@param key string|nil  `byte_key(abs)`
---@return integer|nil
local function covers(r, abs, key)
  if key then
    if key == r.key then
      return #abs
    end
    if key:sub(1, #r.key + 1) == r.key .. "/" then
      return #r.key
    end
    return nil
  end

  -- Case folding that can change a length: compare segment by segment and take the offset from
  -- the ORIGINAL path.
  local start = 1
  for i = 1, r.n do
    local stop = abs:find("/", start, true)
    local seg_end = (stop or #abs + 1) - 1
    if lower(abs:sub(start, seg_end)) ~= r.segs[i] then
      return nil
    end
    if i == r.n then
      return seg_end
    end
    if not stop then
      return nil
    end
    start = stop + 1
  end
  return nil
end

---@param list Lib.Fs.Roots.Prepared[]
---@param abs string
---@param key string|nil
---@return Lib.Fs.Roots.Prepared|nil
---@return integer|nil covered
local function scan(list, abs, key)
  for _, r in ipairs(list) do
    local n = covers(r, abs, key)
    if n then
      return r, n
    end
  end
  return nil, nil
end

---The part of the absolute path `p` below the root `name`: `""` for the root itself, `"/rest"`
---below it; a trailing separator of `p` is kept (as `"/"`), so a completion candidate for a
---directory stays one. nil when `p` is not under that root. Separators and, on Windows, case and
---drive-letter case do not matter -- which is the point: a path that came back from the
---filesystem (a completion candidate) need not be spelled the way the root is. Compares the
---root as configured only (see `fold` for the symlink case).
---@param p string
---@param name string
---@return string|nil
function M.relative(p, name)
  if type(p) ~= "string" or type(name) ~= "string" then
    return nil
  end
  local root
  for _, e in ipairs(collect(name_key(name))) do
    if e.root then
      root = e
      break
    end
  end
  local abs = root and clean_abs(p)
  if not abs then
    return nil
  end
  local windows = win()
  local r = prepare({ root }, windows, false)[1]
  local n = covers(r, abs, byte_key(abs, windows))
  if not n then
    return nil
  end
  return abs:sub(n + 1) .. (ends_with_sep(p) and "/" or "")
end

---`$NAME/rest`, `${NAME}/rest`, `%NAME%/rest` (for the known roots) and `~/rest` -> absolute path.
---Anything else -- another variable, a reference in the middle of the string, an unknown or unset
---root, a name followed by something that is not a separator -- comes back untouched. Works
---whatever `enable` says: it only ever acts on text somebody wrote.
---
---On Windows the rest's backslashes become slashes, so the result is one consistent spelling;
---elsewhere the rest is kept verbatim, and only `/` ends the reference.
---@param s string
---@return string
function M.expand(s)
  if type(s) ~= "string" or s == "" then
    return s
  end
  local home, hrest = parse_tilde(s)
  if home then
    local tail = hrest or ""
    local out = home .. (win() and unify_slashes(tail) or tail)
    return out == "" and "/" or out
  end
  local _, root, rest = M.match(s)
  if not root then
    return s
  end
  local tail = rest or ""
  return root .. (win() and unify_slashes(tail) or tail)
end

---A function folding absolute paths into `$NAME/rest`, with the roots resolved ONCE -- for a caller
---folding many paths (a recursive file list). The function returns the folded path and the name of
---the root that matched (nil when none did). A path that is not absolute comes back unchanged.
---
---A path is compared with each root as configured first; only when none matches, with the
---symlink-resolved spelling of the roots (`uv.fs_realpath`, looked up once per folder). That is
---what a buffer name looks like on Unix when the root itself is a symlink.
---@param opts? Lib.Fs.Roots.FoldOpts
---@return fun(p: string): string, string|nil
function M.folder(opts)
  opts = check_opts("folder", opts, FOLD_OPTS)
  if not (_cfg.enable or opts.force) then
    return function(p)
      return p, nil
    end
  end

  local windows = win()
  local list = M.roots({ names = opts.names, nvim_config = opts.nvim_config })
  local primary = prepare(list, windows, false)
  local resolved ---@type Lib.Fs.Roots.Prepared[]|nil

  return function(p)
    if type(p) ~= "string" or p == "" then
      return p, nil
    end
    local abs = clean_abs(p)
    if not abs then
      return p, nil
    end
    local key = byte_key(abs, windows)
    local r, n = scan(primary, abs, key)
    if not r then
      resolved = resolved or prepare(list, windows, true)
      r, n = scan(resolved, abs, key)
    end
    if not r then
      return p, nil
    end
    return "$" .. r.name .. abs:sub(n + 1), r.name
  end
end

---Absolute `p` as `$NAME/rest` when it lives under one of the roots (the longest match wins, so a
---nested root beats the one around it); `p` unchanged otherwise. With `enable = false` (and no
---`opts.force`) always `p` unchanged. A relative `p` is returned as is. The comparison is
---lexical: `.` and `..` are resolved first, symlinks are not (except for a root that is one, see
---`folder`).
---@param p string
---@param opts? Lib.Fs.Roots.FoldOpts
---@return string result
---@return string|nil name  The root that matched, when one did.
function M.fold(p, opts)
  return M.folder(opts)(p)
end

---The name of the root `p` lives under (see `fold`), or nil.
---@param p string
---@param opts? Lib.Fs.Roots.FoldOpts
---@return string|nil
function M.root_of(p, opts)
  local _, name = M.fold(p, opts)
  return name
end

---Candidates for an absolute path that was recorded on ANOTHER machine, re-anchored under this
---machine's roots. The root's own folder name is the anchor: a root `D:/repos` is called `repos`
---on every machine, so the part of `E:/repos/casedesk.nvim/x.md` after `repos` is looked for
---under `D:/repos` (likewise `nvim` for `$NVIM_CONFIG_DIR`, whatever drive or home it sits on).
---The anchor may be the path's last segment (the recorded root itself). The anchor word compares
---case-insensitively when this machine is Windows or the recorded path is a Windows path. Only
---candidates that exist are returned, the OUTERMOST anchor first (the longest rest), each once.
---Empty when `enable = false`, `p` is not absolute, or nothing matches.
---
---`.` and `..` of the recorded path are resolved lexically first, so `E:/repos/../../etc/x` cannot
---climb out of the root it is re-anchored under.
---@param p string
---@return string[]
function M.remap(p)
  if not _cfg.enable or type(p) ~= "string" then
    return {}
  end
  local raw = clean_abs(p)
  if not raw then
    return {}
  end

  local segs = vim.split(raw, "/", { plain = true, trimempty = true })
  local anchor_case = win() or raw:match("^%a:") ~= nil or raw:sub(1, 2) == "//"
  local folded_raw = fold_case(raw)
  local hits, seen = {}, {}
  for _, r in ipairs(M.roots()) do
    local leaf = r.root:match("([^/]+)$")
    if leaf then
      local want = anchor_case and lower(leaf) or leaf
      for i = 1, #segs do
        if (anchor_case and lower(segs[i]) or segs[i]) == want then
          local cand = i == #segs and r.root or (r.root .. "/" .. table.concat(segs, "/", i + 1))
          local key = fold_case(cand)
          if not seen[key] and key ~= folded_raw and uv.fs_stat(cand) then
            seen[key] = true
            hits[#hits + 1] = cand
          end
        end
      end
    end
  end
  return hits
end

---The resolved roots as a JSON document, for a reader that is not Lua (the desktop hub asks
---through `nvim --headless`, see `print_json`):
---
---    {"version":1,"windows":false,
---     "roots":[{"name":"REPOS_DIR","root":"D:/repos","exists":true}],
---     "unresolved":[{"name":"X","problem":"unset"}]}
---
---`roots` holds the usable ones in `roots()` order; `unresolved` the configured names that have no
---usable value (see `status` for the `problem` values, plus `invalid_encoding`: a root that is not
---valid UTF-8, which a strict JSON reader would refuse as a whole) with the `detail` where there is
---one -- a root whose directory is missing stays in `roots` with `"exists": false`.
---@return string
function M.json()
  local safe = require("lib.lua.strings.safe")
  local roots, unresolved = {}, {}
  for _, e in ipairs(M.status()) do
    if e.root and safe.utf8(e.root) ~= e.root then
      unresolved[#unresolved + 1] = { name = e.name, problem = "invalid_encoding" }
    elseif e.root then
      roots[#roots + 1] = { name = e.name, root = e.root, exists = e.exists == true }
    else
      unresolved[#unresolved + 1] = {
        name = e.name,
        problem = e.problem,
        detail = e.detail and safe.utf8(e.detail) or nil,
      }
    end
  end
  return vim.json.encode({
    version = 1,
    windows = win(),
    roots = roots,
    unresolved = unresolved,
  })
end

---Write `json()` and a newline to stdout -- `print` goes to stderr in a headless instance, and the
---reader wants a clean stdout:
---
---    nvim --headless -c "lua require('lib.nvim.fs.roots').print_json()" -c "qa"
---
---Run it with the user's own config (not `-u NONE`), so `setup()` and its `extra` roots have run.
---A `-c` command runs BEFORE `VimEnter`, so a root that a plugin registers from a `VimEnter`
---handler (lazy loading) is not there yet. To see those too, print from `VimEnter` itself, after
---the handlers of the config (see the README).
---@return nil
function M.print_json()
  io.stdout:write(M.json(), "\n")
  io.stdout:flush()
end

---Make `$NVIM_CONFIG_DIR` a real environment variable (`stdpath("config")`) when none is set, so a
---child process -- a terminal, a job, `vim.fn.expand` itself -- understands it as well.
---
---A value the user set is never overwritten. One that lib.nvim itself exported in a parent Neovim
---(recognised by `LIB_NVIM_ROOTS_EXPORTED` holding the same value) is refreshed: the child may
---run another `NVIM_APPNAME`, and a stale value would make `vim.fn.expand` disagree with the
---registry. With an injected `source` nothing is exported: the process environment is not the
---thing under test. Opt out with `vim.g.lib_nvim_roots_no_export = true` (or `1`).
---@return boolean exported
function M.export_env()
  local opt_out = vim.g.lib_nvim_roots_no_export
  if _cfg.source ~= nil or opt_out == true or opt_out == 1 then
    return false
  end
  -- Setting the variable is a Vimscript call: not possible in a fast event, and nothing to retry
  -- there -- `plugin/lib_roots.lua` has already done it at startup.
  if vim.in_fast_event() then
    return false
  end
  local dir = vim.fn.stdpath("config")
  if type(dir) ~= "string" or dir == "" then
    return false
  end
  local cur = uv.os_getenv(NVIM_CONFIG_NAME)
  if cur ~= nil and cur ~= "" and cur ~= uv.os_getenv(EXPORT_MARKER) then
    return false
  end
  if cur == dir then
    return false
  end
  vim.env[NVIM_CONFIG_NAME] = dir
  vim.env[EXPORT_MARKER] = dir
  return true
end

-- Loading the module is the earliest moment every consumer passes through (`plugin/lib_roots.lua`
-- covers a startup that never requires it).
pcall(M.export_env)

---@type Lib.Fs.Roots
return M
