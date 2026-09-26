-- TESTS/cross_executable_spec.lua — lib.nvim.cross.executable (+ its $PATH index)

return function(H)
  local eq, ok = H.eq, H.ok

  -- vim.env is read-only for luacheck; setenv is the same effect on the process.
  ---@param name string
  ---@param value string|nil
  local function setenv(name, value)
    vim.fn.setenv(name, value == nil and vim.NIL or value)
  end

  local index = require("lib.nvim.cross.executable.index")
  local executable = require("lib.nvim.cross.executable")
  local is_windows = require("lib.nvim.cross.platform.is_windows")()

  -- A directory of empty files: name -> present. `sub/` is a directory named
  -- like an executable, which must never be indexed.
  ---@param files string[]
  ---@return string dir
  local function make_dir(files)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/tools.exe", "p") -- a directory with an executable's name
    for _, name in ipairs(files) do
      vim.fn.writefile({}, dir .. "/" .. name)
    end
    return dir
  end

  -- ------------------------------------------------------------ index.scan
  local first = make_dir({
    "alpha.exe",
    "beta.cmd",
    "notes.txt",
    "Gamma.EXE",
    "dual.exe",
    "dual.com",
    "plain",
    "both",
    "both.cmd",
  })
  -- `second` has the expansion of a name whose EXACT file lives in `first`, and
  -- an exact file named like a bare name that `first` only has as an expansion.
  local second = make_dir({ "alpha.exe", "delta.bat", "beta", "plain.exe" })
  local exts = { ".com", ".exe", ".bat", ".cmd" }

  local map = index.scan({ first, second }, exts)
  local function under(dir, path)
    return path ~= nil and vim.fs.normalize(path):find(vim.fs.normalize(dir), 1, true) == 1
  end

  ok(map["alpha"], "index.scan: a bare name resolves")
  ok(map["alpha.exe"], "index.scan: the name with its extension resolves too")
  ok(under(first, map["alpha"]), "index.scan: the first $PATH directory wins")
  ok(map["delta"] and under(second, map["delta"]), "index.scan: a later directory is indexed")
  eq(
    map["notes"],
    nil,
    "index.scan: a bare name is not expanded with an extension outside $PATHEXT"
  )
  ok(map["notes.txt"], "index.scan: ... but the exact file name counts, as vim.fn.executable does")
  ok(
    map["plain"] and under(first, map["plain"]),
    "index.scan: a file without extension counts (npm, code)"
  )
  ok(
    map["both"] and map["both"]:lower():find("both$"),
    "index.scan: an exact name beats its own expansion (both over both.cmd)"
  )
  ok(map["both.cmd"], "index.scan: ... and the expansion is still there under its full name")
  ok(
    map["beta"] and under(first, map["beta"]) and map["beta"]:lower():find("beta%.cmd$"),
    "index.scan: an earlier directory's expansion beats a later directory's exact name (PATH order first)"
  )
  ok(map["gamma"], "index.scan: matching is case-insensitive (Gamma.EXE)")
  ok(
    map["dual"] and map["dual"]:lower():find("dual%.com$"),
    "index.scan: $PATHEXT rank decides inside one directory (.com before .exe)"
  )
  eq(map["tools"], nil, "index.scan: a directory named tools.exe is not an executable")

  local reversed = index.scan({ first }, { ".exe", ".com" })
  ok(reversed["dual"]:lower():find("dual%.exe$"), "index.scan: a different $PATHEXT order flips it")

  local dedup = index.scan({ first, first .. "/", first:upper() }, exts)
  ok(
    dedup["alpha"],
    "index.scan: the same directory spelled three ways is scanned once and harmless"
  )
  eq(
    index.scan({ vim.fn.tempname() .. "-missing" }, exts)["alpha"],
    nil,
    "index.scan: a missing directory is skipped"
  )

  -- ------------------------------------------------------ platform gating
  eq(index.supported(), is_windows, "index.supported: native Windows only")
  if not is_windows then
    local path, known = index.lookup("git")
    eq(known, false, "index.lookup: off Windows the index never answers")
    eq(path, nil, "index.lookup: ... and returns no path")
    index.build_async()
    eq(index.building(), false, "index.build_async: a no-op off Windows")
    return
  end

  -- ------------------------------------------- Windows: lookups + expiry
  --
  -- Everything below patches process-wide state (PATH/PATHEXT, vim.fn.executable
  -- / exepath, vim.uv.hrtime). TESTS/run.lua loads every spec into one shared
  -- Neovim instance, so a raised assertion that skipped the restore would leak
  -- into every later spec instead of just failing this one -- the same lesson
  -- `H.with_patched` documents. The whole body runs in one `pcall` for exactly
  -- that reason: `restore()` below always runs, pass or fail.
  local saved_path, saved_pathext = vim.env.PATH, vim.env.PATHEXT
  local real_executable, real_exepath = vim.fn.executable, vim.fn.exepath
  local real_hrtime = vim.uv.hrtime

  local function restore()
    setenv("PATH", saved_path)
    setenv("PATHEXT", saved_pathext)
    vim.fn.executable, vim.fn.exepath = real_executable, real_exepath
    rawset(vim.uv, "hrtime", real_hrtime)
    executable.clear()
    index.reset()
  end

  local body_ok, body_err = pcall(function()
    setenv("PATH", first .. ";" .. second)
    setenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")
    executable.clear()

    local p0, known0 = index.lookup("alpha")
    eq(known0, false, "index.lookup: no index yet -> unknown, the caller asks vim.fn")
    eq(p0, nil, "index.lookup: ... with no path")

    index.build()
    ok(index.ready(), "index.build: ready afterwards")
    local p1, known1 = index.lookup("ALPHA")
    ok(known1 and under(first, p1), "index.lookup: answers, case-insensitive")
    local p2, known2 = index.lookup("definitely-not-installed")
    ok(known2 and p2 == nil, "index.lookup: a known miss is an answer, not 'unknown'")
    local _, known3 = index.lookup("C:\\tools\\alpha")
    eq(known3, false, "index.lookup: a path is not a $PATH search")

    setenv("PATH", first)
    eq(index.ready(), false, "index.ready: false once $PATH changed")
    local _, known4 = index.lookup("alpha")
    eq(known4, false, "index.lookup: ... and unknown, so vim.fn decides")
    setenv("PATH", first .. ";" .. second)

    index.build()
    local old = index.MAX_AGE_MS
    index.MAX_AGE_MS = -1
    eq(index.ready(), false, "index.ready: false once older than MAX_AGE_MS")
    index.MAX_AGE_MS = old
    ok(index.ready(), "index.ready: true again within the age limit")

    -- --------------------------------- executable.exists / path use the index
    local native_calls = 0
    vim.fn.executable = function(...)
      native_calls = native_calls + 1
      return real_executable(...)
    end
    vim.fn.exepath = function(...)
      native_calls = native_calls + 1
      return real_exepath(...)
    end

    executable.clear()
    index.build()
    eq(executable.exists("alpha"), true, "executable.exists: found through the index")
    eq(
      executable.exists("nowhere-to-be-found"),
      false,
      "executable.exists: a miss through the index"
    )
    local resolved = executable.path("delta")
    ok(under(second, resolved), "executable.path: resolved through the index")
    eq(
      executable.path("nowhere-to-be-found-either"),
      nil,
      "executable.path: a miss through the index"
    )
    eq(native_calls, 0, "executable: a ready index answers without one native lookup")

    -- clear(name) bypasses the index for that name (installed a moment ago).
    local late = "late-arrival"
    vim.fn.writefile({}, first .. "/" .. late .. ".exe")
    executable.clear(late)
    eq(
      executable.exists(late),
      true,
      "executable.clear(name): the next lookup sees a tool the index predates"
    )
    ok(native_calls > 0, "executable.clear(name): ... by asking vim.fn")
    eq(under(first, executable.path(late)), true, "executable.clear(name): and path() agrees")

    -- Without an index, native lookups are added up; at the break-even (60 ms) the
    -- index is built synchronously -- inside a loop that never yields, which is
    -- exactly where a background build could not finish. A controlled clock, not
    -- sleeping: timer granularity on Windows would make the count wobble.
    index.reset()
    executable.clear()
    native_calls = 0
    local now_ns = 0
    rawset(vim.uv, "hrtime", function()
      return now_ns
    end)
    vim.fn.executable = function(...)
      native_calls = native_calls + 1
      now_ns = now_ns + 25 * 1e6 -- every native lookup "takes" 25 ms
      return real_executable(...)
    end
    executable.exists("nowhere-1")
    executable.exists("nowhere-2")
    eq(index.ready(), false, "executable: 50 ms of native lookups do not build an index yet")
    executable.exists("nowhere-3")
    eq(
      index.ready(),
      true,
      "executable: the lookup that reaches the break-even builds it, synchronously"
    )
    local before = native_calls
    executable.exists("nowhere-4")
    executable.exists("nowhere-5")
    eq(native_calls, before, "executable: once built, new names no longer go native")
    rawset(vim.uv, "hrtime", real_hrtime)

    -- warm() builds in the background.
    index.reset()
    executable.clear()
    executable.warm()
    vim.wait(3000, function()
      return index.ready()
    end, 10)
    ok(index.ready(), "executable.warm: builds the index in the background")

    -- A build for a $PATH that changed meanwhile is dropped, not published.
    index.reset()
    index.build_async()
    setenv("PATH", first)
    vim.wait(500, function()
      return not index.building()
    end, 10)
    eq(index.ready(), false, "index.build_async: dropped when $PATH changed while it ran")
  end)

  restore()
  if not body_ok then
    error(body_err, 0)
  end
end
