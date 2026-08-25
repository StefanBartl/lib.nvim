-- TESTS/normkey_spec.lua — lib.nvim.fs.normkey
--
-- The contract is one sentence: two spellings of the same path produce the
-- same key. The interesting half is the one that used to break it — a path
-- that does not exist *yet*. `uv.fs_realpath` fails there, and the old
-- fallback returned the input verbatim, so on Windows a `$TEMP` in 8.3 form
-- keyed as `C:/Users/STEFAN~1/...` before `mkdir` and
-- `C:/Users/StefanBartl/...` after it. A key that changes when the directory
-- is created is not a key.

return function(H)
  local eq, ok = H.eq, H.ok

  local normkey = require("lib.nvim.fs.normkey")
  local uv = vim.uv or vim.loop

  -- --------------------------------------------------------------- surface

  eq(type(normkey), "function", "normkey: module is a function")
  eq(normkey(""), "", "normkey: empty string in, empty string out")
  eq(normkey(nil), "", "normkey: non-string in, empty string out")

  -- ---------------------------------------------------------- spelling only

  local cwd = vim.fn.getcwd()
  local key = normkey(cwd)

  ok(not key:find("\\", 1, true), "normkey: no backslash survives")
  eq(normkey(cwd .. "/"), key, "normkey: a trailing separator does not change the key")
  eq(normkey(cwd .. "//lua"), key .. "/lua", "normkey: duplicate separators collapse")

  if vim.fn.has("win32") == 1 then
    eq(key:sub(1, 1), key:sub(1, 1):upper(), "normkey: the drive letter is uppercased")
    local backslashed = (cwd:gsub("/", string.char(92)))
    eq(normkey(backslashed), key, "normkey: backslash input keys the same")
    eq(normkey("C:/"), "C:/", "normkey: a bare drive root stays the root")
  end

  -- UNC must survive whole: the guard exists because collapsing "//" would
  -- turn `//server/share` into `/server/share`, i.e. a different machine.
  local unc = normkey([[\\SERVER\Share\proj]], { realpath = false })
  eq(unc, "//SERVER/Share/proj", "normkey: UNC prefix is not collapsed (realpath=false)")
  eq(
    normkey([[\\SERVER\Share\nope\deeper]]),
    "//SERVER/Share/nope/deeper",
    "normkey: an unresolvable UNC path keeps its prefix"
  )

  -- --------------------------------------------- stability across creation

  -- The regression this module was fixed for. Asserted on every platform:
  -- where the OS hands back one spelling anyway the two keys are trivially
  -- equal, and where it hands back two (Windows 8.3, macOS /var) the test
  -- only passes because the ancestor walk resolved the prefix.
  local base = vim.fn.tempname()
  ok(uv.fs_stat(base) == nil, "normkey: the probe path does not exist yet")

  local before = normkey(base)
  vim.fn.mkdir(base .. "/child", "p")
  local after = normkey(base)

  eq(before, after, "normkey: the key does not change when the path is created")
  eq(
    normkey(base .. "/child"),
    after .. "/child",
    "normkey: a resolved child extends the resolved parent"
  )

  -- Several segments deep and none of them on disk: everything below the
  -- deepest existing ancestor is carried over verbatim, in order.
  eq(
    normkey(base .. "/child/a/b/c.txt"),
    after .. "/child/a/b/c.txt",
    "normkey: an unresolvable tail is re-appended in order"
  )

  -- The canonical spelling keys to itself — the walk must not double-resolve.
  local canonical = uv.fs_realpath(base)
  if canonical then
    eq(normkey(canonical), after, "normkey: the canonical spelling is already the key")
  end

  -- ------------------------------------------------------------- fallbacks

  -- Nothing along the path resolves: the input is kept, normalized. Q: is
  -- chosen because a mapped drive that high is vanishingly rare; if this ever
  -- fails on a host that has one, that is the assertion working.
  if vim.fn.has("win32") == 1 and uv.fs_stat("Q:/") == nil then
    eq(
      normkey("Q:/nope/deeper/still"),
      "Q:/nope/deeper/still",
      "normkey: an entirely unresolvable path falls back to its spelling"
    )
  end

  -- realpath=false must not touch the filesystem at all, so a non-existent
  -- path comes back exactly as spelled.
  eq(
    normkey("/no/such/dir/at/all", { realpath = false }),
    "/no/such/dir/at/all",
    "normkey: realpath=false answers on spelling alone"
  )

  local home = (uv.os_homedir and uv.os_homedir()) or os.getenv("HOME")
  if home then
    eq(
      normkey("~", { realpath = false }),
      normkey(home, { realpath = false }),
      "normkey: ~ expands"
    )
  end

  vim.fn.delete(base, "rf")
end
