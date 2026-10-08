-- TESTS/fs_read_bounded_spec.lua — lib.nvim.fs.read_bounded

return function(H)
  local eq, ok = H.eq, H.ok
  local read_bounded = require("lib.nvim.fs.read_bounded")

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/f.txt"
  local fh = assert(io.open(file, "wb"))
  fh:write("a\r\nb\0c")
  fh:close()

  local content, err = read_bounded(file, 100)
  eq(content, "a\r\nb\0c", "within the limit: read byte-exact")
  eq(err, nil, "within the limit: no error")

  content = read_bounded(file, 6)
  eq(content, "a\r\nb\0c", "exactly max_bytes still passes")

  content, err = read_bounded(file, 5)
  eq(content, nil, "one byte over: nothing read")
  ok(err and err:find("too large", 1, true), "one byte over: says why")

  content, err = read_bounded(dir, 100)
  eq(content, nil, "a directory: nothing read")
  ok(err and err:find("not a regular file", 1, true), "a directory: says why")

  content, err = read_bounded(dir .. "/missing", 100)
  eq(content, nil, "a missing path: nothing read")
  ok(err and err:find("not found", 1, true), "a missing path: says why")

  vim.fn.delete(dir, "rf")
end
