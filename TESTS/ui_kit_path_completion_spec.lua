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
-- half a second at every <Tab>. With more than 300 candidates (entries that start
-- with the fragment, the files among them for completion = "dir") the list is built
-- from one directory listing, without a `stat`, sorted and cut to 300; for "dir" it is
-- the whole answer, however few directories there are among the files. Everything
-- else -- few candidates, a pattern, another completion type, a directory that cannot
-- be listed -- is `getcompletion()`'s as before; it is stubbed here, which is what
-- tells the two paths apart.
--
-- The list has to be the one `getcompletion()` would make, so a few cases compare it
-- with the real function (taken before the stub): which entries match and in which
-- order they come under 'fileignorecase' and 'wildignorecase', and for non-ASCII names.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local api = vim.api
  local uv = vim.uv or vim.loop
  local MAX = 300

  vim.o.showmode = false

  local function touch(path)
    -- Not `io.open`: on Windows LuaJIT's takes the ANSI code page, which turns a file
    -- name with a non-ASCII character into another name. "S": no fsync, a few hundred
    -- files add up.
    assert(vim.fn.writefile({}, path, "S") == 0, "could not create " .. path)
  end

  --- `eq` for two lists: names the first position they differ at.
  local function same(actual, expected, label)
    for i = 1, math.max(#actual, #expected) do
      if actual[i] ~= expected[i] then
        error(
          ("FAIL %s: first difference at %d: got %s, expected %s"):format(
            label,
            i,
            vim.inspect(actual[i]),
            vim.inspect(expected[i])
          ),
          2
        )
      end
    end
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

  --- An empty directory (forward slashes, long names).
  local function new_dir()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d, "p")
    return (uv.fs_realpath(d) or d):gsub(string.char(92), "/")
  end

  --- A directory with `files` `item_NNN` files and `dirs` `sub_NNN` subdirectories, a
  --- dot file and one more file.
  local function make_dir(files, dirs)
    local d = new_dir()
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
  local real_scandir, real_scandir_next = uv.fs_scandir, uv.fs_scandir_next

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

  --- What `getcompletion()` itself lists for `frag`: slashes forward, cut to what a
  --- menu holds.
  local function real_list(frag)
    local names = vim.tbl_map(function(name)
      return (name:gsub("\\", "/"))
    end, real_getcompletion(frag, "file"))
    return vim.list_slice(names, 1, MAX)
  end

  --- Run `fn` with 'fileignorecase' and 'wildignorecase' set, whatever happens in it.
  local function with_case_options(fic, wic, fn)
    local saved_fic, saved_wic = vim.o.fileignorecase, vim.o.wildignorecase
    vim.o.fileignorecase, vim.o.wildignorecase = fic, wic
    local fn_ok, fn_err = pcall(fn)
    vim.o.fileignorecase, vim.o.wildignorecase = saved_fic, saved_wic
    assert(fn_ok, fn_err)
  end

  --- <Tab> on `frag`, under every combination of the case options, has to give what the
  --- real getcompletion() gives: its list cut to what a menu holds when it has more than
  --- that (and then it is not asked), getcompletion() itself otherwise. With
  --- `via_getcompletion` it is getcompletion() that has to answer however long its list
  --- is -- names the big list cannot order the way it does.
  local function check_like_getcompletion(frag, label, via_getcompletion)
    for _, case in ipairs({ { true, false }, { false, false }, { false, true }, { true, true } }) do
      local where = ("%s with 'fileignorecase' %s, 'wildignorecase' %s"):format(
        label,
        tostring(case[1]),
        tostring(case[2])
      )
      with_case_options(case[1], case[2], function()
        local full = vim.tbl_map(function(name)
          return (name:gsub("\\", "/"))
        end, real_getcompletion(frag, "file"))
        press_tab(frag)
        if via_getcompletion or #full <= MAX then
          eq(getcompletion_calls, 1, where .. ": getcompletion() answers")
        else
          eq(getcompletion_calls, 0, where .. ": the big list answers")
          same(shown, vim.list_slice(full, 1, MAX), where)
        end
      end)
    end
  end

  --- Whether the directory lists each of `names` as it was created (a file system that
  --- normalizes Unicode -- HFS+ -- does not, and the spec has nothing to say there).
  local function listed_verbatim(d, names)
    local at = {}
    local handle = real_scandir(d)
    while handle do
      local entry = real_scandir_next(handle)
      if not entry then
        break
      end
      at[entry] = true
    end
    for _, name in ipairs(names) do
      if not at[name] then
        return false
      end
    end
    return true
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
    eq(getcompletion_calls, 0, "all those files and no directory: the listing has the answer")
    eq(shown, nil, "an empty list opens no popup")

    -- The files count among the candidates for "dir", and the listing is the whole answer
    -- however few directories hide among them.
    local few = make_dir(MAX + 100, 3)
    dirs_made[#dirs_made + 1] = few
    press_tab(few .. "/", "dir")
    eq(getcompletion_calls, 0, "three directories among all those files: the listing has them")
    eq(stat_calls, 0, "and nothing is stat'ed")
    ok(
      vim.deep_equal({ few .. "/sub_000/", few .. "/sub_001/", few .. "/sub_002/" }, shown),
      "the three directories"
    )
    local edge = make_dir(MAX - 2, 1) -- MAX - 2 items, one directory and other.txt: MAX
    dirs_made[#dirs_made + 1] = edge
    press_tab(edge .. "/", "dir")
    eq(getcompletion_calls, 1, "exactly MAX candidates are getcompletion()'s")
    local over = make_dir(MAX - 1, 1) -- one candidate more
    dirs_made[#dirs_made + 1] = over
    press_tab(over .. "/", "dir")
    eq(getcompletion_calls, 0, "one more is the first list built from the listing")
    ok(vim.deep_equal({ over .. "/sub_000/" }, shown), "its one directory")

    -- A listing that does not say what an entry is (a link, a junction, a file system
    -- without d_type): `stat` is asked for those, but only until the menu is full, and
    -- not at all when too few entries match to need the list.
    hide_entry_kinds()
    press_tab(dir .. "/item")
    eq(getcompletion_calls, 0, "unknown types: getcompletion() is still not asked")
    ok(stat_calls <= MAX, stat_calls .. " stats for " .. MAX + 100 .. " matches")
    eq(#shown, MAX)
    eq(shown[1], dir .. "/item_000")
    eq(shown[MAX], dir .. "/item_" .. ("%03d"):format(MAX - 1))
    press_tab(dir .. "/item_00")
    eq(getcompletion_calls, 1, "few matches: getcompletion() has them")
    eq(stat_calls, 0, "and nothing was stat'ed on the way")
    press_tab(dir .. "/", "dir")
    eq(getcompletion_calls, 0, "no directory among all those files, types unknown: whole answer")
    ok(stat_calls <= MAX + 101, "each of the entries stat'ed once: " .. stat_calls)
    eq(shown, nil, "and no popup for it")

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

    -- An entry that cannot be stat'ed (a broken link) is left out, as getcompletion()
    -- leaves it: here the first ten items.
    uv.fs_stat = function(path)
      stat_calls = stat_calls + 1
      if path:match("/item_00%d$") then
        return nil
      end
      return real_stat(path)
    end
    press_tab(dir .. "/item")
    eq(getcompletion_calls, 0, "the list is the answer")
    eq(#shown, MAX, "the broken ones do not fill the menu")
    eq(shown[1], dir .. "/item_010")
    eq(shown[MAX], dir .. "/item_309")
    local short = make_dir(MAX + 10, 0)
    dirs_made[#dirs_made + 1] = short
    press_tab(short .. "/item")
    eq(getcompletion_calls, 0, "every candidate has been looked at: the list is whole")
    eq(#shown, MAX)
    eq(shown[1], short .. "/item_010")
    eq(shown[MAX], short .. "/item_309")
    -- Nothing at all can be stat'ed: nothing to show, and nothing to ask getcompletion().
    uv.fs_stat = function()
      stat_calls = stat_calls + 1
    end
    press_tab(dir .. "/item")
    eq(getcompletion_calls, 0, "nothing to show is an answer too")
    eq(shown, nil, "and no popup opens for it")
    press_tab(dirs .. "/", "dir")
    eq(getcompletion_calls, 0, "no directory among them")
    eq(shown, nil)
    uv.fs_stat = counting_stat

    -- Every entry of unknown type stat'ed once, and getcompletion() not asked afterwards:
    -- links to files in a directory of two directories.
    local links = make_dir(2 * MAX + 100, 2)
    dirs_made[#dirs_made + 1] = links
    press_tab(links .. "/", "dir")
    eq(getcompletion_calls, 0, "the walk's list is the answer")
    ok(stat_calls <= 2 * MAX + 103, stat_calls .. " stats for " .. 2 * MAX + 103 .. " candidates")
    ok(vim.deep_equal({ links .. "/sub_000/", links .. "/sub_001/" }, shown), "its two directories")
    uv.fs_scandir_next = real_scandir_next

    -- A real link that leads nowhere (a junction on Windows, where a plain symlink needs a
    -- privilege): listed by neither getcompletion() nor the big list. Skipped where the
    -- system lets this spec create none.
    local dangling = make_dir(MAX + 20, 0)
    dirs_made[#dirs_made + 1] = dangling
    local made = 0
    for i = 1, 3 do
      local link = ("%s/brk%03d"):format(dangling, i)
      local target = link .. ".target"
      vim.fn.mkdir(target, "p")
      local linked = uv.fs_symlink(target, link, { dir = true, junction = true })
      vim.fn.delete(target, "d")
      if linked and real_stat(link) == nil then
        made = made + 1
      end
    end
    if made > 0 then
      local expected = real_list(dangling .. "/")
      eq(#expected, MAX, "broken links: more than a menu holds, so the big list runs")
      press_tab(dangling .. "/")
      eq(getcompletion_calls, 0, "broken links: the big list, not getcompletion()")
      same(shown, expected, "broken links")
    end

    -- The same entries in the same order as the real getcompletion(), whatever
    -- 'fileignorecase' and 'wildignorecase' say. The names tell the cases apart and
    -- include the characters that sort between the capitals and the small letters
    -- (`[ ] ^ _` and the backtick); the mixed-case ones all fall among the first MAX.
    local mixed = make_dir(MAX + 10, 0)
    dirs_made[#dirs_made + 1] = mixed
    for _, name in ipairs({
      "itemA",
      "itemb",
      "item[x",
      "item]x",
      "item^x",
      "item`x",
      "Item_000x",
      "ITEM_001y",
    }) do
      touch(mixed .. "/" .. name)
    end
    vim.fn.mkdir(mixed .. "/Item_000Dir", "p")
    for _, case in ipairs({ { true, false }, { false, false }, { false, true }, { true, true } }) do
      local label = ("'fileignorecase' %s, 'wildignorecase' %s"):format(
        tostring(case[1]),
        tostring(case[2])
      )
      with_case_options(case[1], case[2], function()
        local expected = real_list(mixed .. "/item")
        eq(#expected, MAX, label .. ": more than a menu holds, so the big list runs")
        press_tab(mixed .. "/item")
        eq(getcompletion_calls, 0, label .. ": the big list, not getcompletion()")
        same(shown, expected, label)
      end)
    end

    -- Non-ASCII names: `string.upper` folds ASCII only, which would put an a-umlaut
    -- behind a capital U-umlaut where Neovim (upper-casing the whole character) has it
    -- ahead. The bulk is Cyrillic so that it sorts behind the Latin-1 names and they
    -- stay in the first MAX.
    local wide = new_dir()
    dirs_made[#dirs_made + 1] = wide
    local bulk = "a" .. vim.fn.nr2char(0x400)
    for i = 0, MAX + 9 do
      touch(("%s/%s%03d"):format(wide, bulk, i))
    end
    for _, name in ipairs({
      "ae",
      "aF",
      "a" .. vim.fn.nr2char(0xE4),
      "a" .. vim.fn.nr2char(0xC9),
      "a" .. vim.fn.nr2char(0xCA),
      "a" .. vim.fn.nr2char(0xF6),
      "a" .. vim.fn.nr2char(0xDC),
    }) do
      touch(wide .. "/" .. name)
    end
    with_case_options(true, false, function()
      local expected = real_list(wide .. "/a")
      eq(#expected, MAX, "non-ASCII: more than a menu holds, so the big list runs")
      press_tab(wide .. "/a")
      eq(getcompletion_calls, 0, "non-ASCII: the big list, not getcompletion()")
      same(shown, expected, "non-ASCII names")
    end)

    -- Names that fold to one key (Zebra / zebra can only exist side by side on a file
    -- system that tells the cases apart, so the listing is made up): ordered by
    -- spelling, not by the order the listing gives them.
    local names = { "Zebra", "zebra", "ZEBRA" }
    for i = 0, MAX do
      names[#names + 1] = ("zz_%03d"):format(i)
    end
    local function made_up(order)
      local at = 0
      uv.fs_scandir = function()
        at = 0
        return {}
      end
      uv.fs_scandir_next = function()
        at = at + 1
        local name = names[order(at)]
        return name, name and "file"
      end
      press_tab("fake/")
      uv.fs_scandir, uv.fs_scandir_next = real_scandir, real_scandir_next
      return shown
    end
    with_case_options(true, false, function()
      local forward = made_up(function(i)
        return i
      end)
      local backward = made_up(function(i)
        return #names + 1 - i
      end)
      same(vim.list_slice(forward, 1, 3), { "fake/ZEBRA", "fake/Zebra", "fake/zebra" }, "tie order")
      same(backward, forward, "the order of the listing does not show")
    end)

    -- Where a non-ASCII character is involved Neovim's own folding decides what matches:
    -- toupper() turns U+0131 (dotless i) into "I", which Neovim's folding does not, and
    -- leaves the Kelvin sign (U+212A) alone, which Neovim folds to "k".
    local folding = new_dir()
    dirs_made[#dirs_made + 1] = folding
    local dotless, kelvin = vim.fn.nr2char(0x131), vim.fn.nr2char(0x212A)
    for i = 0, MAX do
      touch(("%s/item%sx%03d"):format(folding, dotless, i))
      touch(("%s/item%sx%03d"):format(folding, kelvin, i))
    end
    touch(folding .. "/itemIa")
    touch(folding .. "/itemia")
    for _, frag in ipairs({
      "itemI",
      "itemi",
      "item" .. dotless,
      "itemk",
      "itemK",
      "item" .. kelvin,
    }) do
      check_like_getcompletion(folding .. "/" .. frag, vim.inspect(frag))
    end
    with_case_options(true, true, function()
      ok(
        #real_getcompletion(folding .. "/item" .. dotless, "file") > MAX,
        "dotless i family is long"
      )
    end)

    -- "U" is no prefix of "U" + U+0308 (an umlaut written as two characters, as macOS
    -- writes them): getcompletion() lists the four plain names, the bytes would list 305.
    local marked = new_dir()
    dirs_made[#dirs_made + 1] = marked
    local marked_names = { "Ua", "Ub", "Uber", "Ubz" }
    for i = 0, MAX do
      marked_names[#marked_names + 1] = ("U%sz%03d"):format(vim.fn.nr2char(0x308), i)
    end
    for _, name in ipairs(marked_names) do
      touch(marked .. "/" .. name)
    end
    if listed_verbatim(marked, marked_names) then
      check_like_getcompletion(marked .. "/U", "U")
      check_like_getcompletion(marked .. "/u", "u")
    end

    -- pathcmp() steps over a combining mark and compares the base characters only, so
    -- "Abe" + U+0308 + "y" sorts between "Abex" and "Abez"; ordered by bytes (CC 88 is
    -- above every ASCII letter) it would come behind "Abez". No two names share a key
    -- once the mark is skipped: getcompletion() leaves such ties to an unstable qsort.
    local ordered = new_dir()
    dirs_made[#dirs_made + 1] = ordered
    local ordered_names = { "Abex", "Abe\204\136y", "Abez" }
    for i = 0, MAX do
      ordered_names[#ordered_names + 1] = ("Abz%03d"):format(i)
    end
    for _, name in ipairs(ordered_names) do
      touch(ordered .. "/" .. name)
    end
    if listed_verbatim(ordered, ordered_names) then
      with_case_options(true, false, function()
        ok(#real_getcompletion(ordered .. "/Ab", "file") > MAX, "more than a menu holds")
      end)
      check_like_getcompletion(ordered .. "/Ab", "Ab")
      check_like_getcompletion(ordered .. "/Abz", "Abz")
      press_tab(ordered .. "/Ab")
      same(
        vim.list_slice(shown, 1, 3),
        { ordered .. "/Abex", ordered .. "/Abe\204\136y", ordered .. "/Abez" },
        "between Abex and Abez, not behind Abez"
      )
    end

    -- One name written the macOS way (a letter and its accent as two characters) used to
    -- send the whole directory back to getcompletion(): 0.8 s at five thousand names, after
    -- the walk had been paid for. Its place is the one of "item_005x", between item_005 and
    -- item_006; by its bytes it would come behind item_009.
    local single = new_dir()
    dirs_made[#dirs_made + 1] = single
    local single_mark = "item_00\204\1815x" -- U+0301 is CC 81
    local single_names = { single_mark }
    for i = 0, MAX + 9 do
      single_names[#single_names + 1] = ("item_%03d"):format(i)
    end
    for _, name in ipairs(single_names) do
      touch(single .. "/" .. name)
    end
    if listed_verbatim(single, single_names) then
      check_like_getcompletion(single .. "/item_", "item_")
      press_tab(single .. "/item_")
      eq(getcompletion_calls, 0, "one marked name: the big list answers")
      eq(shown[7], single .. "/" .. single_mark, "after item_005")
    end

    -- What the question for combining marks costs is two `vim.fn` calls: strchars() asks, and
    -- split() takes a name apart. Counting them tells whether a name was asked about, or taken
    -- apart, that did not have to be -- which no result shows: a name without a mark comes out
    -- of the walk with the key it went in with. Only the calls whose text holds a byte that
    -- `pattern` matches are counted (the prompt itself asks others).
    local function press_tab_counting(line, pattern)
      local real_split, real_strchars = vim.fn.split, vim.fn.strchars
      local splits, asked = 0, 0
      vim.fn.split = function(s, ...)
        if type(s) == "string" and s:find(pattern) then
          splits = splits + 1
        end
        return real_split(s, ...)
      end
      vim.fn.strchars = function(s, ...)
        if type(s) == "string" and s:find(pattern) then
          asked = asked + 1
        end
        return real_strchars(s, ...)
      end
      local counted, counted_err = pcall(press_tab, line)
      vim.fn.split, vim.fn.strchars = real_split, real_strchars
      assert(counted, counted_err)
      return splits, asked
    end

    -- More Cyrillic names than a menu holds (every one has a byte from CC on, so every one is a
    -- candidate for a combining mark). Without a mark in any of them one pair of strchars() for
    -- the whole directory says so and no name is taken apart: asked per name, or not asked at
    -- all, every <Tab> would pay a split() per name (20 us each) for keys that come out as they
    -- went in. With one name written the macOS way among them, only that name is taken apart
    -- (all of them were, 140 ms per <Tab> instead of 35 at five thousand names), and it still
    -- sorts by its base characters.
    local cyrillic = "\208\186\208\184\209\128_" -- U+43A U+438 U+440
    local cyrillic_marked = cyrillic .. "00\204\1815x" -- U+0301 is CC 81, after kir_005
    for _, with_mark in ipairs({ false, true }) do
      local crowded = new_dir()
      dirs_made[#dirs_made + 1] = crowded
      local crowded_names = {}
      for i = 0, MAX + 9 do
        crowded_names[#crowded_names + 1] = ("%s%03d"):format(cyrillic, i)
      end
      if with_mark then
        crowded_names[#crowded_names + 1] = cyrillic_marked
      end
      for _, name in ipairs(crowded_names) do
        touch(crowded .. "/" .. name)
      end
      if listed_verbatim(crowded, crowded_names) then
        for _, case in ipairs({ { true, false }, { false, false }, { false, true }, { true, true } }) do
          local where = ("%s with 'fileignorecase' %s, 'wildignorecase' %s"):format(
            with_mark and "one marked name" or "no marked name",
            tostring(case[1]),
            tostring(case[2])
          )
          with_case_options(case[1], case[2], function()
            local splits, asked = press_tab_counting(crowded .. "/" .. cyrillic, "[\208\209]")
            eq(getcompletion_calls, 0, where .. ": the big list answers")
            if with_mark then
              eq(splits, 1, where .. ": the marked name alone was taken apart")
              eq(shown[7], crowded .. "/" .. cyrillic_marked, where .. ": after kir_005")
            else
              eq(#shown, MAX, where)
              eq(splits, 0, where .. ": no name was taken apart")
              ok(asked <= 2, where .. ": " .. asked .. " questions for the whole directory")
            end
          end)
        end
        if with_mark then
          check_like_getcompletion(crowded .. "/" .. cyrillic, "kir_")
        end
      end
    end

    -- In what pathcmp() compares, "<dir>/" is followed by U+0301 and "a_first", and the mark
    -- joins the "/" before it: the name sorts as "a_first" and comes first. Ordered by its own
    -- bytes (CC 81 is above every ASCII letter) it went behind everything else, and the cut to
    -- a menu dropped it: three names of the first 300 were missing.
    local lead_mark = "\204\129" -- U+0301
    local lead = new_dir()
    dirs_made[#dirs_made + 1] = lead
    local lead_names = { lead_mark .. "a_first", lead_mark .. "item_100x", lead_mark .. "m_first" }
    for i = 0, MAX + 19 do
      lead_names[#lead_names + 1] = ("item_%03d"):format(i)
    end
    for _, name in ipairs(lead_names) do
      touch(lead .. "/" .. name)
    end
    if listed_verbatim(lead, lead_names) then
      with_case_options(true, false, function()
        local expected = real_list(lead .. "/")
        eq(#expected, MAX, "a mark behind the separator: more than a menu holds")
        eq(expected[1], lead .. "/" .. lead_mark .. "a_first", "getcompletion() starts with it")
        ok(vim.tbl_contains(expected, lead .. "/" .. lead_mark .. "item_100x"), "and has this one")
        ok(
          not vim.tbl_contains(expected, lead .. "/" .. lead_mark .. "m_first"),
          "but not the last"
        )
      end)
      check_like_getcompletion(lead .. "/", "a mark behind the separator")
      press_tab(lead .. "/")
      eq(getcompletion_calls, 0, "a mark behind the separator: the big list answers")
      eq(shown[1], lead .. "/" .. lead_mark .. "a_first")
    end

    -- Without a directory part nothing stands before the name: the mark is the first code point
    -- of the string pathcmp() compares and sorts as U+0301 -- behind every other name here, all
    -- of which begin with U+0200 (bytes C8 80, below CC, so none of them is a candidate for a
    -- mark). The separator is put in front of a name only where the path has a directory part:
    -- with it the mark would be dropped and the name would come first.
    local own = new_dir()
    dirs_made[#dirs_made + 1] = own
    local own_names = { lead_mark .. "a_first" }
    for i = 0, MAX + 9 do
      own_names[#own_names + 1] = ("\200\128%03d"):format(i) -- U+0200
    end
    for _, name in ipairs(own_names) do
      touch(own .. "/" .. name)
    end
    if listed_verbatim(own, own_names) then
      local saved_cwd = vim.fn.getcwd()
      vim.cmd("cd " .. vim.fn.fnameescape(own))
      local own_ok, own_err = pcall(function()
        with_case_options(true, false, function()
          local expected = real_list("")
          eq(#expected, MAX, "working directory: more than a menu holds")
          ok(not vim.tbl_contains(expected, lead_mark .. "a_first"), "getcompletion() puts it last")
        end)
        for _, case in ipairs({ { true, false }, { false, false }, { false, true }, { true, true } }) do
          with_case_options(case[1], case[2], function()
            local expected = real_list("")
            press_tab("")
            eq(getcompletion_calls, 0, "working directory: the big list answers")
            same(shown, expected, "working directory")
          end)
        end
      end)
      vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
      assert(own_ok, own_err)
    end

    -- A base character with combining marks after it, in the scripts that write them. Every
    -- second name carries the marks, the rest do not, and each has its own number: no two
    -- share a key once the marks are skipped. By bytes all the plain names would come before
    -- all the marked ones; getcompletion() interleaves them by number. In such a script
    -- nearly every name carries a mark, so the list has to cope with that.
    for _, script in ipairs({
      { name = "Thai", base = 0x0E01, marks = { 0x0E34, 0x0E48 } },
      { name = "Devanagari", base = 0x0939, marks = { 0x0902 } },
      { name = "Arabic", base = 0x0628, marks = { 0x0651, 0x064E } },
    }) do
      local base, marks = vim.fn.nr2char(script.base), ""
      for _, mark in ipairs(script.marks) do
        marks = marks .. vim.fn.nr2char(mark)
      end
      local scripted = new_dir()
      dirs_made[#dirs_made + 1] = scripted
      local scripted_names = {}
      for i = 0, MAX + 9 do
        scripted_names[#scripted_names + 1] = ("%s%s%03d"):format(
          base,
          i % 2 == 1 and marks or "",
          i
        )
      end
      for _, name in ipairs(scripted_names) do
        touch(scripted .. "/" .. name)
      end
      if listed_verbatim(scripted, scripted_names) then
        check_like_getcompletion(scripted .. "/", script.name)
      end
    end

    -- Characters of more than two code points: a flag is two regional indicators, a family
    -- is three people joined by U+200D, a syllable is written as its jamo. pathcmp() reads
    -- the first code point of each and no more, so two flags that begin alike (DE, DK) or
    -- two families that begin with the same person are interleaved by the number behind.
    local function chars(...)
      local out = {}
      for _, cp in ipairs({ ... }) do
        out[#out + 1] = vim.fn.nr2char(cp)
      end
      return table.concat(out)
    end
    local clusters = {
      chars(0x1F1E9, 0x1F1EA), -- DE
      chars(0x1F1E9, 0x1F1F0), -- DK
      chars(0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467), -- man, woman, girl
      chars(0x1F468, 0x200D, 0x1F467), -- man, girl
      chars(0x1112, 0x1161, 0x11AB), -- a syllable as lead, vowel and tail
      chars(0x1112, 0x1161), -- ... without the tail
    }
    local grouped = new_dir()
    dirs_made[#dirs_made + 1] = grouped
    local grouped_names = {}
    for i = 0, MAX + 9 do
      grouped_names[#grouped_names + 1] = ("g_%s%03d"):format(clusters[i % #clusters + 1], i)
    end
    for _, name in ipairs(grouped_names) do
      touch(grouped .. "/" .. name)
    end
    if listed_verbatim(grouped, grouped_names) then
      check_like_getcompletion(grouped .. "/g_", "g_")
    end

    -- A line that is not valid UTF-8 (a path pasted from a Latin-1 file) can end in the
    -- middle of a character: "item_" and a lone lead byte C3 is, byte by byte, the start of
    -- every "item_" and an a-umlaut, where getcompletion() lists none. Where the bytes
    -- decide -- no case folding, so not on Windows -- the big list used to answer with 300
    -- names that do not match. The same characters whole are still the big list's.
    local characters = { "\195\164", "\226\132\170", "\240\159\152\128" } -- U+E4, U+212A, U+1F600
    local halves = new_dir()
    dirs_made[#dirs_made + 1] = halves
    local halves_names = {}
    for i = 0, MAX do
      for _, character in ipairs(characters) do
        halves_names[#halves_names + 1] = ("item_%s%03d"):format(character, i)
      end
    end
    for _, name in ipairs(halves_names) do
      touch(halves .. "/" .. name)
    end
    if listed_verbatim(halves, halves_names) then
      for _, frag in ipairs({ "item_\195", "item_\226\132", "item_\240\159", "item_\240\159\152" }) do
        check_like_getcompletion(halves .. "/" .. frag, vim.inspect(frag))
      end
      for _, character in ipairs(characters) do
        check_like_getcompletion(halves .. "/item_" .. character, vim.inspect(character))
      end
    end

    -- A lone byte E4 is read as U+00E4, so for Neovim "item_" and that byte is a prefix of
    -- "item_" and the a-umlaut written C3 A4 as well, and the other way round. Where the bytes
    -- decide -- no case folding, so not on Windows -- the big list kept only the names that
    -- agree with the fragment byte by byte: 300 of 440 with none of the UTF-8 names in them, or,
    -- for a fragment that is valid UTF-8, none of the Latin-1 ones (and, with too few of the
    -- agreeing ones, a trip to getcompletion() for what the list could have done). The order of
    -- the two spellings among themselves is the bytes' (getcompletion() orders by code point),
    -- so the list is judged by what it holds, not by its order. Needs a file system that keeps a
    -- name's bytes, whatever they are: not Windows (names are UTF-16 there, and case is folded
    -- anyway) and not one that normalizes or refuses them.
    for _, case in ipairs({
      { "Latin-1 fragment, both spellings", 320, 120, "item_\228", 120 },
      { "UTF-8 fragment, both spellings", 320, 40, "item_\195\164", 40 },
      { "Latin-1 fragment, UTF-8 names only", 0, 320, "item_\228", 300 },
    }) do
      local label, count_latin1, count_utf8, frag, want_utf8 = unpack(case)
      local coded = new_dir()
      dirs_made[#dirs_made + 1] = coded
      local coded_names = {}
      for i = 0, count_latin1 - 1 do
        coded_names[#coded_names + 1] = ("item_\228%03d"):format(i)
      end
      for i = 0, count_utf8 - 1 do
        coded_names[#coded_names + 1] = ("item_\195\164%03d"):format(i)
      end
      local created = vim.fn.has("win32") == 0
      for _, name in ipairs(coded_names) do
        if not created then
          break
        end
        created = pcall(touch, coded .. "/" .. name)
      end
      if created and listed_verbatim(coded, coded_names) then
        local real = {}
        with_case_options(false, false, function()
          for _, name in ipairs(real_getcompletion(coded .. "/" .. frag, "file")) do
            real[name] = true
          end
          ok(vim.tbl_count(real) > MAX, label .. ": getcompletion() has more than a menu")
          press_tab(coded .. "/" .. frag)
        end)
        eq(getcompletion_calls, 0, label .. ": the big list answers")
        eq(#shown, MAX, label)
        local latin1, utf8_names = 0, 0
        for _, name in ipairs(shown) do
          ok(real[name], label .. ": getcompletion() lists " .. vim.inspect(name))
          if name:find("item_\228", 1, true) then
            latin1 = latin1 + 1
          elseif name:find("item_\195\164", 1, true) then
            utf8_names = utf8_names + 1
          end
        end
        eq(utf8_names, want_utf8, label .. ": the UTF-8 names in the list")
        eq(latin1, MAX - want_utf8, label .. ": the Latin-1 names in the list")
      end
    end

    -- More plain names than a menu holds that start with "U", and five that start with "U"
    -- and a combining mark (an umlaut written as two characters): "U" is a prefix of the plain
    -- ones only, and the marked ones would sort first ("Uy000" before "Uz000") were they let
    -- in. The byte comparison takes "U" for a prefix of "U" + U+0308 + "y000"; Neovim's regex
    -- does not, and the bytes ask it whenever the next byte could begin a mark (CC or later).
    -- Only a file system whose matching is case-sensitive reaches that (Linux, macOS; not
    -- Windows, where the regex decides everything): there it is all that keeps them out.
    local crowd = new_dir()
    dirs_made[#dirs_made + 1] = crowd
    local crowd_names = {}
    for i = 0, MAX + 9 do
      crowd_names[#crowd_names + 1] = ("Uz%03d"):format(i)
    end
    for i = 0, 4 do
      crowd_names[#crowd_names + 1] = ("U%sy%03d"):format(vim.fn.nr2char(0x308), i)
    end
    for _, name in ipairs(crowd_names) do
      touch(crowd .. "/" .. name)
    end
    if listed_verbatim(crowd, crowd_names) then
      with_case_options(true, false, function()
        ok(#real_getcompletion(crowd .. "/U", "file") > MAX, "U among marked names: a long list")
      end)
      check_like_getcompletion(crowd .. "/U", "U among marked names")
      check_like_getcompletion(crowd .. "/u", "u among marked names")
      press_tab(crowd .. "/U")
      eq(shown[1], crowd .. "/Uz000", "the plain names, from the start")

      -- `vim.regex` compiles every pattern this list can ask it for, so nothing real reaches
      -- that fallback; it is a safety net for a list that would be built without the judge
      -- of the marked names, and it is pinned with a matcher that refuses.
      local real_regex = vim.regex
      vim.regex = function()
        error("E0: no matcher")
      end
      local stub_ok, stub_err = pcall(function()
        with_case_options(true, false, function()
          press_tab(crowd .. "/U")
          eq(getcompletion_calls, 1, "no matcher: getcompletion() answers")
          eq(shown[1], "from-getcompletion", "no matcher: its answer")
        end)
      end)
      vim.regex = real_regex
      assert(stub_ok, stub_err)
    end

    -- A file cannot be an answer for "dir", so it is neither kept nor asked about its name:
    -- three hundred files with a combining mark would otherwise cost the question for marks
    -- (and the sort) on names that are dropped at the end. Nothing but the two directories is
    -- left, and no `strchars()` has been asked about a name with the mark (the prompt itself
    -- asks others).
    local filed = new_dir()
    dirs_made[#dirs_made + 1] = filed
    local filed_names = {}
    for i = 0, MAX + 9 do
      filed_names[#filed_names + 1] = ("f%s%03d"):format(vim.fn.nr2char(0x308), i)
    end
    for _, name in ipairs(filed_names) do
      touch(filed .. "/" .. name)
    end
    vim.fn.mkdir(filed .. "/sub_a", "p")
    vim.fn.mkdir(filed .. "/sub_b", "p")
    if listed_verbatim(filed, filed_names) then
      local real_strchars, strchars_calls = vim.fn.strchars, 0
      vim.fn.strchars = function(s, ...)
        if type(s) == "string" and s:find("\204\136", 1, true) then
          strchars_calls = strchars_calls + 1
        end
        return real_strchars(s, ...)
      end
      local filed_ok, filed_err = pcall(press_tab, filed .. "/", "dir")
      vim.fn.strchars = real_strchars
      assert(filed_ok, filed_err)
      eq(getcompletion_calls, 0, "files with marks, completion = dir: the listing has the answer")
      ok(vim.deep_equal({ filed .. "/sub_a/", filed .. "/sub_b/" }, shown), "the two directories")
      eq(strchars_calls, 0, "and no file was asked about a mark")
    end

    -- A fragment with a NUL byte (no file name holds one) is getcompletion()'s and must
    -- not raise E976 out of the mapping: the fold of a non-ASCII name goes through
    -- `toupper()`, and a NUL in a Lua string reaches `vim.fn` as a Blob.
    with_case_options(true, false, function()
      for _, line in ipairs({ "\195\164\0x", "ab\0x", dir .. "/\195\164\0x", dir .. "/item_\0" }) do
        local pressed, press_err = pcall(press_tab, line)
        ok(pressed, "<Tab> on " .. vim.inspect(line) .. ": " .. tostring(press_err))
        eq(getcompletion_calls, 1, "getcompletion() has it: " .. vim.inspect(line))
      end
    end)

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
  uv.fs_scandir, uv.fs_scandir_next = real_scandir, real_scandir_next
  close_floats()
  for _, d in ipairs(dirs_made) do
    vim.fn.delete(d, "rf")
  end
  assert(done, err)
end
