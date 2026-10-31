-- TESTS/data_classes_spec.lua — lib.nvim.data_classes
--
-- The first block ports the tests of tasks-desktop/crates/tasks-hub/src/classes.rs (the reading side; the proposal
-- writer `propose` is the hub's and has no counterpart here). The rest: the config path of tasks-desktop, the lookup
-- of a repository, and the edges where a lenient JSON parser would release an area the hub keeps closed.

return function(H)
  local eq, ok = H.eq, H.ok
  local dc = require("lib.nvim.data_classes")

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  ---A config folder holding `areas.json` with `text` (written byte for byte).
  ---@param name string
  ---@param text string
  ---@return string dir
  local function temp(name, text)
    local dir = root .. "/" .. name
    vim.fn.mkdir(dir, "p")
    local fh = assert(io.open(dir .. "/areas.json", "wb"))
    fh:write(text)
    fh:close()
    return dir
  end

  local function load(name, text)
    return dc.load({ dir = temp(name, text) })
  end

  local GOOD = [[{"schema":1,"areas":{
        "alpha.nvim":{"class":"internal","repo":"alpha.nvim"},
        "pub-area":{"class":"public"},
        "secret-area":{"class":"private"}}}]]

  local TWO = [[{"schema":2,
        "vaults":{"work":{"default":"internal"}},
        "areas":{
            "main:shared.nvim":{"class":"public"},
            "work:shared.nvim":{"class":"private"},
            "work:only-work":{"class":"internal","repo":"w"}}}]]

  -- -- classes.rs: a_missing_file_classifies_nothing ------------------------------------------------------------------
  do
    local empty = root .. "/none"
    vim.fn.mkdir(empty, "p")
    local classes, problem = dc.load({ dir = empty })
    eq(problem, nil, "missing file: no problem")
    eq(classes.problem, nil, "missing file: no problem on the classes")
    eq(classes.missing, true, "missing file: told as missing")
    local policy = classes:for_vault("main")
    ok(policy:is_empty(), "missing file: no entries")
    eq(policy:shown("anything"), "unclassified", "missing file: unclassified")
    eq(policy:allows("anything"), false, "missing file: nothing released")
  end

  -- -- classes.rs: a_default_class_covers_the_areas_without_an_entry ---------------------------------------------------
  do
    local policy = load(
      "default",
      [[{"schema":1,"default":"internal",
            "areas":{"secret-area":{"class":"private"}}}]]
    ):for_vault("main")
    eq(policy:shown("anything"), "internal", "default: covers an area without an entry")
    eq(policy:allows("anything"), true, "default internal: released")
    -- an entry wins over the default, in both directions
    eq(policy:shown("secret-area"), "private", "default: an entry wins")
    eq(policy:allows("secret-area"), false, "default: a private entry stays closed")
    eq(#policy:unclassified({ "anything", "x" }), 0, "default: nothing unclassified")
    eq(policy:default(), "internal", "default: told")
  end

  -- -- classes.rs: unclassified_and_private_leave_nothing -------------------------------------------------------------
  do
    local policy = load("good", GOOD):for_vault()
    eq(policy:allows("alpha.nvim"), true, "internal: released")
    eq(policy:allows("pub-area"), true, "public: released")
    eq(policy:allows("secret-area"), false, "private: not released")
    eq(policy:allows("never-heard-of"), false, "unclassified: not released")
  end

  -- -- classes.rs: a_new_area_is_marked_unclassified ------------------------------------------------------------------
  do
    local policy = load("new", GOOD):for_vault("main")
    local all = { "alpha.nvim", "secret-area", "brand-new.nvim" }
    eq(table.concat(policy:unclassified(all), ","), "brand-new.nvim", "new area: unclassified")
    eq(table.concat(policy:private_areas(all), ","), "secret-area", "private areas")
    eq(policy:repo_of("alpha.nvim"), "alpha.nvim", "repo_of: named")
    eq(policy:repo_of("pub-area"), nil, "repo_of: not named")
    eq(policy:len(), 3, "three entries")
    eq(
      table.concat(policy:areas(), ","),
      "alpha.nvim,pub-area,secret-area",
      "areas: the entries, sorted"
    )
    local e = policy:entry("alpha.nvim")
    eq(e and e.class, "internal", "entry: the class")
    eq(e and e.repo, "alpha.nvim", "entry: the repo")
    eq(policy:entry("secret-area").repo, nil, "entry: no repo")
    eq(policy:entry("brand-new.nvim"), nil, "entry: none for an area without one")
    -- a copy: changing it changes nothing the policy says
    e.class = "public"
    eq(policy:shown("alpha.nvim"), "internal", "entry: a copy")
    local names = policy:areas()
    names[1] = "x"
    eq(policy:areas()[1], "alpha.nvim", "areas: a copy")
  end

  -- -- an area a caller could not work out is not released by the default --------------------------------------------
  do
    local classes = dc.parse([[{"schema":1,"default":"public","areas":{}}]])
    eq(classes:shown("x"), "public", "default: covers a named area")
    for _, bad in ipairs({ { nil }, { 42 }, { true }, { {} } }) do
      local label = "not an area name " .. vim.inspect(bad[1])
      eq(classes:shown(bad[1]), "unclassified", label .. ": unclassified")
      eq(classes:allows(bad[1]), false, label .. ": not released")
      eq(classes:for_vault():shown(bad[1]), "unclassified", label .. ": in the policy")
      eq(classes:for_vault():allows(bad[1]), false, label .. ": not released by the policy")
    end
  end

  -- -- classes.rs: a_file_that_is_not_right_is_refused ----------------------------------------------------------------
  for _, case in ipairs({
    { "typo", [[{"schema":1,"areas":{"a":{"clas":"private"}}}]] },
    { "class", [[{"schema":1,"areas":{"a":{"class":"secret"}}}]] },
    { "schema", [[{"schema":3,"areas":{}}]] },
    { "extra", [[{"schema":1,"areas":{},"more":1}]] },
    { "traversal", [[{"schema":1,"areas":{"../x":{"class":"private"}}}]] },
    { "repo", [[{"schema":1,"areas":{"a":{"class":"public","repo":"../x"}}}]] },
    { "json", "{" },
  }) do
    local classes, problem = load("bad-" .. case[1], case[2])
    eq(classes.kind, "invalid", case[1] .. ": invalid")
    ok(type(problem) == "string" and problem ~= "", case[1] .. ": says why")
    eq(classes:shown("a"), "unclassified", case[1] .. ": classifies nothing")
  end

  -- -- classes.rs: a_huge_file_is_refused -----------------------------------------------------------------------------
  do
    local parts = { [[{"schema":1,"areas":{]] }
    for i = 0, 19999 do
      parts[#parts + 1] = ([["area%d":{"class":"public"}},]]):format(i)
    end
    parts[#parts + 1] = [["z":{"class":"public"}}}]]
    local classes, problem = load("huge", table.concat(parts))
    eq(classes.kind, "invalid", "huge: invalid")
    ok(problem and problem:find("larger than 256 KiB", 1, true), "huge: says why")
    eq(classes:shown("z"), "unclassified", "huge: classifies nothing")
  end

  -- -- classes.rs: schema_two_keeps_a_class_for_each_vault_even_for_the_same_area_name --------------------------------
  do
    local classes = load("two", TWO)
    eq(classes.problem, nil, "two: usable")
    eq(classes.schema, 2, "two: schema 2")
    local main, work = classes:for_vault("main"), classes:for_vault("work")
    eq(main:shown("shared.nvim"), "public", "two: main's class")
    eq(work:shown("shared.nvim"), "private", "two: work's class for the same name")
    eq(main:shown("only-work"), "unclassified", "two: an area of work is nothing in main")
    eq(work:shown("only-work"), "internal", "two: work's entry")
    eq(work:shown("anything"), "internal", "two: work's default")
    eq(main:shown("anything"), "unclassified", "two: main has no default")
    eq(work:repo_of("only-work"), "w", "two: repo of work")
    local other = classes:for_vault("third")
    ok(other:is_empty(), "two: a vault the file does not name has no entries")
    eq(other:shown("shared.nvim"), "unclassified", "two: and does not take over main")
    eq(table.concat(classes:vaults(), ","), "main,work", "two: the vaults")
  end

  -- -- classes.rs: schema_one_is_the_vault_main_and_nothing_else ------------------------------------------------------
  do
    local classes = load("one", GOOD)
    eq(classes:shown("secret-area", "main"), "private", "one: main")
    eq(classes:shown("secret-area", "work"), "unclassified", "one: not another vault")
    eq(classes:shown("alpha.nvim"), "internal", "one: main is the default vault")
  end

  -- -- classes.rs: a_schema_two_file_that_is_not_right_is_refused -----------------------------------------------------
  for _, case in ipairs({
    { "nokey", [[{"schema":2,"areas":{"plain":{"class":"public"}}}]] },
    { "novault", [[{"schema":2,"areas":{":a":{"class":"public"}}}]] },
    { "dotvault", [[{"schema":2,"areas":{".x:a":{"class":"public"}}}]] },
    { "badarea", [[{"schema":2,"areas":{"main:../x":{"class":"public"}}}]] },
    { "rule", [[{"schema":2,"vaults":{"main":{"class":"public"}},"areas":{}}]] },
    { "extra", [[{"schema":2,"areas":{},"more":1}]] },
  }) do
    local classes = load("bad2-" .. case[1], case[2])
    eq(classes.kind, "invalid", "schema 2 " .. case[1] .. ": invalid")
    eq(classes:shown("a"), "unclassified", "schema 2 " .. case[1] .. ": classifies nothing")
  end

  -- -- the config path of tasks-desktop (appkit_hub::config::config_dir) ----------------------------------------------
  do
    -- config.rs: env_override_wins_for_the_config_dir
    eq(
      dc.config_dir({
        os = "windows",
        env = { TASKS_DESKTOP_CONFIG_DIR = "C:/x/cfg", APPDATA = "C:/a" },
      }),
      "C:/x/cfg",
      "path: the variable wins"
    )
    -- config.rs: an_empty_variable_is_not_set
    eq(
      dc.config_dir({ os = "windows", env = { TASKS_DESKTOP_CONFIG_DIR = "", APPDATA = "C:/a" } }),
      "C:/a/tasks-desktop",
      "path: an empty variable is not set"
    )
    eq(
      dc.config_dir({ os = "macos", env = { HOME = "/Users/u" } }),
      "/Users/u/Library/Application Support/tasks-desktop",
      "path: macOS"
    )
    eq(
      dc.config_dir({ os = "linux", env = { XDG_CONFIG_HOME = "/x", HOME = "/home/u" } }),
      "/x/tasks-desktop",
      "path: Linux with XDG_CONFIG_HOME"
    )
    eq(
      dc.config_dir({ os = "linux", env = { XDG_CONFIG_HOME = "", HOME = "/home/u" } }),
      "/home/u/.config/tasks-desktop",
      "path: Linux without XDG_CONFIG_HOME"
    )
    eq(
      dc.config_dir({ os = "linux", app = "other-app", env = { HOME = "/home/u" } }),
      "/home/u/.config/other-app",
      "path: another app"
    )
    eq(
      dc.config_dir({
        os = "linux",
        env_var = "OTHER_CONFIG_DIR",
        env = { OTHER_CONFIG_DIR = "/o" },
      }),
      "/o",
      "path: another variable"
    )
    local none, why = dc.config_dir({ os = "windows", env = {} })
    eq(none, nil, "path: no APPDATA, no folder")
    ok(why and why:find("APPDATA", 1, true), "path: says which variable")
    local classes, problem = dc.load({ os = "windows", env = {} })
    eq(classes.kind, "no_config_dir", "load without a config folder: told")
    ok(problem ~= nil, "load without a config folder: a problem")
    eq(classes:shown("a"), "unclassified", "load without a config folder: nothing classified")
    -- the variable is what load reads
    local dir = temp("by-env", GOOD)
    eq(
      dc.load({ env = { TASKS_DESKTOP_CONFIG_DIR = dir } }):shown("secret-area"),
      "private",
      "load: through the variable"
    )
    eq(dc.path({ dir = "/d" }), "/d/areas.json", "path: in a folder")
    eq(dc.path({ path = "/f.json", dir = "/d" }), "/f.json", "path: the file wins")
  end

  -- -- a repository by its folder -------------------------------------------------------------------------------------
  do
    local classes = load(
      "repos",
      [[{"schema":2,"vaults":{"main":{"default":"public"}},"areas":{
          "main:wkdbook-lib.nvim":{"class":"internal","repo":"lib.nvim"},
          "main:open":{"class":"public","repo":"open.nvim"},
          "main:also-open":{"class":"private","repo":"two.nvim"},
          "main:two-public":{"class":"public","repo":"two.nvim"},
          "work:x":{"class":"private","repo":"open.nvim"}}}]]
    )
    eq(classes:class_of_repo("lib.nvim"), "internal", "repo: by its name")
    eq(classes:class_of_repo("E:/repos/lib.nvim"), "internal", "repo: by its folder")
    eq(classes:class_of_repo("E:\\repos\\lib.nvim\\"), "internal", "repo: a trailing separator")
    local class, matches = classes:class_of_repo("two.nvim")
    eq(class, "private", "repo: two areas name it, the strictest wins")
    eq(#matches, 2, "repo: both areas told")
    eq(classes:class_of_repo("open.nvim"), "private", "repo: across the vaults, the strictest wins")
    eq(classes:class_of_repo("open.nvim", "main"), "public", "repo: in one vault")
    -- the default of main is for its areas; which area a repository belongs to only an entry says
    eq(classes:class_of_repo("unknown.nvim"), "unclassified", "repo: no entry names it")
    eq(classes:class_of_repo("Lib.nvim"), "unclassified", "repo: another case is another name")
    eq(classes:class_of_repo(""), "unclassified", "repo: empty")
    eq(
      classes:class_of_repo("open"),
      "unclassified",
      "repo: an area name is not a repo when its entry names another"
    )
    -- main's default is for main: a vault without a rule of its own has no default
    eq(
      classes:shown("other", "work"),
      "unclassified",
      "repo fixture: work does not take main's default"
    )
    eq(classes:allows("other", "work"), false, "repo fixture: nothing of work released")
    eq(classes:for_vault("work"):default(), nil, "repo fixture: work has no default")

    -- an area named like the repository, without a `repo` field, names it too: the strictest still wins
    local by_name = dc.parse([[{"schema":1,"areas":{
        "lib.nvim":{"class":"private"},
        "wkdbook-lib.nvim":{"class":"public","repo":"lib.nvim"}}}]])
    local named, found = by_name:class_of_repo("E:/repos/lib.nvim")
    eq(named, "private", "repo: an area of that name without a repo field counts")
    eq(#found, 2, "repo: both areas told")
    eq(found[1].by, "name", "repo: told how it was named (by the area name)")
    eq(found[2].by, "repo", "repo: told how it was named (by the repo field)")

    -- an area name alone never releases: without a `repo` match the repository stays unclassified
    local name_only = dc.parse([[{"schema":1,"areas":{"lib.nvim":{"class":"public"}}}]])
    local alone, told = name_only:class_of_repo("E:/repos/lib.nvim")
    eq(alone, "unclassified", "repo: an area name alone releases nothing")
    eq(#told, 1, "repo: the area name match is still told")
    eq(told[1].by, "name", "repo: told as a match by the area name")

    local cls, problem = dc.class_of_repo("E:/repos/lib.nvim", { dir = root .. "/repos" })
    eq(cls, "internal", "class_of_repo: loads")
    eq(problem, nil, "class_of_repo: no problem")
    cls, problem = dc.class_of_repo("open.nvim", { dir = root .. "/repos", vault = "main" })
    eq(cls, "public", "class_of_repo: one vault")
    eq(problem, nil, "class_of_repo: one vault, no problem")
    temp("repos-broken", [[{"schema":1,"areas":{"a":{"class":"public","repo":"lib.nvim","x":1}}}]])
    cls, problem = dc.class_of_repo("lib.nvim", { dir = root .. "/repos-broken" })
    eq(cls, "unclassified", "class_of_repo: a broken file releases nothing")
    ok(problem and problem:find("unknown field", 1, true), "class_of_repo: says why")
  end

  -- -- a file that cannot be read -------------------------------------------------------------------------------------
  do
    local dir = root .. "/dir-file"
    vim.fn.mkdir(dir .. "/areas.json", "p")
    local classes, problem = dc.load({ dir = dir })
    eq(classes.kind, "unreadable", "a folder named areas.json: unreadable")
    ok(problem ~= nil and not problem:find(dir, 1, true), "unreadable: says why, without the path")
    eq(classes.missing, false, "unreadable: not missing")
    eq(
      vim.fs.normalize(classes.path),
      vim.fs.normalize(dir .. "/areas.json"),
      "unreadable: the path is a field"
    )
    ok(not problem:find("areas.json", 1, true), "unreadable: no part of the path in the reason")
  end

  -- -- as strictly as serde_json: where a lenient parser would release an area ----------------------------------------
  local function refused(text, label)
    local classes = dc.parse(text)
    ok(classes.problem ~= nil, label .. ": refused")
    eq(classes:shown("a"), "unclassified", label .. ": classifies nothing")
  end
  local function shows(text, want, label)
    local classes = dc.parse(text)
    eq(classes.problem, nil, label .. ": usable")
    for area, class in pairs(want) do
      eq(classes:shown(area), class, label .. ": " .. area)
    end
  end

  refused([[{"schema":1,"areas":{"a":{"class":"private","class":"public"}}}]], "a field twice")
  refused([[{"schema":1,"schema":1,"areas":{}}]], "schema twice")
  refused([[{"schema":1,"sch\u0065ma":1,"areas":{}}]], "schema twice, once escaped")
  refused([[{"schema":1.0,"areas":{}}]], "schema 1.0")
  refused([[{"schema":1e0,"areas":{}}]], "schema 1e0")
  refused([[{"schema":-0,"areas":{}}]], "schema -0")
  refused([[{"schema":01,"areas":{}}]], "schema 01")
  refused([[{"schema":4294967297,"areas":{}}]], "schema over 32 bits")
  refused([[{"schema":"1","areas":{}}]], "schema as a text")
  refused("\239\187\191" .. [[{"schema":1,"areas":{}}]], "a byte order mark")
  refused([[{"schema":1,"areas":{"a]] .. "\195" .. [[":{"class":"public"}}}]], "not UTF-8")
  eq(dc.parse("\255").kind, "unreadable", "not UTF-8: unreadable, as read_to_string")
  refused([[{"schema":1,"areas":{"a\ud83d":{"class":"private"}}}]], "a lone surrogate")
  refused([[{"schema":1,"areas":{"a":{"cl\u0x61ss":"public"}}}]], "a hex prefix in an escape")
  refused([[{"schema":1,"areas":{},}]], "a trailing comma")
  refused([[{"schema":1,/* x */"areas":{}}]], "a comment")
  refused('{"schema":1,\194\160"areas":{}}', "a no-break space")
  refused([[{"schema":1,"areas":{}} x]], "text after the value")
  refused("", "an empty file")
  refused("null", "null")
  refused([[{"schema":1,"areas":{},"x":]] .. ("["):rep(200) .. ("]"):rep(200) .. "}", "nested deep")
  -- refused by the depth limit itself, before a deep text can run the parser out of stack
  local deep = dc.parse(("["):rep(100000))
  eq(deep.problem, "nested too deep", "nested deep: the limit says why")
  refused([[{"schema":1,"areas":{"a\u0085b":{"class":"private"}}}]], "a C1 control in a name")
  refused([[{"schema":1,"areas":{"a":{"class":"public","repo":""}}}]], "an empty repo")
  refused([[{"schema":1,"areas":{"a":{"class":"\u0050ublic"}}}]], "a class in capitals")
  refused([[{"schema":2,"vaults":null,"areas":{}}]], "vaults null")
  refused([[{"schema":2,"default":"public","areas":{}}]], "schema 2 with a top-level default")
  refused([[{"schema":1,"vaults":{},"areas":{}}]], "schema 1 with vaults")
  refused([[{"schema":2,"areas":{"wörk:a":{"class":"public"}}}]], "a vault name that is not ASCII")
  -- the keys of `vaults` are vault names as well: a rule for a vault no list could hold refuses the file
  for _, bad in ipairs({ ".hidden", "my vault", ("v"):rep(41), "wörk" }) do
    local classes =
      dc.parse(('{"schema":2,"vaults":{"%s":{"default":"public"}},"areas":{}}'):format(bad))
    ok(classes.problem ~= nil, "a rule for vault " .. vim.inspect(bad) .. ": refused")
    eq(
      classes:for_vault(bad):allows("x"),
      false,
      "a rule for vault " .. bad .. ": nothing released"
    )
  end
  -- a vault without a rule of its own never takes main's default
  do
    local classes = dc.parse(
      [[{"schema":2,"vaults":{"main":{"default":"public"}},"areas":{"work:x":{"class":"private"}}}]]
    )
    eq(classes.problem, nil, "main's default: usable")
    eq(classes:shown("anything"), "public", "main's default: main")
    eq(classes:for_vault("work"):shown("anything"), "unclassified", "main's default: not work's")
    eq(
      classes:for_vault("work"):allows("anything"),
      false,
      "main's default: nothing of work released"
    )
  end

  -- a unit enum as serde_json reads it: a text, or a map of the name to null
  shows(
    [[{"schema":1,"areas":{"a":{"class":{"public":null}},"b":[{"private":null}]}}]],
    { a = "public", b = "private" },
    "a class written as a map"
  )
  shows(
    [[{"schema":1,"default":{"internal":null},"areas":{}}]],
    { a = "internal" },
    "a default written as a map"
  )
  shows(
    [[{"schema":2,"vaults":{"main":{"default":{"public":null}}},"areas":{}}]],
    { a = "public" },
    "a vault default written as a map"
  )
  for label, form in pairs({
    ["an empty map"] = "{}",
    ["two names"] = '{"public":null,"private":null}',
    ["a name twice"] = '{"public":null,"public":null}',
    ["a value that is not null"] = '{"public":1}',
    ["an empty map as the value"] = '{"public":{}}',
    ["an unknown name"] = '{"secret":null}',
    ["a name in capitals"] = '{"Public":null}',
    ["a list"] = '["public"]',
  }) do
    refused(('{"schema":1,"areas":{"a":{"class":%s}}}'):format(form), "a class as a map, " .. label)
    refused(('{"schema":1,"default":%s,"areas":{}}'):format(form), "a default as a map, " .. label)
  end

  -- 256 KiB is the largest file: the size counts, for a text and for a file
  do
    local head = '{"schema":1,"areas":{"a":{"class":"public"}}}'
    local at_limit = head .. (" "):rep(dc.MAX_FILE_BYTES - #head)
    eq(#at_limit, 256 * 1024, "limit: the text is 256 KiB")
    shows(at_limit, { a = "public" }, "limit: 256 KiB is read")
    local over = at_limit .. " "
    local classes = dc.parse(over)
    eq(classes.kind, "invalid", "limit: one byte more is invalid")
    eq(classes.problem, "larger than 256 KiB", "limit: one byte more says why")
    eq(classes:shown("a"), "unclassified", "limit: one byte more classifies nothing")
    eq(load("limit", at_limit):shown("a"), "public", "limit: a file of 256 KiB is read")
    local file_over, why = load("limit-over", over)
    eq(file_over:shown("a"), "unclassified", "limit: a file one byte over classifies nothing")
    eq(why, "larger than 256 KiB", "limit: a file one byte over says why")
  end
  refused(
    [[{"schema":2,"areas":{"work:../x":{"class":"public"},"main:a":{"class":"public"}}}]],
    "a bad area in another vault"
  )

  shows(
    [[{"schema":1,"areas":{"a":{"class":"private"},"a":{"class":"public"}}}]],
    { a = "public" },
    "an area twice: the last"
  )
  refused(
    [[{"schema":1,"areas":{"a":{"class":"bad"},"a":{"class":"public"}}}]],
    "an area twice: the first is checked"
  )
  shows(
    [[{"schema":1,"areas":{"caf\u00e9":{"class":"private"},"café":{"class":"public"}}}]],
    { ["café"] = "public" },
    "an escape and the letter are one area"
  )
  shows(
    [[{"schema":1,"areas":{"\ud83d\ude00":{"class":"private"}}}]],
    { ["\240\159\152\128"] = "private" },
    "a surrogate pair"
  )
  shows(
    [[{"schema":1,"areas":{"a":["private"],"b":["public","repo-b"],"c":["internal",null]}}]],
    { a = "private", b = "public", c = "internal" },
    "an entry written as a list"
  )
  refused([[{"schema":1,"areas":{"a":["public","r",1]}}]], "an entry as a list, a field too many")
  shows(
    [[{"sch\u0065ma":1,"ar\u0065as":{"a":{"cl\u0061ss":"public"}}}]],
    { a = "public" },
    "escaped field names"
  )
  shows(
    [[{"schema":1,"default":null,"areas":{"x":{"class":"public","repo":null}}}]],
    { a = "unclassified", x = "public" },
    "null is none"
  )
  shows(
    '\t{\r\n"schema":1,\r\n"areas":{"a":{"class":"public"}}\r\n}\r\n',
    { a = "public" },
    "CRLF is white space"
  )
  shows(
    [[{"schema":2,"vaults":{"main":{},"work":{"default":null}},"areas":{"main:a":{"class":"public"}}}]],
    { a = "public", b = "unclassified" },
    "schema 2: empty rules"
  )
  shows(
    ('{"schema":1,"areas":{"%s":{"class":"public"}}}'):format(("\240\159\152\128"):rep(128)),
    { [("\240\159\152\128"):rep(128)] = "public" },
    "128 characters, counted as characters"
  )
  refused(
    ('{"schema":1,"areas":{"%s":{"class":"public"}}}'):format(("\240\159\152\128"):rep(129)),
    "129 characters"
  )
  do
    local many = {}
    for i = 0, 999 do
      many[#many + 1] = ('"a%d":{"class":"public"}'):format(i)
    end
    shows(
      '{"schema":1,"areas":{' .. table.concat(many, ",") .. "}}",
      { a999 = "public" },
      "1000 areas"
    )
    shows(
      '{"schema":1,"areas":{' .. table.concat(many, ",") .. ',"a0":{"class":"private"}}}',
      { a0 = "private" },
      "1001 entries, one named twice: 1000 areas"
    )
    many[#many + 1] = '"a1000":{"class":"public"}'
    refused('{"schema":1,"areas":{' .. table.concat(many, ",") .. "}}", "1001 areas")
  end

  -- the name checks on their own
  eq((dc.valid_area_name("lib.nvim")), true, "name: lib.nvim")
  eq((dc.valid_area_name("a b")), true, "name: a space inside")
  for _, bad in ipairs({ "", ".a", "a.", "a ", "a,b", "a:b", "a/b", "a\\b", "a\0b", ("n"):rep(129) }) do
    eq((dc.valid_area_name(bad)), false, "name refused: " .. vim.inspect(bad))
  end
  -- what a Rust `&str` can never be
  for _, bad in ipairs({ "a\255", "a\195", "\128a", "a\237\160\128b", "\192\175" }) do
    local valid, why = dc.valid_area_name(bad)
    eq(valid, false, "name refused, not UTF-8: " .. vim.inspect(bad))
    eq(why, "is not valid UTF-8", "name refused, not UTF-8, says why: " .. vim.inspect(bad))
  end
  eq((dc.valid_area_name("café")), true, "name: UTF-8 is fine")
  eq((dc.valid_vault_name("main")), true, "vault: main")
  eq((dc.valid_vault_name(("v"):rep(40))), true, "vault: 40 characters")
  eq((dc.valid_vault_name(("v"):rep(41))), false, "vault: 41 characters")
  eq((dc.valid_vault_name("my vault")), false, "vault: a space")
end
