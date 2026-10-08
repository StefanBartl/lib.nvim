-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_marks_order_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_marks_order_spec.lua (the kit exists twice, see ui.nvim's docs/modules.md):
-- `order_by_base_characters`, the sort keys of a big directory's <Tab> list.
--
-- A name with a combining mark is ordered by its base characters, and the keys of all of
-- them were made by `split()`, which costs about ten times what a few patterns do for the
-- names of a macOS directory (`e` + U+0301). The common marks (U+0300..U+036F) of a name that
-- is nothing but ASCII, Latin-1 and those marks are now cut out with patterns, and every
-- other name still goes through the split. The keys have to be the same either way: this file
-- rebuilds the split version (the reference) and compares them for a great many names, the
-- odd ones included -- and the order with what `getcompletion()` gives for real files.

return function(H)
  local eq, ok = H.eq, H.ok
  local input = require("lib.nvim.ui.kit.input")
  local fn = vim.fn
  local uv = vim.uv or vim.loop

  local SPLIT = vim.fn.nr2char(92) .. "zs" -- the pattern `\zs`

  --- The code `order_by_base_characters` had before: the reference.
  ---@param found {key: string, name: string}[]
  ---@param wides integer[]
  ---@param after_sep boolean
  local function reference(found, wides, after_sep)
    local lead = after_sep and "/" or ""
    local names = {}
    for i = 1, #wides do
      names[i] = lead .. found[wides[i]].name
    end
    local joined = table.concat(names, "\n")
    if fn.strchars(joined) == fn.strchars(joined, 1) then
      return
    end
    local first = after_sep and 2 or 1
    for i = 1, #wides do
      local it = found[wides[i]]
      local text = lead .. it.key
      if fn.strchars(text) ~= fn.strchars(text, 1) then
        local clusters = fn.split(text, SPLIT)
        local bases = {}
        for c = first, #clusters do
          bases[#bases + 1] = clusters[c]:match("^[\1-\127\194-\244][\128-\191]*") or clusters[c]
        end
        it.key = table.concat(bases)
      end
    end
  end

  --- What the caller hands over: the indices of the names with a byte from CC on.
  ---@param names string[]
  ---@return {key: string, name: string}[] found
  ---@return integer[] wides
  local function listing(names)
    local found, wides = {}, {}
    for i, name in ipairs(names) do
      found[i] = { key = name, name = name }
      if name:find("[\204-\255]") then
        wides[#wides + 1] = i
      end
    end
    return found, wides
  end

  --- Pieces of names: every kind there is, the marks at the edges of U+0300..U+036F, and
  --- bytes that make no character.
  local PIECES = {
    "a",
    "b",
    "z",
    "_",
    "1",
    ".",
    " ",
    "\1",
    "\127",
    "\194\160", -- U+00A0
    "\194\173", -- U+00AD, soft hyphen
    "\194\133", -- U+0085, a C1 control
    "\194\159", -- U+009F, the last C1 control
    "\195\164", -- a-umlaut
    "\195\188", -- u-umlaut
    "a\204\136", -- a + U+0308 (NFD)
    "u\204\136",
    "e\204\129", -- e + U+0301
    "e\204\129\204\130", -- two marks
    "e\204\128\204\129\204\130\204\131", -- four
    "x\205\175", -- U+036F: the last mark
    "x\204\128", -- U+0300: the first
    "x\205\176", -- U+0370: no mark
    "x\205\174",
    "\204\129", -- a mark of its own
    "\205\175",
    "\205\176",
    "\208\186\208\184\209\128", -- Cyrillic
    "\208\184\204\134", -- Cyrillic + U+0306
    "\230\188\162\229\173\151", -- CJK
    "\230\188\162\204\129", -- CJK + mark
    "\214\145", -- Hebrew point (a mark of another block)
    "a\214\145",
    "a\225\183\128", -- U+1DC0
    "a\226\131\144", -- U+20D0
    "\226\128\143\204\129", -- a right-to-left mark and a mark behind it
    "\226\128\139\204\129", -- a zero-width space and a mark behind it
    "\226\157\164\239\184\143", -- a heart and its variation selector
    "\240\159\145\141\240\159\143\189", -- a thumb and its skin tone
    "\255", -- no UTF-8
    "\128",
    "\195", -- cut short
    "\226\130",
    "\195\204\129", -- a lead byte, then a mark
    "\194\204\129\169", -- ... and a continuation behind the mark
    "\255\204\129",
    "\128\204\129",
    "\226\130\204\129",
    "a\204", -- half a mark
    "a\204\129\129", -- a mark and a stray continuation byte
    "a\204\192",
  }

  --- The keys of `names` have to be the reference's, with and without a separator in front.
  ---@param names string[]
  ---@param label string
  local function same_keys(names, label)
    for _, after_sep in ipairs({ false, true }) do
      local want, wides = listing(names)
      local got = listing(names)
      reference(want, wides, after_sep)
      input.order_by_base_characters(got, wides, after_sep)
      for i = 1, #names do
        eq(
          got[i].key,
          want[i].key,
          ("%s, after_sep %s: %q"):format(label, tostring(after_sep), names[i])
        )
      end
    end
  end

  -- Names of every kind.
  math.randomseed(20261008)
  local jumble = {}
  for _ = 1, 4000 do
    local parts = {}
    for i = 1, math.random(1, 6) do
      parts[i] = PIECES[math.random(#PIECES)]
    end
    jumble[#jumble + 1] = table.concat(parts)
  end
  for _, piece in ipairs(PIECES) do
    jumble[#jumble + 1] = piece
  end
  same_keys(jumble, "jumble")

  -- Names of macOS spellings, long and short.
  local mac = {}
  for i = 1, 600 do
    mac[#mac + 1] = ("Caf\101\204\129 r\101\204\129sum\101\204\129 %04d.txt"):format(i)
    mac[#mac + 1] = ("Gr\117\204\136\195\159e %d"):format(i)
    mac[#mac + 1] = ("%d\101\204\129"):format(i)
  end
  same_keys(mac, "macOS")

  -- Real files, in the order getcompletion() gives them.
  do
    local dir = fn.tempname()
    eq(fn.mkdir(dir, "p"), 1, "the scratch directory")
    local bases = { "a", "e", "ee", "u", "o" }
    local spellings = { "%s\204\129", "%s\204\136", "%s\204\129\204\130", "%s", "\195\169%s" }
    local made = {}
    for i = 1, 120 do
      local name = ("m%s-%04d"):format(spellings[i % 5 + 1]:format(bases[i % #bases + 1]), i)
      if fn.writefile({}, dir .. "/" .. name, "S") == 0 then
        made[#made + 1] = name
      end
    end
    local entries = {}
    for _, p in ipairs(fn.getcompletion(dir .. "/", "file")) do
      entries[#entries + 1] = p:sub(#dir + 2)
    end
    eq(#entries, #made, "the files are all there")
    local found, wides = listing(made)
    input.order_by_base_characters(found, wides, true)
    table.sort(found, function(a, b)
      if a.key ~= b.key then
        return a.key < b.key
      end
      return a.name < b.name
    end)
    local mine = {}
    for _, it in ipairs(found) do
      mine[#mine + 1] = it.name
    end
    for _, name in ipairs(made) do
      uv.fs_unlink(dir .. "/" .. name)
    end
    uv.fs_rmdir(dir)
    ok(vim.deep_equal(mine, entries), "the order of getcompletion(): " .. vim.inspect(mine))
  end

  -- Quicker than the split for names written the macOS way.
  local many = {}
  for i = 1, 20000 do
    many[i] = ("caf\101\204\129_%06d.txt"):format(i)
  end
  -- Best of three for each: one stall on a busy machine must not decide the ratio. Fresh
  -- lists every round: a list that was ordered once holds its keys already.
  local slow, quick = math.huge, math.huge
  local want, wides, got
  for _ = 1, 3 do
    want, wides = listing(many)
    got = listing(many)
    local t0 = uv.hrtime()
    reference(want, wides, false)
    slow = math.min(slow, uv.hrtime() - t0)
    t0 = uv.hrtime()
    input.order_by_base_characters(got, wides, false)
    quick = math.min(quick, uv.hrtime() - t0)
  end
  eq(got[777].key, want[777].key, "the same key")
  ok(quick * 2 < slow, ("%.0f ms against %.0f ms"):format(quick / 1e6, slow / 1e6))
end
