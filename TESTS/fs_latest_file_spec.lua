-- TESTS/fs_latest_file_spec.lua -- lib.nvim.fs.latest_file: the newest (recent) file of some folders.

return function(H)
  local ok = H.ok
  local latest = require("lib.nvim.fs.latest_file")

  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local now = 1800000000
  local a, b = vim.fn.tempname() .. "_shots_a", vim.fn.tempname() .. "_shots_b"
  vim.fn.mkdir(a, "p")
  vim.fn.mkdir(b, "p")
  local function make(dir, name, age)
    local p = dir .. "/" .. name
    vim.fn.writefile({ "x" }, p)
    vim.uv.fs_utime(p, now - age, now - age)
    return vim.fs.normalize(p)
  end

  make(a, "old.png", 1000)
  local fresh = make(a, "fresh.PNG", 30)
  make(a, "newer-but-text.txt", 5)
  make(b, "other.jpg", 100)
  vim.fn.mkdir(a .. "/dir.png", "p")

  local found, err = latest.find({ a, b }, { now = now, max_age_s = 300 })
  ok(found, "a recent image is found: " .. tostring(err))
  eq(
    found.path,
    fresh,
    "the newest image of all folders wins; extension case and non-images do not matter"
  )
  ok(math.abs(found.age_s - 30) < 1, "the age is reported")

  found, err = latest.find({ a }, { now = now, max_age_s = 10 })
  ok(
    found == nil and err:find("30 s old", 1, true),
    "a too old file is refused, not guessed: " .. tostring(err)
  )
  eq(
    select(3, latest.find({ a }, { now = now, max_age_s = 10 })).path,
    fresh,
    "and handed back so the caller can ask"
  )

  found = latest.find({ a }, { now = now })
  eq(found.path, fresh, "without max_age_s there is no age limit")

  found = latest.find({ a }, { now = now, exts = { "txt" } })
  eq(found.path, vim.fs.normalize(a .. "/newer-but-text.txt"), "exts selects the file types")

  found, err = latest.find({ a .. "_missing" }, { now = now })
  ok(found == nil and err:find("no matching file", 1, true), "a missing folder is an empty result")
  found, err = latest.find({}, {})
  ok(found == nil and err == "no folder given", "no folder given")

  vim.fn.delete(a, "rf")
  vim.fn.delete(b, "rf")
end
