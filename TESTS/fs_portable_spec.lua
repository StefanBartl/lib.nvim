-- TESTS/fs_portable_spec.lua — lib.nvim.fs.portable: placeholders on write, resolve on read via a temp copy.

return function(H)
  local eq, ok = H.eq, H.ok
  local portable = require("lib.nvim.fs.portable")
  local ROOT = { path = "E:/repos/ui.nvim", placeholder = "{{ROOT}}" }

  local function put(path, text)
    local fh = assert(io.open(path, "wb"))
    fh:write(text)
    fh:close()
  end

  -- make: forward and backslash spellings, trailing-slash root, boundary
  do
    local text =
      "cd E:/repos/ui.nvim\nedit E:/repos/ui.nvim/lua/a.lua\nedit E:\\repos\\ui.nvim\\b.lua\n"
    eq(
      portable.make(text, { ROOT }),
      "cd {{ROOT}}\nedit {{ROOT}}/lua/a.lua\nedit {{ROOT}}\\b.lua\n",
      "make: slashed root, subpaths and a backslash spelling become the placeholder"
    )
    eq(
      portable.make(
        "edit E:/repos/ui.nvim-backup/x.lua E:/repos/ui.nvim.old/y E:/repos/ui.nvimx",
        { ROOT }
      ),
      "edit E:/repos/ui.nvim-backup/x.lua E:/repos/ui.nvim.old/y E:/repos/ui.nvimx",
      "make: a sibling that merely starts with the root text is left alone"
    )
    eq(
      portable.make("a E:/repos/ui.nvim-backup/x E:/repos/ui.nvim/y", { ROOT }),
      "a E:/repos/ui.nvim-backup/x {{ROOT}}/y",
      "make: the boundary check resumes after a rejected hit"
    )
    eq(
      portable.make(
        "E:/repos/ui.nvim/x",
        { { path = "E:\\repos\\ui.nvim\\", placeholder = "{{R}}" } }
      ),
      "{{R}}/x",
      "make: a root given with backslashes and a trailing separator matches"
    )
    eq(portable.make(text, {}), text, "make: no roots changes nothing")

    -- the root must also START at a path boundary
    local home = { path = "/home/me", placeholder = "{{HOME}}" }
    eq(
      portable.make("a /srv/home/me/x b /home/me/y c=/home/me", { home }),
      "a /srv/home/me/x b {{HOME}}/y c={{HOME}}",
      "make: a root is not replaced in the middle of another path"
    )
    eq(
      portable.resolve("a /srv/C:/x", {}, { remap = { ["C:/x"] = "/y" } }),
      "a /srv/C:/x",
      "remap: not replaced in the middle of another path either"
    )

    -- a root right behind a URL scheme starts at a boundary (oil://, fugitive://, file:///, term://)
    eq(
      portable.make("oil:///home/me/sub/ file:///home/me/b term://~/x//1:sh", { home }),
      "oil://{{HOME}}/sub/ file://{{HOME}}/b term://~/x//1:sh",
      "make: a root behind scheme:// is replaced"
    )
    eq(
      portable.make("fugitive://E:/repos/ui.nvim/.git//abc", { ROOT }),
      "fugitive://{{ROOT}}/.git//abc",
      "make: a drive root behind scheme:// is replaced"
    )
    eq(
      portable.resolve("oil:///old/root/sub/", {}, { remap = { ["/old/root"] = "/new/root" } }),
      "oil:///new/root/sub/",
      "remap: a root behind scheme:// is translated"
    )
    -- the search resumes after the FIRST byte of a rejected hit, not after its end
    eq(
      portable.make("ab_ ab_ ab", { { path = "ab_ ab", placeholder = "P" } }),
      "ab_ P",
      "make: an overlapping hit is found after a rejected one"
    )

    -- the drive letter matches in either case
    eq(
      portable.make("cd e:/repos/ui.nvim/a", { ROOT }),
      "cd {{ROOT}}/a",
      "make: a lower-case drive letter matches"
    )
  end

  -- nested roots: the longer one wins, in any order of the list
  do
    local outer = { path = "/home/me", placeholder = "{{HOME}}" }
    local inner = { path = "/home/me/proj", placeholder = "{{PROJ}}" }
    local text = "/home/me/proj/a /home/me/notes/b"
    eq(
      portable.make(text, { outer, inner }),
      "{{PROJ}}/a {{HOME}}/notes/b",
      "nested roots: longest first"
    )
    eq(
      portable.make(text, { inner, outer }),
      "{{PROJ}}/a {{HOME}}/notes/b",
      "nested roots: list order is irrelevant"
    )
  end

  -- resolve: placeholder to this machine's path, unknown placeholders stay, remap translates prefixes
  do
    local r = { path = "D:\\work\\ui", placeholder = "{{ROOT}}" }
    eq(
      portable.resolve("cd {{ROOT}}\nedit {{ROOT}}/a.lua {{OTHER}}/x", { r }),
      "cd D:/work/ui\nedit D:/work/ui/a.lua {{OTHER}}/x",
      "resolve: placeholder -> forward-slashed path, unknown ones stay"
    )
    eq(
      portable.resolve(
        "edit C:/Users/a/notes/x C:/Users/ab/y",
        { r },
        { remap = { ["C:/Users/a"] = "/home/a" } }
      ),
      "edit /home/a/notes/x C:/Users/ab/y",
      "resolve: remap honours the path boundary"
    )
    eq(
      portable.resolve("{{ROOT}}/a", { { path = "C:/", placeholder = "{{ROOT}}" } }),
      "C:/a",
      "resolve: a root that ends in a slash does not double it"
    )
    eq(
      portable.resolve(portable.make("E:/repos/ui.nvim/a", { ROOT }), { ROOT }),
      "E:/repos/ui.nvim/a",
      "make then resolve round-trips"
    )
  end

  -- bad arguments
  do
    eq(pcall(portable.make, "x", "nope"), false, "make: roots must be a table")
    eq(
      pcall(portable.make, "x", { { path = "", placeholder = "{{R}}" } }),
      false,
      "make: a root needs a path"
    )
    eq(
      pcall(portable.resolve, "x", { { path = "/a" } }),
      false,
      "resolve: a root needs a placeholder"
    )
  end

  -- files: make_file in place, resolve_file via a temp copy, the stored file untouched
  do
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local root = { path = dir, placeholder = "{{ROOT}}" }
    local slash = dir:gsub("\\", "/")
    local file = dir .. "/session.vim"
    local raw = "cd " .. slash .. "\nedit " .. slash .. "/a.lua"
    put(file, raw)

    local made_ok = portable.make_file(file, { root })
    ok(made_ok, "make_file: succeeds")
    local f = assert(io.open(file, "rb"))
    local stored = f:read("a")
    f:close()
    eq(
      stored,
      "cd {{ROOT}}\nedit {{ROOT}}/a.lua",
      "make_file: rewrites in place, byte-exact (no newline added)"
    )

    local src, is_temp, err = portable.resolve_file(file, { root })
    ok(is_temp, "resolve_file: a temporary copy is made when placeholders were resolved")
    eq(err, nil, "resolve_file: no error")
    ok(src ~= file, "resolve_file: the copy is a different path")
    local g = assert(io.open(src, "rb"))
    eq(g:read("a"), raw, "resolve_file: the copy holds this machine's paths")
    g:close()
    local h = assert(io.open(file, "rb"))
    eq(h:read("a"), stored, "resolve_file: the stored file is untouched")
    h:close()
    vim.fn.delete(src)

    -- nothing to resolve: the stored path comes back, no copy
    local plain = dir .. "/plain.txt"
    put(plain, "nothing here")
    local psrc, ptemp = portable.resolve_file(plain, { root })
    eq(psrc, plain, "resolve_file: nothing to resolve returns the stored path")
    eq(ptemp, false, "resolve_file: ... and is_temp is false")

    -- an unreadable file: the path comes back with the error
    local msrc, mtemp, merr = portable.resolve_file(dir .. "/missing.vim", { root })
    eq(msrc, dir .. "/missing.vim", "resolve_file: a missing file returns its path")
    eq(mtemp, false, "resolve_file: ... not temp")
    ok(type(merr) == "string", "resolve_file: ... with the error")
    local mok = portable.make_file(dir .. "/missing.vim", { root })
    eq(mok, false, "make_file: a missing file is an error")

    vim.fn.delete(dir, "rf")
  end
end
