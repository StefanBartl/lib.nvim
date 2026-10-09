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

  local empty = dir .. "/empty.txt"
  local eh = assert(io.open(empty, "wb"))
  eh:close()
  eq(read_bounded(empty, 10), "", "an empty file reads as an empty string")
  eq(read_bounded(empty, 0), "", "an empty file passes a limit of 0")

  content, err = read_bounded(file, -1)
  eq(content, nil, "a negative limit is refused")
  ok(err and err:find("invalid", 1, true), "a negative limit: says why")
  ---@diagnostic disable-next-line: param-type-mismatch
  content = read_bounded(nil, 10)
  eq(content, nil, "a non-string path is refused")

  content, err = read_bounded(dir, 100)
  eq(content, nil, "a directory: nothing read")
  ok(err and err:find("not a regular file", 1, true), "a directory: says why")

  content, err = read_bounded(dir .. "/missing", 100)
  eq(content, nil, "a missing path: nothing read")
  ok(err and err:find("not found", 1, true), "a missing path: says why")

  -- a symlink: followed by default, refused with follow_symlinks = false
  local link = dir .. "/link.txt"
  local made = (vim.uv or vim.loop).fs_symlink(file, link)
  if made then
    eq(read_bounded(link, 100), "a\r\nb\0c", "a symlink is followed by default")
    content, err = read_bounded(link, 100, { follow_symlinks = false })
    eq(content, nil, "follow_symlinks = false: a symlink is refused")
    ok(err and err:find("not a regular file", 1, true), "follow_symlinks = false: says why")
  else
    ok(true, "symlinks cannot be created here")
  end
  eq(
    read_bounded(file, 100, { follow_symlinks = false }),
    "a\r\nb\0c",
    "a plain file passes either way"
  )

  vim.fn.delete(dir, "rf")
end
