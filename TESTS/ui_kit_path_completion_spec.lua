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
  local real_scandir_next = uv.fs_scandir_next

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
  local function counting_stat(...)
    stat_calls = stat_calls + 1
    return real_stat(...)
  end
  uv.fs_stat = counting_stat

  --- The same listing, but it does not say what an entry is -- what a link, a junction
  --- and a file system without `d_type` do: the code has to `stat` those.
  local function hide_entry_kinds()
    uv.fs_scandir_next = function(handle)
      return (real_scandir_next(handle))
    end
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

    -- A listing that does not say what an entry is (a link, a junction, a file system
    -- without d_type): `stat` is asked for those, but only up to one past the menu, and
    -- not at all when too few entries match to need the list.
    hide_entry_kinds()
    press_tab(dir .. "/item")
    eq(getcompletion_calls, 0, "unknown types: getcompletion() is still not asked")
    ok(stat_calls <= MAX + 1, stat_calls .. " stats for " .. MAX + 100 .. " matches")
    eq(#shown, MAX)
    eq(shown[1], dir .. "/item_000")
    eq(shown[MAX], dir .. "/item_" .. ("%03d"):format(MAX - 1))
    press_tab(dir .. "/item_00")
    eq(getcompletion_calls, 1, "few matches: getcompletion() has them")
    eq(stat_calls, 0, "and nothing was stat'ed on the way")
    press_tab(dir .. "/", "dir")
    eq(getcompletion_calls, 1, "no directory among all those files, types unknown")

    -- A directory of unknown type gets its slash and is what completion = "dir" keeps.
    press_tab(dirs .. "/", "dir")
    eq(#shown, MAX)
    for _, name in ipairs(shown) do
      ok(name:match("^" .. vim.pesc(dirs) .. "/sub_%d+/$") ~= nil, "a directory: " .. name)
    end
    press_tab(dirs .. "/", "file")
    local listed = {}
    for i = 0, 19 do
      listed[#listed + 1] = ("%s/item_%03d"):format(dirs, i)
    end
    listed[#listed + 1] = dirs .. "/other.txt"
    for i = 0, MAX - 22 do
      listed[#listed + 1] = ("%s/sub_%03d/"):format(dirs, i)
    end
    ok(vim.deep_equal(listed, shown), "files, then directories with their slash")

    -- An entry that cannot be stat'ed (a broken link) is taken for a file.
    uv.fs_stat = function()
      stat_calls = stat_calls + 1
    end
    press_tab(dir .. "/item")
    eq(#shown, MAX)
    for _, name in ipairs(shown) do
      ok(name:match("/$") == nil, "a file: " .. name)
    end
    press_tab(dirs .. "/", "dir")
    eq(getcompletion_calls, 1, "no directory among them: getcompletion() has it")
    uv.fs_stat = counting_stat
    uv.fs_scandir_next = real_scandir_next

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

    -- 'wildignore' is not applied: getcompletion() without `filtered` does not apply it
    -- either, so what <Tab> lists must not depend on the directory size.
    local wild = make_dir(MAX + 10, 0)
    dirs_made[#dirs_made + 1] = wild
    touch(wild .. "/aaa.o")
    local saved_wild = vim.o.wildignore
    vim.o.wildignore = "*.o,item_00*"
    local wild_ok, wild_err = pcall(function()
      local expected = vim.tbl_map(function(name)
        return (name:gsub("\\", "/"))
      end, real_getcompletion(wild .. "/", "file"))
      ok(vim.tbl_contains(expected, wild .. "/aaa.o"), "getcompletion() keeps an ignored file")
      press_tab(wild .. "/")
      ok(vim.deep_equal(vim.list_slice(expected, 1, MAX), shown), "the big list matches it")
    end)
    vim.o.wildignore = saved_wild
    assert(wild_ok, wild_err)
  end)

  vim.fn.getcompletion, vim.fn.complete, uv.fs_stat = real_getcompletion, real_complete, real_stat
  uv.fs_scandir_next = real_scandir_next
  close_floats()
  for _, d in ipairs(dirs_made) do
    vim.fn.delete(d, "rf")
  end
  assert(done, err)
end
