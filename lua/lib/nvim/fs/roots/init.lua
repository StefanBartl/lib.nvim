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
--- State is the configuration only (`setup`); the roots themselves are re-read on every call, so
--- a changed environment is seen. For tests, `setup({ source = ... })` replaces the environment
--- AND `stdpath("config")` as the origin of every value -- there is deliberately no silent
--- fallback to the `stdpath` of whatever sandbox the test runs in.

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")
local drive_upper = require("lib.nvim.cross.fs.separators.drive_upper")
local is_windows = require("lib.nvim.cross.platform.is_windows")

local uv = vim.uv or vim.loop

local M = {}

local NVIM_CONFIG_NAME = "NVIM_CONFIG_DIR"

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
---byte goes through `vim.fn.tolower`; the common all-ASCII path stays in Lua.
---@param s string
---@return string
local function lower(s)
  if not s:find("[\128-\255]") then
    return s:lower()
  end
  return vim.fn.tolower(s)
end

---Apply the configuration. Replaces the previous one entirely; `setup()` resets to the defaults.
---`vars` has no merged default on purpose: a user's `{ "A" }` must not silently keep a default's
---second entry.
---@param cfg? Lib.Fs.Roots.Config
---@return nil
function M.setup(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  _cfg = {
    enable = cfg.enable ~= false,
    vars = type(cfg.vars) == "table" and cfg.vars or DEFAULT_VARS,
    nvim_config = cfg.nvim_config ~= false,
    extra = type(cfg.extra) == "table" and cfg.extra or {},
    source = cfg.source,
    windows = cfg.windows,
  }
end

---Whether actions should write the env-var form of an absolute path (`fold`, `remap`).
---@return boolean
function M.enabled()
  return _cfg.enable
end

---@param v any  a value, or a function returning one
---@return string|nil
local function resolve_value(v)
  if type(v) == "function" then
    local ok, r = pcall(v)
    v = ok and r or nil
  end
  if type(v) == "string" and v ~= "" then
    return v
  end
  return nil
end

---The raw value of an environment-style name: from `vim.env`, or from the injected `source`.
---@param name string
---@return string|nil
local function read_env(name)
  local src = _cfg.source
  if src == nil then
    -- libuv, not `vim.env`: the latter is a Vimscript round trip per read and raises E5560 in a
    -- fast event; both see the same process environment.
    return resolve_value(uv.os_getenv(name))
  end
  if type(src) == "function" then
    local ok, v = pcall(src, name)
    return ok and resolve_value(v) or nil
  end
  if type(src) == "table" then
    return resolve_value(src[name])
  end
  return nil
end

---Backslashes to slashes -- on Windows always, elsewhere only for a spelling that can only be a
---Windows one (`C:\x`, `\\server\share`): a POSIX filename may legitimately contain a backslash.
---@param p string
---@return string
local function unify(p)
  if win() or p:match("^%a:[/\\]") or p:match("^\\\\") then
    return unify_slashes(p)
  end
  return p
end

---@param s string
---@return string
local function fold_case(s)
  return win() and lower(s) or s
end

---Canonical spelling of an absolute path: forward slashes, one separator between segments, no
---trailing separator, uppercase drive letter, a leading `//` (UNC) kept. nil when `s` is not
---absolute. The root of a drive or of the filesystem comes out as `C:` / `""`.
---@param s string
---@return string|nil
local function clean_abs(s)
  s = unify(s)
  if not (s:match("^%a:/") or s:sub(1, 1) == "/") then
    return nil
  end
  local unc = s:match("^//[^/]") ~= nil
  s = s:gsub("/+", "/"):gsub("/$", "")
  if unc then
    s = "/" .. s
  end
  return (drive_upper(s))
end

---Reference at the very start of `s`: `$NAME`, `${NAME}`, `%NAME%`. The reference must be followed
---by the end of the string or a separator, so `$REPOS_DIRX`, `$REPOS_DIR.bak` and `${A}b` are not
---references to `REPOS_DIR` / `A`.
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
  if rest ~= "" and not rest:match("^[/\\]") then
    return nil, nil
  end
  return name, rest
end

---@param s string
---@return string|nil home  the home directory when `s` is `~` or `~/...`
---@return string|nil rest
local function parse_tilde(s)
  if s:sub(1, 1) ~= "~" then
    return nil, nil
  end
  local rest = s:sub(2)
  if rest ~= "" and not rest:match("^[/\\]") then
    return nil, nil
  end
  local home = uv.os_homedir()
  if not home or home == "" then
    return nil, nil
  end
  return home, rest
end

---Resolve the value of a root to an absolute, forward-slash path without trailing slash; nil for
---anything that cannot serve as a root.
---
---A leading `~` or `$VAR` / `${VAR}` / `%VAR%` in the value is expanded (from the environment or
---the injected source -- never from other roots). A relative value is refused: it would resolve
---against whatever the cwd happens to be, and a root that moves with `:cd` is no root.
---@param value string
---@return string|nil
local function to_root(value)
  local s = value
  local home, hrest = parse_tilde(s)
  if home then
    s = home .. hrest
  else
    local name, rest = parse_ref(s)
    if name then
      local env = read_env(name)
      if not env then
        return nil
      end
      s = env .. rest
    end
  end

  s = clean_abs(s)
  -- A whole drive or the filesystem root as a root would fold every path on it.
  if not s or s == "" or s:match("^%a:$") then
    return nil
  end
  return s
end

---One configured name with what became of it.
---@param kind "extra"|"var"|"nvim_config"
---@param name string
---@param raw string|nil  the value before normalization
---@return Lib.Fs.Roots.Status
local function entry(kind, name, raw)
  if raw == nil then
    return { name = name, kind = kind, problem = "unset" }
  end
  local root = to_root(raw)
  if not root then
    return { name = name, kind = kind, raw = raw, problem = "not_absolute" }
  end
  return { name = name, kind = kind, raw = raw, root = root }
end

---@param name string
---@return string
local function name_key(name)
  return win() and name:upper() or name
end

---Every configured name in precedence order -- user-defined `extra` roots (sorted by name, so a
---result never depends on table iteration order), then `vars`, then `$NVIM_CONFIG_DIR` -- with
---its outcome. The first USABLE definition of a name wins (an `extra` function that returns
---nothing does not shadow the environment variable of that name); when none is usable the first
---one is reported.
---
---`only` (a `name_key`) restricts this to the definitions of one name and resolves nothing else --
---what `match` needs, and `expand_path` calls it for every `$VAR` it meets.
---@param only? string
---@return Lib.Fs.Roots.Status[]
local function collect(only)
  local out, index = {}, {}

  ---@param kind "extra"|"var"|"nvim_config"
  ---@param name string
  ---@param fetch fun(): any  Called only when the definition is actually wanted.
  local function add(kind, name, fetch)
    local key = name_key(name)
    if only and key ~= only then
      return
    end
    local at = index[key]
    if at and out[at].root then
      return
    end
    local e
    if name:match(NAME_PAT) then
      e = entry(kind, name, resolve_value(fetch()))
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

  local extra_names = {}
  for name in pairs(_cfg.extra) do
    if type(name) == "string" and name ~= "" and (not only or name_key(name) == only) then
      extra_names[#extra_names + 1] = name
    end
  end
  table.sort(extra_names)
  for _, name in ipairs(extra_names) do
    add("extra", name, function()
      return _cfg.extra[name]
    end)
  end

  for _, name in ipairs(_cfg.vars) do
    if type(name) == "string" and name ~= "" then
      add("var", name, function()
        return read_env(name)
      end)
    end
  end

  if _cfg.nvim_config then
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

---Every root that currently has a value, as `{ name, root }` with `root` absolute, forward-slash
---and without a trailing slash. Independent of `enable`: that switch decides whether callers FOLD,
---not which roots exist. Order: `extra` (alphabetical), `vars`, `NVIM_CONFIG_DIR`; the first
---definition of a name wins, so an `extra` entry overrides an environment variable of that name.
---@return Lib.Fs.Roots.Root[]
function M.roots()
  local out = {}
  for _, e in ipairs(collect()) do
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

---Every configured name, including the ones without a usable value (`problem = "unset"`,
---`"not_absolute"` or `"invalid_name"`), plus `exists` for the ones that have one. For
---`:checkhealth` and `json()`.
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

---The part of the absolute path `p` below the root `name`: `""` for the root itself, `"/rest"`
---below it; a trailing separator of `p` is kept (as `"/"`), so a completion candidate for a
---directory stays one. nil when `p` is not under that root. Separators and, on Windows, case and
---drive-letter case do not matter -- which is the point: a path that came back from the
---filesystem (a completion candidate) need not be spelled the way the root is.
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
      root = e.root
      break
    end
  end
  local abs = root and clean_abs(p)
  if not abs then
    return nil
  end
  local trail = p:match("[/\\]$") and "/" or ""
  local key, rkey = fold_case(abs), fold_case(root)
  if key == rkey then
    return trail
  end
  if key:sub(1, #rkey + 1) == rkey .. "/" then
    return abs:sub(#root + 1) .. trail
  end
  return nil
end

---`$NAME/rest`, `${NAME}/rest`, `%NAME%/rest` (for the known roots) and `~/rest` -> absolute path.
---Anything else -- another variable, a reference in the middle of the string, an unknown or unset
---root, a name followed by something that is not a separator -- comes back untouched. Works
---whatever `enable` says: it only ever acts on text somebody wrote.
---
---On Windows the rest's backslashes become slashes, so the result is one consistent spelling;
---elsewhere the rest is kept verbatim.
---@param s string
---@return string
function M.expand(s)
  if type(s) ~= "string" or s == "" then
    return s
  end
  local home, hrest = parse_tilde(s)
  if home then
    return unify(home) .. (win() and unify_slashes(hrest) or hrest)
  end
  local _, root, rest = M.match(s)
  if not root then
    return s
  end
  return root .. (win() and unify_slashes(rest) or rest)
end

---@class Lib.Fs.Roots.FoldOpts
---@field force? boolean  Fold even when `enable` is false -- for an action the user asked for by name.

---A function folding absolute paths into `$NAME/rest`, with the roots resolved ONCE -- for a caller
---folding many paths (a recursive file list). The function returns the folded path and the name of
---the root that matched (nil when none did). A path that is not absolute comes back unchanged.
---@param opts? Lib.Fs.Roots.FoldOpts
---@return fun(p: string): string, string|nil
function M.folder(opts)
  if not (_cfg.enable or (type(opts) == "table" and opts.force)) then
    return function(p)
      return p, nil
    end
  end

  local windows = win()
  local prepared = {}
  for i, r in ipairs(M.roots()) do
    prepared[#prepared + 1] = {
      name = r.name,
      key = windows and lower(r.root) or r.root,
      len = #r.root,
      idx = i,
    }
  end
  -- Longest root first, so a nested root beats the one around it. Two names for one directory
  -- have the same length: the earlier one in `roots()` order wins, not whichever `sort` put first.
  table.sort(prepared, function(a, b)
    if a.len ~= b.len then
      return a.len > b.len
    end
    return a.idx < b.idx
  end)

  return function(p)
    if type(p) ~= "string" or p == "" then
      return p, nil
    end
    local abs = clean_abs(p)
    if not abs then
      return p, nil
    end
    local key = windows and lower(abs) or abs
    for _, r in ipairs(prepared) do
      if key == r.key then
        return "$" .. r.name, r.name
      end
      if key:sub(1, r.len + 1) == r.key .. "/" then
        return "$" .. r.name .. "/" .. abs:sub(r.len + 2), r.name
      end
    end
    return p, nil
  end
end

---Absolute `p` as `$NAME/rest` when it lives under one of the roots (the longest match wins, so a
---nested root beats the one around it); `p` unchanged otherwise. With `enable = false` (and no
---`opts.force`) always `p` unchanged. A relative `p` is returned as is.
---@param p string
---@param opts? Lib.Fs.Roots.FoldOpts
---@return string result
---@return string|nil name  The root that matched, when one did.
function M.fold(p, opts)
  return M.folder(opts)(p)
end

---Candidates for an absolute path that was recorded on ANOTHER machine, re-anchored under this
---machine's roots. The root's own folder name is the anchor: a root `D:/repos` is called `repos`
---on every machine, so the part of `E:/repos/casedesk.nvim/x.md` after `repos` is looked for
---under `D:/repos` (likewise `nvim` for `$NVIM_CONFIG_DIR`, whatever drive or home it sits on).
---Only candidates that exist are returned, nearest anchor first, each once. Empty when
---`enable = false`, `p` is not absolute, or nothing matches.
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
  -- A recorded path is somebody else's data. `E:/repos/../../etc/x` re-anchored under a root
  -- would climb out of it, so a path that is not already canonical maps to nothing.
  for _, seg in ipairs(segs) do
    if seg == ".." then
      return {}
    end
  end
  local folded_raw = fold_case(raw)
  local hits, seen = {}, {}
  for _, r in ipairs(M.roots()) do
    local leaf = r.root:match("([^/]+)$")
    if leaf then
      local folded_leaf = fold_case(leaf)
      for i = 1, #segs - 1 do
        if fold_case(segs[i]) == folded_leaf then
          local cand = r.root .. "/" .. table.concat(segs, "/", i + 1)
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
---usable value (`unset`, `not_absolute`, `invalid_name`) -- a root whose directory is missing stays in `roots`
---with `"exists": false`.
---@return string
function M.json()
  local roots, unresolved = {}, {}
  for _, e in ipairs(M.status()) do
    if e.root then
      roots[#roots + 1] = { name = e.name, root = e.root, exists = e.exists == true }
    else
      unresolved[#unresolved + 1] = { name = e.name, problem = e.problem }
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
---@return nil
function M.print_json()
  io.stdout:write(M.json(), "\n")
  io.stdout:flush()
end

---Make `$NVIM_CONFIG_DIR` a real environment variable (`stdpath("config")`) when none is set, so a
---child process -- a terminal, a job, `vim.fn.expand` itself -- understands it as well. Never
---overwrites. With an injected `source` nothing is exported: the process environment is not the
---thing under test. Opt out with `vim.g.lib_nvim_roots_no_export = true`.
---@return boolean exported
function M.export_env()
  if _cfg.source ~= nil or vim.g.lib_nvim_roots_no_export == true then
    return false
  end
  -- Setting the variable is a Vimscript call: not possible in a fast event, and nothing to retry
  -- there -- `plugin/lib_roots.lua` has already done it at startup.
  if vim.in_fast_event() then
    return false
  end
  local cur = uv.os_getenv(NVIM_CONFIG_NAME)
  if cur ~= nil and cur ~= "" then
    return false
  end
  local dir = vim.fn.stdpath("config")
  if type(dir) ~= "string" or dir == "" then
    return false
  end
  vim.env[NVIM_CONFIG_NAME] = dir
  return true
end

-- Loading the module is the earliest moment every consumer passes through (`plugin/lib_roots.lua`
-- covers a startup that never requires it).
pcall(M.export_env)

---@type Lib.Fs.Roots
return M
