-- TESTS/fs_json_write_spec.lua -- lib.nvim.fs.json.write: each write stages in its own temp file.

return function(H)
  local ok, eq = H.ok, H.eq
  local uv = vim.uv or vim.loop

  local function read(path)
    local f = io.open(path, "rb")
    if not f then
      return nil
    end
    local text = f:read("*a")
    f:close()
    return text
  end

  ---Names in `dir` ending in `.tmp`.
  local function temps(dir)
    local out, handle = {}, uv.fs_scandir(dir)
    while handle do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if name:sub(-4) == ".tmp" then
        out[#out + 1] = name
      end
    end
    return out
  end

  -- `fs.json` binds `fs.write.to_file` when it loads, so a stubbed writer needs a freshly loaded module.
  local function with_writer(writer, fn)
    local saved_json = package.loaded["lib.nvim.fs.json"]
    H.with_patched(package.loaded, "lib.nvim.fs.write.to_file", writer, function()
      package.loaded["lib.nvim.fs.json"] = nil
      local okfn, err = pcall(fn, require("lib.nvim.fs.json"))
      package.loaded["lib.nvim.fs.json"] = saved_json
      if not okfn then
        error(err, 0)
      end
    end)
  end

  local json = require("lib.nvim.fs.json")

  -- The temp name: next to the target, unique per call, still ending in `<ext>.tmp`.
  local a, b = json.tmp_path("/d/state.json"), json.tmp_path("/d/state.json")
  ok(a ~= b, "tmp_path: two calls give two names")
  ok(
    a:match("^/d/state%.[%d%-]+%.json%.tmp$") ~= nil,
    "tmp_path: same folder, ends in .json.tmp: " .. a
  )
  ok(
    json.tmp_path("/d/state"):match("^/d/state%.[%d%-]+%.tmp$") ~= nil,
    "tmp_path: no extension -> <path>.<id>.tmp"
  )
  ok(
    json.tmp_path("/d.x/.rc"):match("^/d%.x/%.rc%.[%d%-]+%.tmp$") ~= nil,
    "tmp_path: a dot name has no extension"
  )
  ok(
    json.tmp_path("C:\\d.x\\st"):match("^C:\\d%.x\\st%.[%d%-]+%.tmp$") ~= nil,
    "tmp_path: a dot in a folder is no extension"
  )

  -- Two writers interleaved (two Neovim instances on one file): A has staged its bytes, B is half way through its
  -- own, then A renames. With one shared `<path>.tmp` A renamed B's half file into place.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local target = dir .. "/shared.json"
  local real = require("lib.nvim.fs.write.to_file")
  -- Inside a coroutine the writer pauses: A after its whole content, B after half of it.
  local writer = function(path, content)
    if not coroutine.running() then
      return real(path, content)
    end
    if content:find('"who":"B"', 1, true) then
      assert(real(path, content:sub(1, math.floor(#content / 2))))
      coroutine.yield("half")
      return real(path, content)
    end
    local wrote, err = real(path, content)
    coroutine.yield("staged")
    return wrote, err
  end
  with_writer(writer, function(fresh)
    local wa = coroutine.create(function()
      return fresh.write(target, { who = "A", pad = ("a"):rep(200) })
    end)
    local wb = coroutine.create(function()
      return fresh.write(target, { who = "B", pad = ("b"):rep(200) })
    end)
    assert(coroutine.resume(wa)) -- A has staged its whole content
    assert(coroutine.resume(wb)) -- B has written half of its own
    local _, a_ok, a_err = coroutine.resume(wa) -- A renames
    ok(a_ok, "interleaved: A succeeds: " .. tostring(a_err))
    local after_a = fresh.read(target)
    eq(after_a and after_a.who, "A", "interleaved: after A's rename the file is A's whole JSON")
    local _, b_ok, b_err = coroutine.resume(wb) -- B finishes and renames
    ok(b_ok, "interleaved: B succeeds: " .. tostring(b_err))
    local final = fresh.read(target)
    eq(final and final.who, "B", "interleaved: the last writer wins with a whole JSON")
    eq(#temps(dir), 0, "interleaved: no temp file is left")
  end)

  -- A failed rename removes its own temp file, and only that one.
  local fail_dir = vim.fn.tempname()
  vim.fn.mkdir(fail_dir .. "/blocker.json/inner", "p") -- a non-empty folder where the file should go
  local foreign = fail_dir .. "/blocker.other.json.tmp"
  assert(real(foreign, "{}"))
  local wrote, werr = json.write(fail_dir .. "/blocker.json", { v = 1 })
  eq(wrote, false, "rename failure: write reports false")
  ok(
    tostring(werr):find("rename failed", 1, true) ~= nil,
    "rename failure: names the step: " .. tostring(werr)
  )
  ok(
    vim.deep_equal(temps(fail_dir), { "blocker.other.json.tmp" }),
    "rename failure: own temp removed, a foreign one kept"
  )
  ok(read(foreign) ~= nil, "rename failure: the foreign temp file is untouched")

  -- A write that fails after opening (full disk, error on close) removes its partial temp file: a unique name is
  -- never overwritten by a later write, so every such failure would otherwise leave one more file behind.
  local wfail_dir = vim.fn.tempname()
  vim.fn.mkdir(wfail_dir, "p")
  with_writer(function(path, content)
    assert(real(path, content:sub(1, 3)))
    return false, "close failed: disk full"
  end, function(fresh)
    local wf_ok, wf_err = fresh.write(wfail_dir .. "/state.json", { v = 1 })
    eq(wf_ok, false, "write failure: write reports false")
    ok(
      tostring(wf_err):find("write failed: close failed", 1, true) ~= nil,
      "write failure: names the step: " .. tostring(wf_err)
    )
    eq(#temps(wfail_dir), 0, "write failure: the partial temp file is removed")
  end)

  vim.fn.delete(dir, "rf")
  vim.fn.delete(fail_dir, "rf")
  vim.fn.delete(wfail_dir, "rf")
end
