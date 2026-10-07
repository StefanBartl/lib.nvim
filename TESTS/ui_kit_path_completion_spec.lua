-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_path_completion_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_path_completion_spec.lua (the kit exists twice, see ui.nvim's
-- docs/modules.md): `<Tab>` path completion in a directory with a great many
-- entries.
--
-- `getcompletion(frag, "file")` pays a file-system `stat` per match -- about a tenth
-- of a millisecond each -- so a directory of five thousand files froze the editor for
-- half a second at every <Tab>. With more than 300 matches the candidates are built
-- from one directory listing, without a `stat`, sorted and cut to 300. Everything
-- else -- few matches, a pattern, another completion type, a directory that cannot
-- be listed -- is `getcompletion()`'s as before; it is stubbed here, which is what
-- tells the two paths apart.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local api = vim.api
  local uv = vim.uv or vim.loop
  local MAX = 300

  vim.o.showmode = false

  local function touch(path)
    local f = assert(io.open(path, "w"))
    f:write("")
    f:close()
  end

  local function close_floats()
    for _ = 1, 10 do
      local closed = false
      for _, w in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
          pcall(api.nvim_win_close, w, true)
          closed = true
        end
      end
      if not closed then
        return
      end
    end
  end

  --- A directory (forward slashes, long names) with `files` `item_NNN` files and
  --- `dirs` `sub_NNN` subdirectories, a dot file and one more file.
  local function make_dir(files, dirs)
    local d = vim.fn.tempname()
    vim.fn.mkdir(d, "p")
    d = (uv.fs_realpath(d) or d):gsub(string.char(92), "/")
    for i = 0, files - 1 do
      touch(("%s/item_%03d"):format(d, i))
    end
    for i = 0, dirs - 1 do
      vim.fn.mkdir(("%s/sub_%03d"):format(d, i), "p")
    end
    touch(d .. "/.hidden")
    touch(d .. "/other.txt")
    return d
  end

  local getcompletion_calls, stat_calls, shown, shown_col = 0, 0, nil, nil
  local real_getcompletion, real_complete, real_stat =
    vim.fn.getcompletion, vim.fn.complete, uv.fs_stat

  --- <Tab> in a prompt of `completion` type, with `line` typed and the cursor at its end.
  local function press_tab(line, completion)
    getcompletion_calls, stat_calls, shown, shown_col = 0, 0, nil, nil
    local surf = kit.input({ completion = completion or "file" })
    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { line })
    api.nvim_win_set_cursor(surf.winid, { 1, #line })
    vim.fn.maparg("<Tab>", "i", false, true).callback()
    surf:close()
  end

  vim.fn.getcompletion = function()
    getcompletion_calls = getcompletion_calls + 1
    return { "from-getcompletion" }
  end
  vim.fn.complete = function(col, items)
    shown_col, shown = col, items
  end
  uv.fs_stat = function(...)
    stat_calls = stat_calls + 1
    return real_stat(...)
  end

  local dirs_made = {}
  local done, err = pcall(function()
    local dir = make_dir(MAX + 100, 0)
    dirs_made[#dirs_made + 1] = dir

    -- Many files: one listing, no stat, sorted, cut.
    press_tab(dir .. "/item")
    ok(shown ~= nil, "a popup opens")
    eq(#shown, MAX, "cut to the most a menu holds")
    eq(getcompletion_calls, 0, "getcompletion() is not asked")
    eq(stat_calls, 0, "and nothing is stat'ed")
    eq(shown[1], dir .. "/item_000", "sorted, from the start")
    eq(shown[MAX], dir .. "/item_" .. ("%03d"):format(MAX - 1))
    eq(shown_col, 1, "complete() starts where the fragment began")

    -- Few matches, a pattern, another type, a directory that is not there: getcompletion().
    press_tab(dir .. "/item_00")
    eq(getcompletion_calls, 1, "few matches")
    eq(shown[1], "from-getcompletion")
    press_tab(dir .. "/item*")
    eq(getcompletion_calls, 1, "a pattern")
    press_tab(dir .. "/item_{0,1}")
    eq(getcompletion_calls, 1, "a brace pattern")
    press_tab(dir .. "/item", "buffer")
    eq(getcompletion_calls, 1, "a completion type that is no path")
    press_tab(dir .. "/no/such/dir/item")
    eq(getcompletion_calls, 1, "a directory that does not exist")
    press_tab(dir .. "/.")
    eq(getcompletion_calls, 1, "one dot file is few matches")

    -- Directories: marked with a slash, the only ones for completion = "dir".
    local dirs = make_dir(20, MAX + 20)
    dirs_made[#dirs_made + 1] = dirs
    press_tab(dirs .. "/", "dir")
    eq(#shown, MAX)
    eq(getcompletion_calls, 0)
    eq(stat_calls, 0)
    for _, name in ipairs(shown) do
      ok(name:match("^" .. vim.pesc(dirs) .. "/sub_%d+/$") ~= nil, "a directory: " .. name)
    end
    press_tab(dir .. "/", "dir")
    eq(getcompletion_calls, 1, "no directory among all those files")

    -- Sorted the way getcompletion() sorts.
    touch(dir .. "/Item_upper")
    press_tab(dir .. "/item")
    local keys = {}
    for i, name in ipairs(shown) do
      keys[i] = vim.o.fileignorecase and name:lower() or name
    end
    local sorted = vim.deepcopy(keys)
    table.sort(sorted)
    ok(vim.deep_equal(sorted, keys), "the candidates are in order")

    -- 'wildignore' is honoured, as getcompletion() does: names and, with a slash, paths.
    local saved_ignore = vim.o.wildignore
    for i = 0, 9 do
      touch(("%s/item_%03d.o"):format(dir, i))
    end
    local ign_ok, ign_err = pcall(function()
      vim.o.wildignore = "*.o"
      press_tab(dir .. "/item")
      eq(getcompletion_calls, 0, "still the fast path")
      eq(#shown, MAX)
      for _, name in ipairs(shown) do
        ok(name:match("%.o$") == nil, "an ignored file: " .. name)
      end
      vim.o.wildignore = "*/item_00*"
      press_tab(dir .. "/item")
      for _, name in ipairs(shown) do
        ok(name:match("/item_00") == nil, "an ignored path: " .. name)
      end
    end)
    vim.o.wildignore = saved_ignore
    assert(ign_ok, ign_err)
  end)

  vim.fn.getcompletion, vim.fn.complete, uv.fs_stat = real_getcompletion, real_complete, real_stat
  close_floats()
  for _, d in ipairs(dirs_made) do
    vim.fn.delete(d, "rf")
  end
  assert(done, err)
end
