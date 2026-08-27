-- TESTS/spawn_env_spec.lua — lib.nvim.cross.run.env

return function(H)
  local eq, ok = H.eq, H.ok

  local env = require("lib.nvim.cross.run.env")
  local is_windows = require("lib.nvim.cross.platform.is_windows")()
  local sep = is_windows and ";" or ":"

  ---Lower-cased, trailing-separator-free key, mirroring the module's own
  ---Windows-insensitive dedup so assertions here compare like for like.
  ---@param p string
  local function key(p)
    p = p:gsub("[/\\]+$", "")
    return is_windows and p:gsub("/", "\\"):lower() or p
  end

  ---@param path string
  ---@return string[]
  local function split(path)
    local out = {}
    for part in path:gmatch("([^" .. sep .. "]+)") do
      out[#out + 1] = part
    end
    return out
  end

  -- ------------------------------------------------------------- aggregators

  eq(
    require("lib.nvim.cross").run.env,
    env,
    "aggregator: cross.run.env is the same module instance"
  )
  eq(type(require("lib").spawn_env.build), "function", "aggregator: lib.spawn_env is wired up")

  -- -------------------------------------------------------------- session_vars

  eq(env.SESSION_VARS.wsl, env.SESSION_VARS.linux, "SESSION_VARS: wsl aliases linux")

  local names = env.session_vars()
  ok(#names > 0, "session_vars: returns names for this platform")
  eq(names[1], env.SESSION_VARS.common[1], "session_vars: common vars come first")

  local platform = require("lib.nvim.cross.platform.is")()
  local seen_platform_var = false
  for _, name in ipairs(names) do
    if name == (env.SESSION_VARS[platform] or {})[1] then
      seen_platform_var = true
    end
  end
  ok(seen_platform_var, "session_vars: the current platform's vars are included")

  -- `session_vars()` must hand back a fresh list each call — `build()` appends
  -- `opts.passthrough` to it, and a shared table would grow without bound.
  local first_len = #env.session_vars()
  local scratch = env.session_vars()
  scratch[#scratch + 1] = "LIB_NVIM_SPEC_SCRATCH"
  eq(#env.session_vars(), first_len, "session_vars: returns a fresh list, not shared state")

  -- ------------------------------------------------------------------ missing

  local missing = env.missing()
  eq(type(missing), "table", "missing: returns a list")
  for _, name in ipairs(missing) do
    local v = vim.env[name]
    ok(v == nil or v == "", "missing: " .. name .. " really is absent from vim.env")
  end

  -- ----------------------------------------------------------- candidate_dirs

  local dirs = env.candidate_dirs()
  eq(type(dirs), "table", "candidate_dirs: returns a list")
  for _, dir in ipairs(dirs) do
    eq(vim.fn.isdirectory(dir), 1, "candidate_dirs: " .. dir .. " exists")
  end
  eq(env.candidate_dirs(), dirs, "candidate_dirs: cached across calls")

  -- --------------------------------------------------------------------- path

  local path = env.path()
  eq(type(path), "string", "path: returns a string")

  -- Nothing inherited may be dropped.
  for _, dir in ipairs(split(vim.env.PATH or "")) do
    local found = false
    for _, got in ipairs(split(path)) do
      if key(got) == key(dir) then
        found = true
        break
      end
    end
    ok(found, "path: inherited entry survives — " .. dir)
  end

  -- Every existing candidate must be present.
  for _, dir in ipairs(dirs) do
    local found = false
    for _, got in ipairs(split(path)) do
      if key(got) == key(dir) then
        found = true
        break
      end
    end
    ok(found, "path: candidate dir is present — " .. dir)
  end

  -- No duplicates, under the module's own comparison rules.
  local seen = {}
  for _, dir in ipairs(split(path)) do
    ok(not seen[key(dir)], "path: no duplicate entry for " .. dir)
    seen[key(dir)] = true
  end

  -- extra_paths win, in the order given.
  local extra_a = is_windows and "C:\\lib-nvim-spec\\a" or "/lib-nvim-spec/a"
  local extra_b = is_windows and "C:\\lib-nvim-spec\\b" or "/lib-nvim-spec/b"
  local with_extra = split(env.path({ extra_paths = { extra_a, extra_b } }))
  eq(key(with_extra[1]), key(extra_a), "path: first extra_path comes first")
  eq(key(with_extra[2]), key(extra_b), "path: extra_paths keep their order")

  -- A caller-supplied base is what gets extended, not vim.env.
  local based = env.path({ base = { PATH = extra_a } })
  ok(based:find(extra_a, 1, true) ~= nil, "path: opts.base supplies the inherited PATH")

  -- -------------------------------------------------------------------- build

  local built = env.build()
  eq(type(built), "table", "build: returns a table")

  local path_keys = {}
  for k in pairs(built) do
    if k:upper() == "PATH" then
      path_keys[#path_keys + 1] = k
    end
  end
  eq(#path_keys, 1, "build: exactly one PATH key, whatever its casing")
  eq(built[path_keys[1]], env.path(), "build: PATH is the completed one")

  -- The base is carried over, and `vars` wins over everything.
  local overridden = env.build({
    base = { PATH = extra_a, LIB_NVIM_SPEC_BASE = "base" },
    vars = { LIB_NVIM_SPEC_BASE = "override", LIB_NVIM_SPEC_EXTRA = "extra" },
  })
  eq(overridden.LIB_NVIM_SPEC_BASE, "override", "build: vars override base entries")
  eq(overridden.LIB_NVIM_SPEC_EXTRA, "extra", "build: vars add new entries")

  -- passthrough carries a name over from vim.env when the base lacks it.
  vim.env.LIB_NVIM_SPEC_PASS = "from-vim-env"
  local passed = env.build({ base = { PATH = extra_a }, passthrough = { "LIB_NVIM_SPEC_PASS" } })
  eq(passed.LIB_NVIM_SPEC_PASS, "from-vim-env", "build: passthrough pulls from vim.env")
  vim.env.LIB_NVIM_SPEC_PASS = nil

  -- -------------------------------------------------------------------- apply

  local spawn_opts = { cwd = "/tmp", text = true, env = { LIB_NVIM_SPEC_CALLER = "kept" } }
  local applied = env.apply(spawn_opts)
  eq(applied.cwd, "/tmp", "apply: unrelated options survive")
  eq(applied.text, true, "apply: unrelated options survive (boolean)")
  eq(applied.env.LIB_NVIM_SPEC_CALLER, "kept", "apply: a caller-supplied env entry survives")
  ok(applied.env[path_keys[1]] ~= nil, "apply: PATH is filled in")
  eq(type(spawn_opts.env.LIB_NVIM_SPEC_CALLER), "string", "apply: the input table is not mutated")
  eq(spawn_opts.env.PATH, nil, "apply: the input env table is not mutated")

  -- -------------------------------------------------------------------- array

  -- The dict -> array conversion raw uv.spawn's opts.env needs: extracted
  -- from pdfport.nvim's and reposcope.nvim's byte-identical copies.
  local arr = env.array({ LIB_NVIM_SPEC_ARRAY = "yes" })
  eq(type(arr), "table", "array: returns a table")
  local found_entry, path_entries = false, 0
  for _, kv in ipairs(arr) do
    ok(kv:match("^[^=]+=") ~= nil, "array: every entry is KEY=VALUE — got " .. kv)
    if kv == "LIB_NVIM_SPEC_ARRAY=yes" then
      found_entry = true
    end
    if kv:match("^[Pp][Aa][Tt][Hh]=") then
      path_entries = path_entries + 1
    end
  end
  ok(found_entry, "array: vars override lands as one KEY=VALUE entry")
  eq(path_entries, 1, "array: exactly one PATH entry, no case-duplicate on Windows")

  -- ------------------------------------------------------------ login_shell_env

  if is_windows then
    eq(env.login_shell_env(), nil, "login_shell_env: nil on native Windows")
  else
    local login = env.login_shell_env()
    ok(
      login == nil or type(login) == "table",
      "login_shell_env: a table or nil, never a raw string"
    )
    if login then
      ok(login.PATH ~= nil, "login_shell_env: a harvested environment carries PATH")
    end
  end

  -- -------------------------------------------------------------------- clear

  env.clear()
  eq(type(env.candidate_dirs()), "table", "clear: the scan re-runs cleanly afterwards")
end
