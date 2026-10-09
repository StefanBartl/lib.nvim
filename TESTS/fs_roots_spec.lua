-- TESTS/fs_roots_spec.lua — lib.nvim.fs.roots (named-roots registry) and its two first
-- consumers, lib.nvim.cross.fs.expand_path and the composer path types PATH/DIR/FILE.
--
-- Why the module exists: five plugins carried their own copy of "$REPOS_DIR/x <-> D:/repos/x",
-- and the copies had drifted. The facts that force a registry rather than `vim.fn.expand`
-- (measured on Neovim 0.12.2, Windows): `expand`/`vim.fs.normalize`/`glob`/`:edit` expand `$VAR`
-- but NOT `${VAR}`; `filereadable`/`isdirectory`/`io.open`/`vim.uv.fs_*` expand nothing;
-- `fnamemodify(p, ":p")` prepends the cwd to `$VAR/x`; `vim.fs.normalize` expands `$X` in the
-- MIDDLE of a path as well. Every case below says which of those it pins.
--
-- Portability: the CI matrix runs this on Windows too, so every case that depends on spelling or
-- case folding sets `windows` explicitly instead of following the platform, and the roots come
-- from an injected `source` -- never from the machine's environment or its stdpath.

-- Many cases pass a value of the wrong type ON PURPOSE (nil, a number, a string for a table): that
-- is the thing under test, so the type diagnostics would only ever be noise here.
---@diagnostic disable: assign-type-mismatch, param-type-mismatch, missing-parameter, redundant-parameter

local roots = require("lib.nvim.fs.roots")
local expand_path = require("lib.nvim.cross.fs.expand_path")
local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")

local norm = vim.fs.normalize

--- The registry writes a drive letter uppercase; a Windows `tempname()` need not.
---@param p string
---@return string
local function up(p)
  return (p:gsub("^(%a):", function(d)
    return d:upper() .. ":"
  end))
end

--- A temp path in the registry's own spelling.
---@return string
local function tmp()
  return up(norm(vim.fn.tempname()))
end

---@param H table
return function(H)
  local eq, ok = H.eq, H.ok

  --- Run `fn` under a registry configuration, restoring the defaults afterwards whatever
  --- happens -- a leaked config would redirect every later spec in the shared run.
  ---@param cfg table
  ---@param fn fun()
  local function with_roots(cfg, fn)
    roots.setup(cfg)
    local done, err = pcall(fn)
    roots.setup()
    if not done then
      error(err, 0)
    end
  end

  ---@param list { name: string, root: string }[]
  ---@return string
  local function flat(list)
    local out = {}
    for _, r in ipairs(list) do
      out[#out + 1] = r.name .. "=" .. r.root
    end
    return table.concat(out, ";")
  end

  -- ── roots(): what counts as a root, and in which order ────────────────────────────────────
  --
  -- Order matters because "the first definition of a name wins": an `extra` entry has to be able
  -- to override an environment variable of the same name, and a result must never depend on the
  -- iteration order of a Lua table.
  with_roots({
    windows = false,
    vars = { "REPOS_DIR", "OTHER" },
    extra = { ZED = "/z", ALPHA = "/a", REPOS_DIR = "/from/extra" },
    source = { REPOS_DIR = "/from/env", OTHER = "/other", NVIM_CONFIG_DIR = "/cfg" },
  }, function()
    eq(
      flat(roots.roots()),
      "ALPHA=/a;REPOS_DIR=/from/extra;ZED=/z;OTHER=/other;NVIM_CONFIG_DIR=/cfg",
      "roots: extra alphabetical, then vars, then NVIM_CONFIG_DIR; extra overrides the env var"
    )
    eq(
      table.concat(roots.names(), ","),
      "ALPHA,REPOS_DIR,ZED,OTHER,NVIM_CONFIG_DIR",
      "names: the names of roots(), same order"
    )
  end)

  -- Normalization of a root's value: backslashes, doubled and trailing separators, a lowercase
  -- drive letter. A root with a trailing slash would make `fold` emit "$X//rest" and `expand`
  -- double the separator.
  with_roots({
    windows = true,
    nvim_config = false,
    vars = { "A", "B", "C", "D", "E" },
    source = {
      A = "d:\\repos\\",
      B = "D:/data//sub///",
      C = "relative/dir",
      D = "/",
      E = "C:/",
    },
  }, function()
    eq(
      flat(roots.roots()),
      "A=D:/repos;B=D:/data/sub",
      "roots: backslashes/trailing/doubled separators normalized, drive letter uppercased"
    )
    -- `D:/repos` and `D:/data/sub` may or may not exist on the machine running this: whether a
    -- usable root has a directory behind it is not the point here, so that problem is dropped.
    local names = {}
    for _, st in ipairs(roots.status()) do
      local problem = st.problem ~= "missing_dir" and st.problem or nil
      names[#names + 1] = st.name .. ":" .. tostring(problem)
    end
    eq(
      table.concat(names, ","),
      "A:nil,B:nil,C:not_absolute,D:too_broad,E:too_broad",
      "status: a relative value is refused; so are a whole drive / the filesystem root (too broad)"
    )
  end)

  -- A function value, a raising function, an empty string and a non-string: only a real path
  -- becomes a root, nothing throws.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = {
      OK = function()
        return "/fn/root"
      end,
      BOOM = function()
        error("nope")
      end,
      EMPTY = "",
      NUM = 5,
    },
  }, function()
    eq(flat(roots.roots()), "OK=/fn/root", "roots: function values resolved, bad ones skipped")
  end)

  -- A root defined through the home directory or another variable. `~` is expanded for real; the
  -- variable comes from the injected source, not from the process.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = { NOTES = "~/notes", VIAVAR = "$BASE/sub" },
    source = { BASE = "/base" },
  }, function()
    local home = ((vim.uv or vim.loop).os_homedir():gsub("\\", "/"):gsub("/$", ""))
    local list = roots.roots()
    eq(#list, 2, "roots: ~ and $VAR in a root value are expanded")
    eq(list[1].name, "NOTES", "roots: NOTES")
    ok(list[1].root:sub(1, #home) == up(home), "roots: ~ is the home")
    eq(list[2].root, "/base/sub", "roots: $BASE from the injected source")
  end)

  -- ── NVIM_CONFIG_DIR: injected source vs. the process ──────────────────────────────────────
  --
  -- "No silent fallback to the stdpath of a sandbox": with a source, a missing NVIM_CONFIG_DIR
  -- stays missing. Without one it is stdpath("config") -- and only that: a stale
  -- $NVIM_CONFIG_DIR inherited from a parent Neovim with another NVIM_APPNAME must not win.
  with_roots({ windows = false, vars = {}, source = { REPOS_DIR = "/r" } }, function()
    eq(
      #roots.roots(),
      0,
      "source without NVIM_CONFIG_DIR: the registry does NOT fall back to stdpath"
    )
    eq(roots.status()[1].problem, "unset", "source without NVIM_CONFIG_DIR: reported as unset")
  end)

  do
    local cfg = tmp()
    local saved = vim.env.NVIM_CONFIG_DIR
    vim.env.NVIM_CONFIG_DIR = "/stale/from/parent"
    H.with_stdpath_config(cfg, function()
      with_roots({ windows = false, vars = {} }, function()
        eq(
          flat(roots.roots()),
          "NVIM_CONFIG_DIR=" .. cfg,
          "no source: NVIM_CONFIG_DIR is stdpath('config'), not the (stale) env var"
        )
        eq(roots.expand("$NVIM_CONFIG_DIR/lua"), cfg .. "/lua", "expand: root without env var")
      end)
    end)
    vim.env.NVIM_CONFIG_DIR = saved
  end

  -- ── expand(): the measured cases ──────────────────────────────────────────────────────────
  with_roots({
    windows = false,
    vars = { "REPOS_DIR", "UNSET_ROOT" },
    source = { REPOS_DIR = "/work/repos", NVIM_CONFIG_DIR = "/work/nvim" },
  }, function()
    -- ${VAR}: `vim.fn.expand` cannot do it.
    eq(roots.expand("${REPOS_DIR}/a/b.lua"), "/work/repos/a/b.lua", "expand: ${NAME}/rest")
    eq(roots.expand("$REPOS_DIR/a/b.lua"), "/work/repos/a/b.lua", "expand: $NAME/rest")
    eq(roots.expand("%REPOS_DIR%/a"), "/work/repos/a", "expand: %NAME%/rest")
    eq(roots.expand("$REPOS_DIR"), "/work/repos", "expand: the bare root")
    eq(roots.expand("${REPOS_DIR}"), "/work/repos", "expand: the bare root, braces")
    eq(roots.expand("$REPOS_DIR/"), "/work/repos/", "expand: a trailing slash the user typed stays")

    -- A root with no environment variable behind it.
    eq(roots.expand("$NVIM_CONFIG_DIR/lua"), "/work/nvim/lua", "expand: NVIM_CONFIG_DIR via source")

    -- "$ in the middle of a path": `vim.fs.normalize` would expand it and produce garbage; a root
    -- is an absolute path, so substituting it mid-string never makes sense.
    eq(
      roots.expand("C:/data/$REPOS_DIR/y"),
      "C:/data/$REPOS_DIR/y",
      "expand: a reference in the middle is left alone"
    )
    eq(roots.expand("x/${REPOS_DIR}"), "x/${REPOS_DIR}", "expand: not at the start -> unchanged")

    -- Unknown / unset / not a reference.
    eq(roots.expand("$NOT_A_ROOT/x"), "$NOT_A_ROOT/x", "expand: unknown name unchanged")
    eq(
      roots.expand("$UNSET_ROOT/x"),
      "$UNSET_ROOT/x",
      "expand: a configured but unset var unchanged"
    )
    eq(roots.expand("$REPOS_DIRX/x"), "$REPOS_DIRX/x", "expand: longer name is another name")
    eq(roots.expand("$REPOS_DIR.bak"), "$REPOS_DIR.bak", "expand: a name must end at a separator")
    eq(roots.expand("${REPOS_DIR}x"), "${REPOS_DIR}x", "expand: braces then non-separator")
    eq(roots.expand("$repos_dir/x"), "$repos_dir/x", "expand: names are case-sensitive on POSIX")
    eq(roots.expand("plain/path"), "plain/path", "expand: a plain path unchanged")
    eq(roots.expand(""), "", "expand: empty string")
    eq(roots.expand(nil), nil, "expand: nil passes through")
    eq(roots.expand(42), 42, "expand: a non-string passes through")

    -- `~`
    -- A Windows home comes back with backslashes; a drive-letter spelling is unified everywhere.
    local home = ((vim.uv or vim.loop).os_homedir():gsub("\\", "/"))
    eq(roots.expand("~/x"), home .. "/x", "expand: ~/rest")
    eq(roots.expand("~"), home, "expand: bare ~")
    eq(roots.expand("~other/x"), "~other/x", "expand: ~user is not ours")

    -- POSIX: a backslash in the rest is a filename character, kept verbatim.
    eq(roots.expand("$REPOS_DIR/a\\b"), "/work/repos/a\\b", "expand: POSIX keeps a backslash")
  end)

  -- Windows spellings. `windows = true` forces them on any runner.
  with_roots({
    windows = true,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "D:\\repos", NVIM_CONFIG_DIR = "c:/Users/Müller/AppData/Local/nvim" },
  }, function()
    eq(roots.expand("$REPOS_DIR\\a\\b.lua"), "D:/repos/a/b.lua", "expand (win): backslash rest")
    eq(roots.expand("%REPOS_DIR%\\a"), "D:/repos/a", "expand (win): %NAME%\\rest")
    eq(roots.expand("%repos_dir%\\a"), "D:/repos/a", "expand (win): names are case-insensitive")
    eq(roots.expand("${repos_dir}/a"), "D:/repos/a", "expand (win): ${name} case-insensitive")
    eq(
      roots.expand("$NVIM_CONFIG_DIR/lua"),
      "C:/Users/Müller/AppData/Local/nvim/lua",
      "expand (win): umlaut in the root, lowercase drive letter normalized"
    )
  end)

  -- ── fold() ────────────────────────────────────────────────────────────────────────────────
  with_roots({
    windows = false,
    vars = { "REPOS_DIR" },
    nvim_config = false,
    extra = { OUTER = "/data", INNER = "/data/inner/deep", SIB = "/repos2" },
    source = { REPOS_DIR = "/repos" },
  }, function()
    eq(roots.fold("/repos/lib.nvim/x.lua"), "$REPOS_DIR/lib.nvim/x.lua", "fold: under a root")
    local folded, name = roots.fold("/repos/lib.nvim")
    eq(folded, "$REPOS_DIR/lib.nvim", "fold: result")
    eq(name, "REPOS_DIR", "fold: second result names the root")
    eq(roots.fold("/repos"), "$REPOS_DIR", "fold: the root itself")
    eq(roots.fold("/repos/"), "$REPOS_DIR", "fold: the root with a trailing slash")
    eq(roots.fold("/repos//lib///x"), "$REPOS_DIR/lib/x", "fold: doubled separators collapsed")

    -- Nested roots: the longest one wins, whatever the registration order.
    eq(roots.fold("/data/inner/deep/f.md"), "$INNER/f.md", "fold: the longest (nested) root wins")
    eq(roots.fold("/data/other/f.md"), "$OUTER/other/f.md", "fold: the outer one when not nested")

    -- A name-prefix sibling is not inside: "/repos2" is not under "/repos".
    eq(roots.fold("/repos2/x"), "$SIB/x", "fold: /repos2 belongs to SIB, not to /repos")
    eq(roots.fold("/repos-extra/x"), "/repos-extra/x", "fold: a name-prefix sibling is not inside")

    -- Not foldable.
    eq(roots.fold("/elsewhere/x"), "/elsewhere/x", "fold: outside every root -> unchanged")
    local _, none = roots.fold("/elsewhere/x")
    eq(none, nil, "fold: no root -> no name")
    eq(roots.fold("relative/x"), "relative/x", "fold: relative path unchanged")
    eq(roots.fold(""), "", "fold: empty string")
    eq(roots.fold(nil), nil, "fold: nil passes through")

    -- POSIX is case-sensitive.
    eq(roots.fold("/REPOS/x"), "/REPOS/x", "fold (posix): case matters")

    -- folder(): the same, resolved once.
    local fold_many = roots.folder()
    eq(fold_many("/repos/a"), "$REPOS_DIR/a", "folder: folds")
    eq(fold_many("/data/inner/deep/a"), "$INNER/a", "folder: longest wins")
  end)

  -- Windows: case-insensitive, backslashes, drive letter case, umlauts. `string.lower` would
  -- leave the "Ü" of an umlaut profile path case-sensitive; `vim.fn.tolower` does not.
  with_roots({
    windows = true,
    vars = { "REPOS_DIR" },
    extra = { HOME_CFG = "C:/Users/Müller/AppData/Local/nvim" },
    nvim_config = false,
    source = { REPOS_DIR = "D:/Repos" },
  }, function()
    eq(roots.fold("d:/repos/x.lua"), "$REPOS_DIR/x.lua", "fold (win): case and drive case ignored")
    eq(
      roots.fold("D:\\REPOS\\lib.nvim\\x.lua"),
      "$REPOS_DIR/lib.nvim/x.lua",
      "fold (win): backslashes"
    )
    eq(roots.fold("D:\\Repos"), "$REPOS_DIR", "fold (win): the root itself, backslash spelling")
    eq(
      roots.fold("c:/users/MÜLLER/appdata/local/nvim/init.lua"),
      "$HOME_CFG/init.lua",
      "fold (win): non-ASCII case folding (vim.fn.tolower, not string.lower)"
    )
    eq(
      roots.fold("D:/Repos/Lib.Nvim/X.lua"),
      "$REPOS_DIR/Lib.Nvim/X.lua",
      "fold (win): the rest keeps its own case"
    )
    eq(roots.fold("E:/repos/x"), "E:/repos/x", "fold (win): another drive is another place")
  end)

  -- UNC roots keep their leading "//" through normalization, on both sides.
  with_roots({
    windows = true,
    nvim_config = false,
    vars = {},
    extra = { SHARE = "\\\\server\\share\\repos" },
  }, function()
    eq(flat(roots.roots()), "SHARE=//server/share/repos", "roots: UNC keeps its leading //")
    eq(roots.fold("//server/share/repos/a"), "$SHARE/a", "fold: UNC path")
    eq(roots.fold("\\\\server\\share\\repos\\a"), "$SHARE/a", "fold: UNC, backslash spelling")
  end)

  -- enable = false: fold/remap off, expand still works.
  with_roots({
    windows = false,
    enable = false,
    nvim_config = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "/repos" },
  }, function()
    eq(roots.enabled(), false, "enabled: reflects the config")
    eq(roots.fold("/repos/x"), "/repos/x", "fold: unchanged when disabled")
    eq(roots.fold("/repos/x", { force = true }), "$REPOS_DIR/x", "fold: force overrides disabled")
    eq(#roots.remap("/other/repos/x"), 0, "remap: nothing when disabled")
    eq(roots.expand("$REPOS_DIR/x"), "/repos/x", "expand: works when disabled")
    eq(#roots.roots(), 1, "roots: independent of enable")
  end)

  -- ── remap(): a path recorded on another machine ───────────────────────────────────────────
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos/casedesk.nvim/docs", "p")
    vim.fn.mkdir(base .. "/nvim/lua", "p")
    vim.fn.mkdir(base .. "/data/repos/nested", "p")
    local fh = assert(io.open(base .. "/repos/casedesk.nvim/docs/a.md", "w"))
    fh:write("x")
    fh:close()
    fh = assert(io.open(base .. "/nvim/lua/init.lua", "w"))
    fh:write("x")
    fh:close()

    with_roots({
      windows = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos", NVIM_CONFIG_DIR = base .. "/nvim" },
    }, function()
      eq(
        table.concat(roots.remap("E:/repos/casedesk.nvim/docs/a.md"), "|"),
        base .. "/repos/casedesk.nvim/docs/a.md",
        "remap: the part after the anchor word is looked up under the local root"
      )
      eq(
        table.concat(roots.remap("C:\\Users\\other\\AppData\\Local\\nvim\\lua\\init.lua"), "|"),
        base .. "/nvim/lua/init.lua",
        "remap (posix): a drive-letter path in backslash spelling can only be a Windows path"
      )
      eq(
        table.concat(roots.remap("C:/Users/other/AppData/Local/nvim/lua/init.lua"), "|"),
        base .. "/nvim/lua/init.lua",
        "remap: NVIM_CONFIG_DIR anchors on 'nvim', whatever drive or home it sat on"
      )
      eq(#roots.remap("E:/repos/casedesk.nvim/missing.md"), 0, "remap: only existing candidates")
      eq(
        #roots.remap(base .. "/repos/casedesk.nvim/docs/a.md"),
        0,
        "remap: the path itself is no candidate"
      )
      eq(#roots.remap("relative/repos/x"), 0, "remap: relative path -> nothing")
      eq(#roots.remap("E:/nothing/here/x"), 0, "remap: no anchor -> nothing")
      eq(#roots.remap(nil), 0, "remap: nil -> nothing")
    end)

    -- Two anchors in one path (".../repos/data/repos/nested"): outermost anchor first, each once.
    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/data/repos" },
    }, function()
      local hits = roots.remap("E:/repos/data/repos/nested")
      eq(#hits, 1, "remap: a candidate that does not exist is dropped, the one that does stays")
      eq(hits[1], base .. "/data/repos/nested", "remap: second anchor resolves")
    end)

    -- Windows spelling on the foreign side: backslashes and a different case of the anchor word.
    with_roots({
      windows = true,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos" },
    }, function()
      eq(
        table.concat(roots.remap("E:\\REPOS\\casedesk.nvim\\docs\\a.md"), "|"),
        base .. "/repos/casedesk.nvim/docs/a.md",
        "remap (win): backslashes and anchor case"
      )
    end)

    vim.fn.delete(base, "rf")
  end

  -- ── status() / json(): readable from outside, health ──────────────────────────────────────
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos", "p")
    with_roots({
      windows = false,
      vars = { "REPOS_DIR", "MISSING_VAR", "GONE_DIR" },
      source = {
        REPOS_DIR = base .. "/repos",
        GONE_DIR = base .. "/does-not-exist",
        NVIM_CONFIG_DIR = base .. "/repos",
      },
    }, function()
      local by_name = {}
      for _, st in ipairs(roots.status()) do
        by_name[st.name] = st
      end
      eq(by_name.REPOS_DIR.problem, nil, "status: an existing root has no problem")
      eq(by_name.REPOS_DIR.exists, true, "status: exists")
      eq(by_name.MISSING_VAR.problem, "unset", "status: an unset variable is reported (health)")
      eq(by_name.GONE_DIR.problem, "missing_dir", "status: a root that points at nothing")
      eq(by_name.GONE_DIR.exists, false, "status: exists = false")

      local doc = vim.json.decode(roots.json())
      eq(doc.version, 1, "json: version")
      eq(doc.windows, false, "json: windows flag")
      eq(#doc.roots, 3, "json: the three usable roots")
      eq(doc.roots[1].name, "REPOS_DIR", "json: roots in roots() order")
      eq(doc.roots[1].root, base .. "/repos", "json: root path")
      eq(doc.roots[1].exists, true, "json: exists")
      eq(doc.roots[2].exists, false, "json: a missing directory stays listed with exists=false")
      eq(#doc.unresolved, 1, "json: the unset name")
      eq(doc.unresolved[1].name, "MISSING_VAR", "json: unresolved name")
      eq(doc.unresolved[1].problem, "unset", "json: unresolved problem")
    end)

    -- An empty result is `[]`, not `{}`: a Rust/Node reader deserializes arrays into lists.
    with_roots({ windows = false, nvim_config = false, vars = {}, source = {} }, function()
      local text = roots.json()
      ok(text:find('"roots":[]', 1, true) ~= nil, "json: empty roots is an array")
      ok(text:find('"unresolved":[]', 1, true) ~= nil, "json: empty unresolved is an array")
    end)
    vim.fn.delete(base, "rf")
  end

  -- ── export_env(): $NVIM_CONFIG_DIR becomes a real variable, never overwritten ─────────────
  do
    local saved = vim.env.NVIM_CONFIG_DIR
    local saved_marker = vim.env.LIB_NVIM_ROOTS_EXPORTED
    local cfg = tmp()
    H.with_stdpath_config(cfg, function()
      roots.setup()
      vim.env.NVIM_CONFIG_DIR = nil
      vim.env.LIB_NVIM_ROOTS_EXPORTED = nil
      eq(roots.export_env(), true, "export_env: sets it when absent")
      eq(vim.env.NVIM_CONFIG_DIR, cfg, "export_env: to stdpath('config')")
      vim.env.NVIM_CONFIG_DIR = "/already/there"
      eq(roots.export_env(), false, "export_env: never overwrites")
      eq(vim.env.NVIM_CONFIG_DIR, "/already/there", "export_env: value kept")

      vim.env.NVIM_CONFIG_DIR = nil
      roots.setup({ source = {} })
      eq(roots.export_env(), false, "export_env: nothing exported under an injected source")
      eq(
        vim.env.NVIM_CONFIG_DIR,
        nil,
        "export_env: the process environment is not the test subject"
      )
      roots.setup()

      vim.g.lib_nvim_roots_no_export = true
      eq(roots.export_env(), false, "export_env: opt-out")
      vim.g.lib_nvim_roots_no_export = nil
    end)
    vim.env.NVIM_CONFIG_DIR = saved
    vim.env.LIB_NVIM_ROOTS_EXPORTED = saved_marker
  end

  -- ── expand_path: the first consumer ───────────────────────────────────────────────────────
  --
  -- Behavior without the registry must not change: variables the registry does not know, a
  -- reference in the middle, an unset variable, `~`.
  vim.env.LIBNVIM_ROOTS_SPEC_VAR = "xyz"
  with_roots({
    windows = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "/work/repos", NVIM_CONFIG_DIR = "/work/nvim" },
  }, function()
    eq(
      expand_path("$NVIM_CONFIG_DIR/lua"),
      "/work/nvim/lua",
      "expand_path: a root without an env var (the gap this module closes)"
    )
    eq(expand_path("${REPOS_DIR}/a"), "/work/repos/a", "expand_path: ${NAME} of a root")
    eq(expand_path("%REPOS_DIR%/a"), "/work/repos/a", "expand_path: %NAME% of a root")
    eq(
      expand_path("$REPOS_DIR/$LIBNVIM_ROOTS_SPEC_VAR/b"),
      "/work/repos/xyz/b",
      "expand_path: after the root, the rest still gets the generic $VAR expansion"
    )
    eq(
      expand_path("$LIBNVIM_ROOTS_SPEC_VAR/a"),
      "xyz/a",
      "expand_path: a plain env var behaves as before"
    )
    eq(
      expand_path("${LIBNVIM_ROOTS_SPEC_VAR}/a"),
      "xyz/a",
      "expand_path: ${VAR} of a plain env var behaves as before"
    )
    eq(
      expand_path("C:/data/$LIBNVIM_ROOTS_SPEC_VAR/y"),
      "C:/data/xyz/y",
      "expand_path: a variable in the middle is expanded as before"
    )
    eq(expand_path("$NOT_SET_ROOTS_VAR/x"), "$NOT_SET_ROOTS_VAR/x", "expand_path: unset stays")
    eq(
      expand_path("$REPOS_DIRX/x"),
      "$REPOS_DIRX/x",
      "expand_path: a longer name is not mistaken for the root"
    )
    ok(expand_path("~/x"):match("^~") == nil, "expand_path: ~ still expands")
    eq(expand_path(""), "", "expand_path: empty string")
    eq(expand_path(nil), nil, "expand_path: nil")

    -- An injected source wins over the real environment: the sandbox case.
    local saved_repos = vim.env.REPOS_DIR
    vim.env.REPOS_DIR = "/the/real/one"
    eq(
      expand_path("$REPOS_DIR/a"),
      "/work/repos/a",
      "expand_path: the registry (here: the injected source) beats the process environment"
    )
    vim.env.REPOS_DIR = saved_repos
  end)
  vim.env.LIBNVIM_ROOTS_SPEC_VAR = nil

  -- ── composer PATH / DIR / FILE: validation and completion ────────────────────────────────
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos/proj/sub", "p")
    local fh = assert(io.open(base .. "/repos/proj/file.txt", "w"))
    fh:write("x")
    fh:close()

    with_roots({
      windows = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos", NVIM_CONFIG_DIR = base .. "/repos/proj" },
    }, function()
      local path_t, dir_t, file_t = argtypes.get("PATH"), argtypes.get("DIR"), argtypes.get("FILE")

      local valid, value = path_t.validate("${REPOS_DIR}/proj")
      eq(valid, true, "PATH: ${NAME} validates")
      eq(value, base .. "/repos/proj", "PATH: ${NAME} expands through the registry")

      valid, value = dir_t.validate("$NVIM_CONFIG_DIR/sub")
      eq(valid, true, "DIR: a root with no env var resolves and is a directory")
      eq(value, base .. "/repos/proj/sub", "DIR: expanded value")
      valid = dir_t.validate("$REPOS_DIR/proj/file.txt")
      eq(valid, false, "DIR: a file is not a directory")

      valid, value = file_t.validate("${NVIM_CONFIG_DIR}/file.txt")
      eq(valid, true, "FILE: ${NAME} of a root with no env var resolves")
      eq(value, base .. "/repos/proj/file.txt", "FILE: expanded value")
      valid = file_t.validate("$REPOS_DIR/proj/nope.txt")
      eq(valid, false, "FILE: a missing file is refused")
      valid = file_t.validate("$NOT_A_ROOT_AT_ALL/file.txt")
      eq(valid, false, "FILE: an unknown root stays literal and is refused")

      -- Completion is handed back in the spelling the user typed.
      local list = dir_t.complete("${REPOS_DIR}/pr")
      eq(
        vim.tbl_contains(list, "${REPOS_DIR}/proj/"),
        true,
        "DIR completion: ${NAME}/ lead completes in the typed spelling"
      )
      list = file_t.complete("$NVIM_CONFIG_DIR/fi")
      eq(
        vim.tbl_contains(list, "$NVIM_CONFIG_DIR/file.txt"),
        true,
        "FILE completion: a root without env var completes (getcompletion alone could not)"
      )
      eq(
        table.concat(path_t.complete("$REP"), "|"),
        "$REPOS_DIR/",
        "PATH completion: a bare $PREFIX completes root names"
      )
      eq(
        table.concat(path_t.complete("$nvim"), "|"),
        "$NVIM_CONFIG_DIR/",
        "PATH completion: root-name completion ignores case"
      )
    end)
    vim.fn.delete(base, "rf")
  end

  -- ── review fixes: each case below pins one defect found in the first version ──────────────

  -- A root has to survive fold -> expand. `MY-ROOT` folded to "$MY-ROOT/x", which `expand` reads
  -- as `$MY` followed by "-ROOT/x" and leaves alone: a path that could be written but never read.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "GOOD_1", "bad-name", "1ST" },
    extra = { ["my root"] = "/a", ["a.b"] = "/b", [7] = "/c" },
    source = { GOOD_1 = "/g", ["bad-name"] = "/x", ["1ST"] = "/y" },
  }, function()
    eq(flat(roots.roots()), "GOOD_1=/g", "names: only a name `expand` can read back is a root")
    local problems = {}
    for _, st in ipairs(roots.status()) do
      problems[#problems + 1] = st.name .. ":" .. tostring(st.problem)
    end
    table.sort(problems)
    eq(
      table.concat(problems, ","),
      "1ST:invalid_name,GOOD_1:missing_dir,a.b:invalid_name,bad-name:invalid_name,my root:invalid_name",
      "names: refused names are reported (health), a non-string key is ignored"
    )
    local folded = roots.fold("/x/file")
    eq(folded, "/x/file", "names: nothing folds into a refused name")
  end)

  -- The first USABLE definition wins. An `extra` function that returns nothing used to shadow the
  -- environment variable of the same name and report the root as unset.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "WORK" },
    extra = {
      WORK = function()
        return nil
      end,
    },
    source = { WORK = "/from/env" },
  }, function()
    eq(
      flat(roots.roots()),
      "WORK=/from/env",
      "precedence: an unusable extra falls through to the var"
    )
    eq(roots.expand("$WORK/x"), "/from/env/x", "precedence: expand sees it too")
    eq(#roots.status(), 1, "precedence: one entry per name")
  end)

  -- Two names for one directory: the earlier one in roots() order wins, not whichever one
  -- table.sort happened to put first among equals. A dozen names, because a sort of two equal
  -- elements happens to be stable and would pass either way.
  do
    local extra = {}
    for i = 1, 12 do
      extra[("N%02d"):format(i)] = "/same/dir"
      -- Roots of other lengths around them, so the sort has to move the equal ones.
      extra[("D%02d"):format(i)] = "/d/" .. ("x"):rep(i)
      extra[("S%02d"):format(i)] = "/s" .. ("y"):rep(13 - i) .. "/dir"
    end
    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "LAST" },
      extra = extra,
      source = { LAST = "/same/dir" },
    }, function()
      eq(roots.fold("/same/dir/f"), "$N01/f", "fold: equal roots -> the earliest name")
      eq(roots.fold("/same/dir"), "$N01", "fold: the root itself, same rule")
    end)
  end

  -- `match` (and so expand_path on every `$VAR`) must not resolve roots it was not asked for: no
  -- user function is run, and the config dir is not asked, for a reference to some other name.
  do
    local calls = 0
    with_roots({
      windows = false,
      vars = { "WANTED" },
      extra = {
        OTHER = function()
          calls = calls + 1
          return "/other"
        end,
        NAMED = function()
          calls = calls + 1
          return "/named"
        end,
      },
      source = { WANTED = "/wanted" },
    }, function()
      eq(roots.expand("$WANTED/x"), "/wanted/x", "lazy: the wanted root resolves")
      eq(roots.expand("$HOME/x"), "$HOME/x", "lazy: an unknown name is left alone")
      eq(calls, 0, "lazy: extra functions of other names are not run")
      eq(roots.expand("$NAMED/x"), "/named/x", "lazy: the wanted extra root resolves")
      eq(calls, 1, "lazy: and only that one ran")
    end)
  end

  -- libuv instead of Vimscript for the environment: a fast event (a uv callback) can resolve a
  -- root. `vim.env` raises E5560 there.
  do
    local saved = vim.env.LIBNVIM_FAST_ROOT
    vim.env.LIBNVIM_FAST_ROOT = "/fast/root"
    roots.setup({ windows = false, vars = { "LIBNVIM_FAST_ROOT" }, nvim_config = false })
    local result
    local timer = (vim.uv or vim.loop).new_timer()
    timer:start(0, 0, function()
      timer:close()
      result = { pcall(roots.expand, "$LIBNVIM_FAST_ROOT/x") }
      result[3] = select(2, pcall(expand_path, "$LIBNVIM_FAST_ROOT/y"))
    end)
    vim.wait(2000, function()
      return result ~= nil
    end)
    roots.setup()
    vim.env.LIBNVIM_FAST_ROOT = saved
    ok(result ~= nil, "fast event: the callback ran")
    eq(result[1], true, "fast event: expand does not raise")
    eq(result[2], "/fast/root/x", "fast event: expand resolves a root")
    eq(result[3], "/fast/root/y", "fast event: expand_path resolves a root")
  end

  -- remap: a recorded path is somebody else's data. `..` must not let a candidate climb out of
  -- the root it is anchored under.
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos/proj", "p")
    vim.fn.mkdir(base .. "/secret", "p")
    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos" },
    }, function()
      eq(#roots.remap("E:/repos/proj"), 1, "remap: the plain path maps")
      eq(#roots.remap("E:/repos/../secret"), 0, "remap: a '..' segment maps to nothing")
      eq(#roots.remap("E:/x/repos/proj/../../../secret"), 0, "remap: nor does a deeper climb")
    end)
    vim.fn.delete(base, "rf")
  end

  -- relative(): the spelling-blind "what is below this root", used to put a completion candidate
  -- back into the spelling the user typed.
  with_roots({
    windows = true,
    nvim_config = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "D:/Repos" },
  }, function()
    eq(
      roots.relative("d:\\repos\\proj\\", "REPOS_DIR"),
      "/proj/",
      "relative (win): other separator, case, trailing"
    )
    eq(roots.relative("D:/Repos", "REPOS_DIR"), "", "relative: the root itself")
    eq(
      roots.relative("D:/Repos/", "REPOS_DIR"),
      "/",
      "relative: the root with a trailing separator"
    )
    eq(
      roots.relative("D:/Repos2/x", "REPOS_DIR"),
      nil,
      "relative: a name-prefix sibling is not below"
    )
    eq(roots.relative("E:/Repos/x", "REPOS_DIR"), nil, "relative: another drive")
    eq(roots.relative("D:/Repos/x", "NOPE"), nil, "relative: an unknown root")
    eq(roots.relative("rel/x", "REPOS_DIR"), nil, "relative: a relative path")
    eq(roots.relative(nil, "REPOS_DIR"), nil, "relative: nil")
  end)

  -- Completion on Windows: `getcompletion` answers in its own spelling (backslashes, the case it
  -- found on disk). A plain prefix test against the root dropped every such candidate.
  with_roots({
    windows = true,
    nvim_config = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "D:/Repos" },
  }, function()
    local dir_t = argtypes.get("DIR")
    H.with_patched(vim.fn, "getcompletion", function()
      return { "d:\\repos\\proj\\", "D:/Repos/other/" }
    end, function()
      eq(
        table.concat(dir_t.complete("${REPOS_DIR}/p"), "|"),
        "${REPOS_DIR}/proj/|${REPOS_DIR}/other/",
        "DIR completion (win): candidates in another separator/case come back in the typed spelling"
      )
    end)
  end)

  -- A backtick in the ROOT's path is as dangerous as one in the lead: it is what getcompletion
  -- is handed after expansion.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = { EVIL = "/tmp/x`touch marker`" },
  }, function()
    local asked = 0
    H.with_patched(vim.fn, "getcompletion", function()
      asked = asked + 1
      return {}
    end, function()
      eq(
        #argtypes.get("DIR").complete("$EVIL/a"),
        0,
        "completion: a backtick in the root completes to nothing"
      )
    end)
    eq(asked, 0, "completion: getcompletion never saw the expanded backtick path")
  end)

  -- ══ second review round ═══════════════════════════════════════════════════════════════════
  --
  -- Every case below pins one defect of the first two versions (see the task
  -- `roots-review-findings`), or one API the plugins that move onto the registry depend on.

  local uv = vim.uv or vim.loop

  ---@param fn fun()
  ---@param needle string  a part of the message
  ---@param msg string
  local function raises(fn, needle, msg)
    local done, err = pcall(fn)
    eq(done, false, msg .. " (raises)")
    ok(
      tostring(err):find(needle, 1, true) ~= nil,
      msg .. " (message names `" .. needle .. "`, got: " .. tostring(err) .. ")"
    )
  end

  --- Set environment variables for `fn` and put them back afterwards, whatever happens.
  ---@param vars table<string, string|false>  false removes the variable
  ---@param fn fun()
  local function with_env(vars, fn)
    local saved = {}
    for name, value in pairs(vars) do
      saved[name] = vim.env[name]
      vim.env[name] = value or nil
    end
    local done, err = pcall(fn)
    for name in pairs(vars) do
      vim.env[name] = saved[name]
    end
    if not done then
      error(err, 0)
    end
  end

  --- Remove a symlink / junction the spec made, and say whether it is really gone. A temp tree
  --- that still holds a link must NOT be deleted recursively: a link to a drive root would take the
  --- drive with it.
  ---@param path string
  ---@return boolean gone
  local function remove_link(path)
    pcall(uv.fs_unlink, path)
    pcall(uv.fs_rmdir, path)
    return uv.fs_lstat(path) == nil
  end

  --- Register a root for the duration of `fn` (registrations survive `setup`, so a leaked one
  --- would show up in every later case).
  ---@param name string
  ---@param value string|fun(): string?
  ---@param fn fun()
  local function with_registered(name, value, fn)
    local off = roots.register(name, value)
    local done, err = pcall(fn)
    off()
    if not done then
      error(err, 0)
    end
  end

  -- ── per-call options: what filetree's markdown_links / path_copy / link_create rely on ───────
  --
  -- `names` and `nvim_config` used to be accepted and silently ignored, which would have turned
  -- three filetree options into no-ops after the migration. `root_of` is the fourth thing filetree
  -- calls. An unknown key raises instead of being ignored.
  with_roots({
    windows = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "/r", FT_ROOT = "/ft", NVIM_CONFIG_DIR = "/cfg" },
  }, function()
    eq(flat(roots.roots()), "REPOS_DIR=/r;NVIM_CONFIG_DIR=/cfg", "opts: the baseline")
    eq(
      flat(roots.roots({ names = { "FT_ROOT", "REPOS_DIR", 5 } })),
      "REPOS_DIR=/r;FT_ROOT=/ft;NVIM_CONFIG_DIR=/cfg",
      "opts.names: after vars; a repeated name stays one root; a non-string is skipped"
    )
    eq(
      flat(roots.roots({ nvim_config = false })),
      "REPOS_DIR=/r",
      "opts.nvim_config = false: drops $NVIM_CONFIG_DIR for this call"
    )

    eq(roots.fold("/ft/x.md"), "/ft/x.md", "opts: an env var that is not configured is no root")
    eq(
      roots.fold("/ft/x.md", { names = { "FT_ROOT" } }),
      "$FT_ROOT/x.md",
      "fold: opts.names adds a root for the call"
    )
    eq(roots.fold("/ft/x.md"), "/ft/x.md", "fold: ... and only for the call")
    eq(
      roots.fold("/cfg/init.lua", { nvim_config = false }),
      "/cfg/init.lua",
      "fold: opts.nvim_config = false"
    )
    eq(roots.fold("/cfg/init.lua"), "$NVIM_CONFIG_DIR/init.lua", "fold: ... and only for the call")

    local fold_many = roots.folder({ names = { "FT_ROOT" } })
    eq(fold_many("/ft/a"), "$FT_ROOT/a", "folder: opts.names")
    eq(fold_many("/r/a"), "$REPOS_DIR/a", "folder: the configured roots stay")

    eq(roots.root_of("/r/lib/x.lua"), "REPOS_DIR", "root_of: the name of the root a path is under")
    eq(roots.root_of("/elsewhere/x.lua"), nil, "root_of: nil outside every root")
    eq(roots.root_of("rel/x.lua"), nil, "root_of: nil for a relative path")
    eq(roots.root_of("/ft/x.md", { names = { "FT_ROOT" } }), "FT_ROOT", "root_of: takes the opts")

    raises(function()
      roots.fold("/r/a", { nmes = { "X" } })
    end, "unknown option `nmes`", "fold: a typo in opts")
    raises(function()
      roots.roots({ force = true })
    end, "unknown option `force`", "roots: force belongs to fold only")
    raises(function()
      roots.folder("names")
    end, "opts must be a table", "folder: opts of the wrong type")
  end)

  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    source = { NVIM_CONFIG_DIR = "/cfg" },
  }, function()
    eq(
      flat(roots.roots({ nvim_config = true })),
      "NVIM_CONFIG_DIR=/cfg",
      "opts.nvim_config = true: adds it where the config left it out"
    )
  end)

  with_roots({
    windows = false,
    enable = false,
    nvim_config = false,
    vars = {},
    source = { FT_ROOT = "/ft" },
  }, function()
    eq(roots.fold("/ft/x", { names = { "FT_ROOT" } }), "/ft/x", "fold: disabled stays disabled")
    eq(
      roots.fold("/ft/x", { names = { "FT_ROOT" }, force = true }),
      "$FT_ROOT/x",
      "fold: force + names, the way `:Filetree copy env_rooted` asks"
    )
  end)

  -- ── register(): a plugin adds a root without erasing the user's setup ────────────────────────
  --
  -- `setup` replaces the configuration, so a second caller wiped the first one's `extra` and
  -- `vars`. `register` is the additive door; it survives `setup`.
  with_registered("PLUG_ROOT", "/plug/root", function()
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { USER_ONE = "/u" },
    }, function()
      eq(
        flat(roots.roots()),
        "USER_ONE=/u;PLUG_ROOT=/plug/root",
        "register: listed after the user's extra roots"
      )
      eq(roots.expand("$PLUG_ROOT/a"), "/plug/root/a", "register: expand")
      eq(roots.fold("/plug/root/a"), "$PLUG_ROOT/a", "register: fold")
      eq(roots.status()[2].kind, "registered", "register: status says where it came from")

      roots.setup({ windows = false, nvim_config = false, vars = {} })
      eq(
        roots.expand("$PLUG_ROOT/a"),
        "/plug/root/a",
        "register: survives a later setup() that replaces the configuration"
      )
    end)
  end)
  with_roots({ windows = false, nvim_config = false, vars = {} }, function()
    eq(#roots.roots(), 0, "register: gone after the unregister function ran")
  end)

  with_registered("DUP", "/from/plugin", function()
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { DUP = "/from/user" },
    }, function()
      eq(flat(roots.roots()), "DUP=/from/user", "register: the user's extra root wins")
    end)
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = {
        DUP = function()
          return nil
        end,
      },
    }, function()
      eq(
        flat(roots.roots()),
        "DUP=/from/plugin",
        "register: ... but an extra root that yields nothing falls through to it"
      )
    end)
  end)

  do
    local first = roots.register("TWICE", "/one")
    local second = roots.register("TWICE", "/two")
    with_roots({ windows = false, nvim_config = false, vars = {} }, function()
      eq(flat(roots.roots()), "TWICE=/two", "register: the same name again replaces")
      first()
      eq(
        flat(roots.roots()),
        "TWICE=/two",
        "register: the stale unregister function of the first one leaves the newer registration"
      )
      second()
      eq(#roots.roots(), 0, "register: the current unregister function removes it")
      eq(roots.unregister("TWICE"), false, "unregister: nothing there -> false")
      roots.register("TWICE", "/three")
      eq(roots.unregister("TWICE"), true, "unregister: removes -> true")
      eq(#roots.roots(), 0, "unregister: gone")
    end)
  end

  raises(function()
    roots.register("bad-name", "/x")
  end, "register", "register: a name `expand` could not read back")
  raises(function()
    roots.register("GOOD_NAME", 5)
  end, "register", "register: a value that is neither path nor function")

  -- ── setup(): validated, copied ───────────────────────────────────────────────────────────────
  --
  -- A wrong type used to fall back to the default without a word (`vars = "REPOS_DIR"` -> the
  -- default list, `windows = "yes"` -> the platform), and a typo in a key (`extras`) was ignored.
  raises(function()
    roots.setup({ vars = "REPOS_DIR" })
  end, "`vars` must be table", "setup: vars as a string")
  raises(function()
    roots.setup({ extra = "x" })
  end, "`extra` must be table", "setup: extra as a string")
  raises(function()
    roots.setup({ windows = "yes" })
  end, "`windows` must be boolean", "setup: windows as a string")
  raises(function()
    roots.setup({ enable = "no" })
  end, "`enable` must be boolean", "setup: enable as a string")
  raises(function()
    roots.setup({ source = 5 })
  end, "`source` must be table or function", "setup: source as a number")
  raises(function()
    roots.setup({ extras = {} })
  end, "unknown option `extras`", "setup: a misspelled key")
  raises(function()
    roots.setup(5)
  end, "cfg must be a table", "setup: cfg as a number")

  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "KEEP" },
    source = { KEEP = "/k" },
  }, function()
    pcall(roots.setup, { vars = "oops" })
    eq(flat(roots.roots()), "KEEP=/k", "setup: a refused call leaves the configuration as it was")
  end)

  do
    local vars = { "A" }
    local extra = { X = "/x" }
    roots.setup({
      windows = false,
      nvim_config = false,
      vars = vars,
      extra = extra,
      source = { A = "/a", B = "/b" },
    })
    vars[#vars + 1] = "B"
    extra.Y = "/y"
    eq(flat(roots.roots()), "X=/x;A=/a", "setup: vars and extra are copied, not aliased")
    roots.setup()
  end

  -- ── case folding that changes the byte length (Windows) ──────────────────────────────────────
  --
  -- `vim.fn.tolower` is not length-preserving: `İ` is 2 bytes and lowers to `i` (1), `ẞ` 3 -> `ß` 2,
  -- `Ⱥ` 2 -> `ⱥ` 3. `fold` and `relative` compared the lowered strings and then took the rest
  -- from the original at an offset of the root's length: a root with such a letter never matched
  -- (a Turkish Windows profile), and a path with one under an ASCII root came back as `$R//x`.
  with_roots({
    windows = true,
    nvim_config = false,
    vars = {},
    extra = {
      TURKISH = "C:/Users/İlker/nvim",
      SHARP = "D:/Straẞe",
      BAR = "D:/Ⱥbc",
      PLAIN = "D:/plainroot",
    },
  }, function()
    eq(
      roots.fold("C:/Users/İlker/nvim/init.lua"),
      "$TURKISH/init.lua",
      "fold (win): a root whose lowercase is SHORTER than itself (İ)"
    )
    eq(
      roots.fold("c:/USERS/İLKER/NVIM/init.lua"),
      "$TURKISH/init.lua",
      "fold (win): ... spelled in another case"
    )
    eq(roots.fold("C:/Users/İlker/nvim"), "$TURKISH", "fold (win): the root itself")
    eq(roots.fold("D:/Straẞe/a"), "$SHARP/a", "fold (win): ẞ, 3 -> 2 bytes")
    eq(roots.fold("D:/Ⱥbc/a"), "$BAR/a", "fold (win): a root whose lowercase is LONGER (Ⱥ)")
    eq(roots.fold("D:/ⱥBC/a/b"), "$BAR/a/b", "fold (win): ... and its lowercase spelling")
    eq(
      roots.fold("D:/PLAİNROOT/x.lua"),
      "$PLAIN/x.lua",
      "fold (win): İ in the PATH under an ASCII root (the rest was cut at the wrong byte: $PLAIN//x.lua)"
    )
    eq(roots.fold("D:/PLAİNROOT"), "$PLAIN", "fold (win): ... and the root itself")
    eq(roots.fold("D:/plainrootX/x"), "D:/plainrootX/x", "fold (win): still a segment boundary")
    eq(
      roots.fold("D:/İ/PLAİNROOT/x"),
      "D:/İ/PLAİNROOT/x",
      "fold (win): a longer prefix before the root is not the root"
    )

    eq(
      roots.relative("c:/users/İLKER/NVIM/sub/x", "TURKISH"),
      "/sub/x",
      "relative (win): the same, for the root that is shorter when lowered"
    )
    eq(
      roots.relative("C:/Users/İlker/nvim/", "TURKISH"),
      "/",
      "relative (win): the root with a trailing separator"
    )
    eq(
      roots.relative("D:/PLAİNROOT/x", "PLAIN"),
      "/x",
      "relative (win): İ in the path under an ASCII root"
    )
    eq(
      roots.relative("D:/Ⱥbc/x", "BAR"),
      "/x",
      "relative (win): a root that is longer when lowered"
    )
  end)

  -- ── a root that is a symlink ─────────────────────────────────────────────────────────────────
  --
  -- On Unix a buffer name is canonical: `~/.config/nvim` -> `~/dotfiles/nvim` opens as the latter.
  -- The root as configured never matched what lies in it. (A junction stands in for the symlink
  -- where creating one needs a privilege.)
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/real/sub", "p")
    local linked = uv.fs_symlink(base .. "/real", base .. "/link", { dir = true, junction = true })
    if linked then
      local real = up(norm(assert(uv.fs_realpath(base .. "/real"))))
      with_roots({
        windows = false,
        nvim_config = false,
        vars = {},
        extra = { LINKED = base .. "/link" },
      }, function()
        eq(
          roots.fold(base .. "/link/sub/f.txt"),
          "$LINKED/sub/f.txt",
          "symlink root: the spelling as configured folds"
        )
        eq(
          roots.fold(real .. "/sub/f.txt"),
          "$LINKED/sub/f.txt",
          "symlink root: so does the canonical path a buffer carries"
        )
        eq(roots.fold(real), "$LINKED", "symlink root: the canonical root itself")
        eq(
          roots.fold(real .. "-other/x"),
          real .. "-other/x",
          "symlink root: a sibling that shares the name prefix is not inside"
        )
        eq(
          roots.root_of(real .. "/sub"),
          "LINKED",
          "symlink root: root_of goes through the same lookup"
        )
      end)
      if remove_link(base .. "/link") then
        vim.fn.delete(base, "rf")
      end
    else
      vim.fn.delete(base, "rf")
    end
  end

  -- ── $NVIM_CONFIG_DIR as an environment variable: stale vs. deliberate ────────────────────────
  --
  -- A Neovim started from inside another one (a terminal, a job) inherits the parent's exported
  -- `NVIM_CONFIG_DIR`; with another `NVIM_APPNAME` that is wrong, and `vim.fn.expand` then
  -- disagreed with the registry. What lib.nvim exported itself is recognised by the marker that
  -- carries the same value; anything else was set by somebody on purpose.
  do
    local cfg = tmp()
    with_env({ NVIM_CONFIG_DIR = false, LIB_NVIM_ROOTS_EXPORTED = false }, function()
      H.with_stdpath_config(cfg, function()
        roots.setup()
        vim.env.NVIM_CONFIG_DIR = "/stale/from/parent"
        vim.env.LIB_NVIM_ROOTS_EXPORTED = "/stale/from/parent"
        eq(roots.export_env(), true, "export_env: refreshes a value lib.nvim itself exported")
        eq(vim.env.NVIM_CONFIG_DIR, cfg, "export_env: ... to the stdpath of THIS instance")
        eq(vim.env.LIB_NVIM_ROOTS_EXPORTED, cfg, "export_env: ... and updates the marker")
        eq(roots.export_env(), false, "export_env: nothing to do once it is right")

        vim.env.NVIM_CONFIG_DIR = "/set/on/purpose"
        vim.env.LIB_NVIM_ROOTS_EXPORTED = "/something/else"
        eq(roots.export_env(), false, "export_env: a value the marker does not vouch for stays")
        eq(vim.env.NVIM_CONFIG_DIR, "/set/on/purpose", "export_env: ... untouched")

        vim.env.NVIM_CONFIG_DIR = "/set/on/purpose"
        vim.env.LIB_NVIM_ROOTS_EXPORTED = nil
        eq(roots.export_env(), false, "export_env: no marker at all: the user's value stays")

        vim.env.NVIM_CONFIG_DIR = ""
        eq(roots.export_env(), true, "export_env: an empty value counts as unset")

        vim.env.NVIM_CONFIG_DIR = nil
        vim.g.lib_nvim_roots_no_export = 1
        eq(roots.export_env(), false, "export_env: the Vimscript spelling of the opt-out (1)")
        vim.g.lib_nvim_roots_no_export = nil

        -- health: the registry and the environment disagree (an absolute path on this host too: a
        -- drive-less one is no root on Windows)
        local env_says = cfg .. "-env-says-otherwise"
        vim.env.NVIM_CONFIG_DIR = env_says
        vim.env.LIB_NVIM_ROOTS_EXPORTED = nil
        local entry
        for _, st in ipairs(roots.status()) do
          if st.kind == "nvim_config" then
            entry = st
          end
        end
        eq(entry.root, cfg, "status: the root is stdpath('config') whatever the environment says")
        eq(entry.env, env_says, "status: ... and says what the environment holds instead")
        vim.env.NVIM_CONFIG_DIR = cfg
        for _, st in ipairs(roots.status()) do
          if st.kind == "nvim_config" then
            eq(st.env, nil, "status: no `env` when both agree")
          end
        end
      end)
    end)
  end

  -- ── a cold process, from a fast event ────────────────────────────────────────────────────────
  --
  -- The README promises that `expand`/`fold`/... work in a `vim.uv` callback. The platform check
  -- read `vim.env.OS` on Linux/macOS (E5560 on the very first call). This spec's own process has
  -- long since cached the platform, so it takes a fresh Neovim; the child poses as Linux so the
  -- environment-variable fallback is reached on any host.
  local repo = norm(vim.fn.getcwd())

  --- Run a Neovim child on a script; returns the result of `vim.system`.
  ---@param source string  the script
  ---@param extra_args? string[]
  ---@param env? table<string, string>
  local function child(source, extra_args, env)
    local script = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(vim.split(source, "\n", { plain = true }), script)
    local argv = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE" }
    vim.list_extend(argv, extra_args or {})
    vim.list_extend(argv, { "-l", script, repo })
    local res = vim.system(argv, { text = true, env = env }):wait(30000)
    vim.fn.delete(script)
    return res
  end

  do
    local res = child(
      [==[
local repo = arg[1]
vim.opt.rtp:append(repo)
local uv = vim.uv
uv.os_uname = function()
  return { sysname = "Linux" }
end
local roots = require("lib.nvim.fs.roots")
roots.setup({ nvim_config = false, vars = { "COLD_ROOT" }, source = { COLD_ROOT = "/cold/root" } })
local out
local timer = uv.new_timer()
timer:start(0, 0, function()
  timer:close()
  out = { pcall(function()
    return roots.expand("$COLD_ROOT/x") .. "|" .. roots.fold("/cold/root/y") .. "|" .. tostring(roots.export_env())
  end) }
end)
vim.wait(5000, function()
  return out ~= nil
end)
io.stdout:write(tostring(out[1]), ":", tostring(out[2]), "\n")
]==],
      nil,
      { OS = "Plan9" }
    ) -- on a Windows host `OS` would still say so
    eq(res.code, 0, "cold fast event: the child ran (" .. tostring(res.stderr) .. ")")
    eq(
      vim.trim(res.stdout),
      "true:/cold/root/x|$COLD_ROOT/y|false",
      "cold fast event: expand, fold and export_env answer instead of raising E5560"
    )
  end

  -- Non-ASCII case folding calls `vim.fn.tolower`, which a fast event may (unlike `vim.env`);
  -- an export is a Vimscript call it may not, and has nothing to do there.
  do
    local saved = vim.env.NVIM_CONFIG_DIR
    vim.env.NVIM_CONFIG_DIR = nil
    roots.setup({ windows = true, nvim_config = false, vars = {}, extra = { UML = "D:/Ü" } })
    local result
    local timer = uv.new_timer()
    timer:start(0, 0, function()
      timer:close()
      local fold_ok, fold_res = pcall(roots.fold, "d:/ü/x")
      local rel_ok, rel_res = pcall(roots.relative, "d:/ü/x", "UML")
      local export_ok, export_res = pcall(roots.export_env)
      result = {
        fold = { fold_ok, fold_res },
        relative = { rel_ok, rel_res },
        export = { export_ok, export_res },
      }
    end)
    vim.wait(2000, function()
      return result ~= nil
    end)
    roots.setup()
    ok(result ~= nil, "fast event (win): the callback ran")
    eq(result.fold[1], true, "fast event (win): fold does not raise on a non-ASCII path")
    eq(result.fold[2], "$UML/x", "fast event (win): ... and folds case-insensitively, Ü and all")
    eq(result.relative[1], true, "fast event (win): relative does not raise on a non-ASCII path")
    eq(result.relative[2], "/x", "fast event (win): ... and still answers")
    eq(result.export[1], true, "fast event: export_env does not raise")
    eq(result.export[2], false, "fast event: export_env exports nothing there")
    eq(vim.env.NVIM_CONFIG_DIR, nil, "fast event: export_env set nothing")
    vim.env.NVIM_CONFIG_DIR = saved
  end

  -- ── `~` ──────────────────────────────────────────────────────────────────────────────────────
  --
  -- The home directory went in unchecked: `HOME=/home/u/` gave `/home/u//x`, and `HOME=/` turned
  -- `~/repos` into `//repos`, which is a UNC root.
  do
    local base = tmp()
    with_env({ HOME = base .. "/", USERPROFILE = base .. "/" }, function()
      with_roots({
        windows = false,
        nvim_config = false,
        vars = {},
        extra = { VIAHOME = "~/notes" },
      }, function()
        eq(roots.expand("~/x"), base .. "/x", "~: a trailing slash of the home is not doubled")
        eq(roots.expand("~"), base, "~: the bare tilde, no trailing slash")
        eq(flat(roots.roots()), "VIAHOME=" .. base .. "/notes", "~: the same in a root value")
      end)
    end)
    -- A home of "/" is something libuv only answers on POSIX (a container running as root with
    -- HOME=/); on Windows it reports no home at all, and there is nothing to pin.
    with_env({ HOME = "/", USERPROFILE = "/" }, function()
      if uv.os_homedir() ~= "/" then
        return
      end
      with_roots({
        windows = false,
        nvim_config = false,
        vars = {},
        extra = { VIAHOME = "~/repos" },
      }, function()
        eq(roots.expand("~/repos"), "/repos", "~ (home is /): not //repos")
        eq(roots.expand("~"), "/", "~ (home is /): the bare tilde is the root")
        eq(flat(roots.roots()), "VIAHOME=/repos", "~ (home is /): a root value is not a UNC path")
      end)
    end)
  end

  -- ── separators: a backslash is one only where it is one ──────────────────────────────────────
  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "/work/repos" },
  }, function()
    eq(
      roots.expand("$REPOS_DIR\\a"),
      "$REPOS_DIR\\a",
      "expand (posix): `\\` does not end the name -- that is a file called `$REPOS_DIR\\a`"
    )
    eq(roots.expand("%REPOS_DIR%\\a"), "%REPOS_DIR%\\a", "expand (posix): nor after %NAME%")
    eq(roots.expand("~\\a"), "~\\a", "expand (posix): nor after ~")
    eq(roots.match("$REPOS_DIR\\a"), nil, "match (posix): not a reference")
    eq(roots.expand("$REPOS_DIR/a\\b"), "/work/repos/a\\b", "expand (posix): the rest keeps it")
    eq(
      roots.relative("/work/repos/x\\", "REPOS_DIR"),
      "/x\\",
      'relative (posix): a trailing backslash is part of the name (was "/x\\\\/")'
    )
    eq(
      roots.relative("/work/repos/x/", "REPOS_DIR"),
      "/x/",
      "relative (posix): a trailing slash still counts"
    )
  end)

  -- ── lexical clean-up of paths and root values ────────────────────────────────────────────────
  --
  -- `fold`/`relative` were purely textual: `/repos/../etc/passwd` counted as inside `/repos`. And
  -- a root value with `.`/`..` stayed as written, so `fold` of the path it names never matched.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "REPOS_DIR" },
    extra = { DOTS = "/a/b/../c", UP = "/x/../../y", ABOVE = "/a/./d/" },
    source = { REPOS_DIR = "/repos" },
  }, function()
    eq(
      flat(roots.roots()),
      "ABOVE=/a/d;DOTS=/a/c;UP=/y;REPOS_DIR=/repos",
      "roots: . and .. in a root value are resolved; .. cannot climb above the filesystem root"
    )
    eq(roots.fold("/a/c/x"), "$DOTS/x", "fold: a path under the root a `..` value names")
    eq(
      roots.fold("/repos/../etc/passwd"),
      "/repos/../etc/passwd",
      "fold: .. leaves the root -> not inside, the path comes back as it was given"
    )
    eq(roots.fold("/repos/a/../b"), "$REPOS_DIR/b", "fold: .. that stays inside")
    eq(roots.fold("/repos/./x"), "$REPOS_DIR/x", "fold: a . segment")
    eq(roots.fold("/repos/.."), "/repos/..", "fold: the parent of a root is no root")
    eq(roots.relative("/repos/../etc", "REPOS_DIR"), nil, "relative: .. leaves the root")
    eq(roots.relative("/repos/a/../b", "REPOS_DIR"), "/b", "relative: .. that stays inside")
    eq(roots.expand("$REPOS_DIR/a/../b"), "/repos/a/../b", "expand: the rest is kept verbatim")
  end)

  -- `//a/b` is `/a/b` on POSIX; a UNC path only where the platform has them, or when it was
  -- spelled with backslashes (which only Windows does).
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = { A = "/a", DOUBLE = "//d/e", BSL = "\\\\srv\\share\\r" },
  }, function()
    eq(roots.fold("//a/b"), "$A/b", "fold (posix): a leading // is not a UNC prefix")
    eq(
      flat(roots.roots()),
      "A=/a;BSL=//srv/share/r;DOUBLE=/d/e",
      "roots (posix): // collapses; a backslash UNC spelling is kept as UNC"
    )
    eq(roots.fold("\\\\srv\\share\\r\\x"), "$BSL/x", "fold (posix): the backslash UNC spelling")
  end)
  with_roots({
    windows = true,
    nvim_config = false,
    vars = {},
    extra = { UNC = "//srv/share/r", SHARE = "//srv/share" },
  }, function()
    eq(roots.fold("//srv/share/r/x"), "$UNC/x", "fold (win): a // UNC path")
    eq(
      roots.fold("//srv/share/r/../../x"),
      "$SHARE/x",
      "fold (win): .. stops at the share, it does not reach `//srv`"
    )
    eq(roots.fold("//srv/share/../../..//y"), "$SHARE/y", "fold (win): nor climb above it")
  end)

  -- ── a NUL byte ───────────────────────────────────────────────────────────────────────────────
  --
  -- `fs_stat` stops at a NUL, so a candidate was checked at one path and returned as another;
  -- on Windows `vim.fn.tolower` raised E976 for a non-ASCII path that held one.
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos/proj", "p")
    with_roots({
      windows = true,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      extra = { BADROOT = "D:/a\0b" },
      source = { REPOS_DIR = base .. "/repos" },
    }, function()
      eq(roots.fold("D:/Ü\0x"), "D:/Ü\0x", "fold (win): a NUL + non-ASCII path does not raise")
      eq(roots.relative("D:/Ü\0x", "REPOS_DIR"), nil, "relative (win): nor does it")
      eq(#roots.remap("E:/repos/proj\0junk"), 0, "remap: a NUL path maps to nothing")
      eq(#roots.remap("E:/repos/proj"), 1, "remap: the same path without it maps")
      local by_name = {}
      for _, st in ipairs(roots.status()) do
        by_name[st.name] = st
      end
      eq(by_name.BADROOT.problem, "invalid_path", "status: a root with a NUL byte")
    end)
    vim.fn.delete(base, "rf")
  end

  -- ── remap ────────────────────────────────────────────────────────────────────────────────────
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos/casedesk.nvim/docs", "p")
    vim.fn.mkdir(base .. "/repos/proj", "p")
    vim.fn.mkdir(base .. "/data/repos/x/repos/y", "p")
    vim.fn.mkdir(base .. "/data/repos/y", "p")
    vim.fn.mkdir(base .. "/other/place", "p")
    local fh = assert(io.open(base .. "/repos/casedesk.nvim/docs/a.md", "w"))
    fh:write("x")
    fh:close()
    fh = assert(io.open(base .. "/afile", "w"))
    fh:write("x")
    fh:close()

    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos" },
    }, function()
      eq(
        table.concat(roots.remap("E:/repos"), "|"),
        base .. "/repos",
        "remap: the recorded root itself maps to the local root"
      )
      eq(
        table.concat(roots.remap("E:/repos/./casedesk.nvim/./docs/a.md"), "|"),
        base .. "/repos/casedesk.nvim/docs/a.md",
        "remap: . segments are dropped, not carried into the candidate"
      )
      eq(
        table.concat(roots.remap("E:/repos/proj/../casedesk.nvim/docs/a.md"), "|"),
        base .. "/repos/casedesk.nvim/docs/a.md",
        "remap: a .. that stays below the anchor is resolved (it used to map to nothing)"
      )
      eq(#roots.remap("E:/repos/../etc/x"), 0, "remap: a .. that leaves the anchor maps to nothing")
      eq(
        table.concat(roots.remap("E:/Repos/casedesk.nvim/docs/a.md"), "|"),
        base .. "/repos/casedesk.nvim/docs/a.md",
        "remap: a Windows path's anchor word compares case-insensitively on a POSIX machine"
      )
      eq(
        #roots.remap("/h/Repos/casedesk.nvim/docs/a.md"),
        0,
        "remap: ... a POSIX path's anchor stays case-sensitive"
      )
    end)

    -- Two anchors in one path: the outermost one first (the longest rest), each candidate once.
    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/data/repos" },
    }, function()
      eq(
        table.concat(roots.remap("E:/repos/x/repos/y"), "|"),
        base .. "/data/repos/x/repos/y|" .. base .. "/data/repos/y",
        "remap: outermost anchor first (the order the docs promise), both existing candidates"
      )
    end)

    -- Two names for one directory must not give the same candidate twice.
    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      extra = { ALIAS = base .. "/repos" },
      source = { REPOS_DIR = base .. "/repos" },
    }, function()
      eq(
        table.concat(roots.remap("E:/repos/proj"), "|"),
        base .. "/repos/proj",
        "remap: one candidate per directory, however many names point at it"
      )
    end)

    -- `enable = false` with a path that WOULD map: the earlier case used a path that matched
    -- nothing either way, so it passed with the switch ignored.
    with_roots({
      windows = false,
      enable = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos" },
    }, function()
      eq(#roots.remap("E:/repos/proj"), 0, "remap: nothing while disabled, though it would map")
    end)

    -- A root that points at a file is not a usable directory.
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { FILEROOT = base .. "/afile", DIRROOT = base .. "/other" },
    }, function()
      local by_name = {}
      for _, st in ipairs(roots.status()) do
        by_name[st.name] = st
      end
      eq(by_name.FILEROOT.exists, false, "status: a root that is a file does not exist as a dir")
      eq(by_name.FILEROOT.problem, "missing_dir", "status: ... and is reported as such")
      eq(by_name.DIRROOT.exists, true, "status: a directory does")
    end)
    vim.fn.delete(base, "rf")
  end

  -- ── a root function that asks the registry ───────────────────────────────────────────────────
  --
  -- A function calling back into the registry recursed until the stack gave out (about 1800
  -- frames, each one re-evaluating everything). A definition now counts as busy while it runs;
  -- asking about ANOTHER root works, asking about itself finds nothing.
  do
    local self_calls = 0
    with_roots({
      windows = false,
      nvim_config = false,
      vars = { "BASE", "SHARED" },
      extra = {
        GOOD = function()
          return roots.expand("$BASE/sub")
        end,
        SELF = function()
          self_calls = self_calls + 1
          return roots.expand("$SELF/x")
        end,
        CYC1 = function()
          return roots.expand("$CYC2/x")
        end,
        CYC2 = function()
          return roots.expand("$CYC1/y")
        end,
        NOTES = "$BASE/notes",
        SHARED = "$SHARED/more",
        PARENT = "/par",
        KID = "$PARENT/kid",
        KIDFN = function()
          return roots.expand("${PARENT}/fn")
        end,
      },
      source = { BASE = "/base", SHARED = "/shared" },
    }, function()
      eq(
        flat(roots.roots()),
        "GOOD=/base/sub;KID=/par/kid;KIDFN=/par/fn;NOTES=/base/notes;PARENT=/par;SHARED=/shared/more;BASE=/base",
        "recursion: a root built on another works, however the other is defined (PARENT is no env var)"
      )
      eq(self_calls, 1, "recursion: a function that asks about itself runs once")
      local problems = {}
      for _, st in ipairs(roots.status()) do
        if st.problem then
          problems[st.name] = st.problem .. ":" .. tostring(st.detail)
        end
      end
      eq(problems.SELF, "unresolved_var:SELF", "recursion: the self-reference is reported")
      eq(problems.CYC1, "unresolved_var:CYC2", "recursion: a cycle ends, first half")
      eq(problems.CYC2, "unresolved_var:CYC1", "recursion: a cycle ends, second half")
    end)
  end

  -- ── why a root has no value ──────────────────────────────────────────────────────────────────
  --
  -- A function that raised, a value of the wrong type and `$UNSET/notes` were all reported as
  -- "unset" or "not_absolute", which sends the reader looking in the wrong place.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = {
      BOOM = function()
        error("kaboom", 0)
      end,
      NUM = 5,
      UNSETVAR = "$NO_SUCH_VARIABLE_ANYWHERE/notes",
      REL = "some/dir",
      NOTHING = function()
        return nil
      end,
      BROAD = "/",
    },
  }, function()
    local by_name = {}
    for _, st in ipairs(roots.status()) do
      by_name[st.name] = st
    end
    eq(by_name.BOOM.problem, "error", "problem: a function that raised")
    eq(by_name.BOOM.detail, "kaboom", "problem: ... says what it raised")
    eq(by_name.NUM.problem, "bad_type", "problem: a number")
    eq(by_name.NUM.detail, "number", "problem: ... says its type")
    eq(by_name.UNSETVAR.problem, "unresolved_var", "problem: a value starting with an unset $VAR")
    eq(by_name.UNSETVAR.detail, "NO_SUCH_VARIABLE_ANYWHERE", "problem: ... names the variable")
    eq(by_name.REL.problem, "not_absolute", "problem: a relative value")
    eq(by_name.NOTHING.problem, "unset", "problem: a function that returns nothing")
    eq(by_name.BROAD.problem, "too_broad", "problem: the filesystem root")
  end)

  -- A source that raises is the same as no value.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "A" },
    source = function()
      error("no source today")
    end,
  }, function()
    eq(#roots.roots(), 0, "source: a function that raises gives no roots, and does not raise")
    eq(roots.status()[1].problem, "unset", "source: ... the name is reported as unset")
  end)

  -- ── json ─────────────────────────────────────────────────────────────────────────────────────
  with_roots({
    windows = true,
    nvim_config = false,
    vars = {},
    extra = {
      FINE = "D:/fine",
      LATIN = "D:/bad/\255\254dir",
      BOOM = function()
        error("bad \255 byte", 0)
      end,
    },
  }, function()
    local text = roots.json()
    local doc = vim.json.decode(text)
    eq(doc.windows, true, "json: the windows flag follows the configuration")
    local names = {}
    for _, r in ipairs(doc.roots) do
      names[#names + 1] = r.name
    end
    eq(table.concat(names, ","), "FINE", "json: a root that is not valid UTF-8 is not listed")
    local problems = {}
    for _, u in ipairs(doc.unresolved) do
      problems[u.name] = u.problem
    end
    eq(problems.LATIN, "invalid_encoding", "json: ... it is reported as unresolved instead")
    eq(problems.BOOM, "error", "json: an error is reported with its problem")
    eq(
      require("lib.lua.strings.safe").utf8(text),
      text,
      "json: the whole document is valid UTF-8 (a strict reader refuses the lot otherwise)"
    )
  end)

  -- ── the outside world: a child Neovim reading the roots, and the startup hook ───────────────
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos", "p")
    local res = vim
      .system({
        vim.v.progpath,
        "-n",
        "-i",
        "NONE",
        "--headless",
        "-u",
        "NONE",
        "--cmd",
        "lua vim.opt.rtp:append(vim.env.LIBNVIM_ROOTS_REPO)",
        "-c",
        "lua require('lib.nvim.fs.roots').print_json()",
        "-c",
        "qa",
      }, {
        text = true,
        env = { LIBNVIM_ROOTS_REPO = repo, REPOS_DIR = base .. "/repos" },
      })
      :wait(30000)
    eq(res.code, 0, "print_json: the child exited cleanly (" .. tostring(res.stderr) .. ")")
    local lines = vim.split(vim.trim(res.stdout), "\n", { plain = true })
    eq(#lines, 1, "print_json: exactly one line on stdout, got: " .. res.stdout)
    local doc = vim.json.decode(lines[1])
    eq(doc.version, 1, "print_json: the document is JSON")
    local repos
    for _, r in ipairs(doc.roots) do
      if r.name == "REPOS_DIR" then
        repos = r
      end
    end
    ok(repos ~= nil, "print_json: REPOS_DIR is listed")
    eq(repos.root, up(norm(base .. "/repos")), "print_json: ... with the root from the environment")
    eq(repos.exists, true, "print_json: ... which exists")
    vim.fn.delete(base, "rf")
  end

  -- plugin/lib_roots.lua: `-u NORC` loads plugins (from the runtimepath the `--cmd` extended).
  do
    local function startup(extra_args)
      local args = {
        vim.v.progpath,
        "-n",
        "-i",
        "NONE",
        "--headless",
        "-u",
        "NORC",
        "--cmd",
        "lua vim.opt.rtp:append(vim.env.LIBNVIM_ROOTS_REPO)",
      }
      vim.list_extend(args, extra_args)
      vim.list_extend(args, {
        "-c",
        "lua io.stdout:write(vim.env.NVIM_CONFIG_DIR or '<unset>', '|', vim.fn.stdpath('config'), '\\n')",
        "-c",
        "qa",
      })
      local res = vim
        .system(args, {
          text = true,
          env = { LIBNVIM_ROOTS_REPO = repo, NVIM_CONFIG_DIR = "" },
        })
        :wait(30000)
      return res.code, vim.trim(res.stdout or ""), res.stderr
    end

    local code, out, err = startup({})
    eq(code, 0, "startup: the child exited cleanly (" .. tostring(err) .. ")")
    local exported, config = out:match("^(.-)|(.*)$")
    ok(config ~= nil and config ~= "", "startup: the child printed its stdpath: " .. out)
    eq(exported, config, "startup hook: $NVIM_CONFIG_DIR is exported at startup")

    code, out = startup({ "--cmd", "let g:lib_nvim_roots_no_export = 1" })
    eq(code, 0, "startup (opt-out): the child exited cleanly")
    local kept = out:match("^(.-)|")
    ok(kept == "" or kept == "<unset>", "startup hook: the opt-out is honoured (" .. out .. ")")
  end

  -- ── :checkhealth lib ─────────────────────────────────────────────────────────────────────────
  do
    local lines = {}
    local function recorder(kind)
      return function(msg)
        lines[#lines + 1] = kind .. ": " .. tostring(msg)
      end
    end
    local saved = {}
    local kinds = { "start", "ok", "warn", "error", "info" }
    for _, kind in ipairs(kinds) do
      saved[kind] = vim.health[kind]
      vim.health[kind] = recorder(kind)
    end
    package.loaded["lib.health"] = nil
    local cfg = tmp()
    local base = tmp()
    vim.fn.mkdir(base .. "/there", "p")
    local done, err = pcall(function()
      with_env({ NVIM_CONFIG_DIR = "/environment/says/otherwise" }, function()
        H.with_stdpath_config(cfg, function()
          roots.setup({
            windows = false,
            vars = { "HEALTH_UNSET" },
            extra = {
              THERE = base .. "/there",
              GONE = base .. "/gone",
              BOOM = function()
                error("kaboom", 0)
              end,
              NUM = 5,
              UNSETVAR = "$NO_SUCH_VARIABLE_ANYWHERE/x",
              BROAD = "/",
              REL = "rel/dir",
            },
          })
          require("lib.health").check_roots()
        end)
      end)
    end)
    roots.setup()
    for _, kind in ipairs(kinds) do
      vim.health[kind] = saved[kind]
    end
    package.loaded["lib.health"] = nil
    vim.fn.delete(base, "rf")
    if not done then
      error(err, 0)
    end

    local text = table.concat(lines, "\n")
    for _, needle in ipairs({
      "start: lib.nvim: named roots",
      "warn: $HEALTH_UNSET is not set",
      "ok: $THERE = " .. base .. "/there",
      "warn: $GONE points at a directory that does not exist",
      "warn: $BOOM: its function raised: kaboom",
      "warn: $NUM: the value is a number",
      "warn: $UNSETVAR: $NO_SUCH_VARIABLE_ANYWHERE/x starts with `NO_SUCH_VARIABLE_ANYWHERE`",
      "warn: $BROAD is the filesystem root or a whole drive",
      "warn: $REL is not an absolute path: rel/dir",
      "warn: $NVIM_CONFIG_DIR in the environment is /environment/says/otherwise, but stdpath('config') is "
        .. cfg,
    }) do
      ok(text:find(needle, 1, true) ~= nil, "health: reports `" .. needle .. "`\n" .. text)
    end
    eq(text:find("error:", 1, true), nil, "health: a problem root is a warning, never an error")
  end

  -- ══ adversarial review of round 2 ═════════════════════════════════════════════════════════
  --
  -- Each case reproduces a finding of the reviewer that attacked the second-round code.

  -- ── remap: the order promised in the docs, across roots; and bounded work ───────────────────
  --
  -- The result was root-major: a root whose folder name matches a DEEPER segment came out ahead of
  -- one that matches an outer one, so "outermost anchor first" held only inside one root. And a
  -- recorded path of n segments that all equal the anchor word cost O(n²) per root (4000 anchors:
  -- about a second), for data that comes from another machine.
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/m1/outer/inner/deep", "p")
    vim.fn.mkdir(base .. "/m2/outer/inner/deep", "p")
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { A_INNER = base .. "/m1/outer/inner", B_OUTER = base .. "/m2/outer" },
    }, function()
      eq(
        table.concat(roots.remap("/other/machine/outer/inner/deep"), "|"),
        base .. "/m2/outer/inner/deep|" .. base .. "/m1/outer/inner/deep",
        "remap: outermost anchor first ACROSS roots (B_OUTER matches `outer`, A_INNER only `inner`)"
      )
    end)
    vim.fn.delete(base, "rf")

    vim.fn.mkdir(base .. "/repos", "p")
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { R = base .. "/repos" },
    }, function()
      local stats = 0
      local real_stat = uv.fs_stat
      H.with_patched(uv, "fs_stat", function(...)
        stats = stats + 1
        return real_stat(...)
      end, function()
        roots.remap("/x/" .. ("repos/"):rep(600))
        ok(stats <= 64, "remap: at most 64 candidates are looked up, not one per anchor: " .. stats)

        stats = 0
        eq(
          #roots.remap("/x/" .. ("repos/"):rep(1000)),
          0,
          "remap: a path over 4096 bytes maps to nothing"
        )
        eq(stats, 0, "remap: ... without touching the filesystem")
      end)
      eq(#roots.remap("/x/repos"), 1, "remap: an ordinary path still maps")
    end)
    vim.fn.delete(base, "rf")
  end

  -- ── fold on a path no root matches: no stat chain per call ──────────────────────────────────
  --
  -- `fold` builds its roots on every call, and the symlink fallback stat'ed each of them for every
  -- path that matched nothing (3 roots, 1000 folds: 3000 `realpath` calls; a dead network share
  -- blocked a fold for over a second). It is cached for a few seconds, and Windows -- where buffer
  -- names are not canonicalised -- does not look at all.
  do
    local calls = 0
    local real_realpath = uv.fs_realpath
    local function counting(fn)
      calls = 0
      H.with_patched(uv, "fs_realpath", function(...)
        calls = calls + 1
        return real_realpath(...)
      end, fn)
    end
    local extra = { RPA = "/rp-unique/a", RPB = "/rp-unique/b", RPC = "/rp-unique/c" }
    with_roots({ windows = false, nvim_config = false, vars = {}, extra = extra }, function()
      counting(function()
        for _ = 1, 200 do
          roots.fold("/elsewhere/x.lua")
        end
      end)
      ok(calls <= 3, "fold: realpath of a root is looked up once, not per call: " .. calls)
    end)
    -- other root paths than above: the answer for those is cached by now, which would hide a call
    local win_extra = { RPA = "D:/rp-unique-win/a", RPB = "D:/rp-unique-win/b" }
    with_roots({ windows = true, nvim_config = false, vars = {}, extra = win_extra }, function()
      counting(function()
        roots.fold("D:/elsewhere/x.lua")
      end)
      eq(
        #roots.roots(),
        2,
        "fold (win): the roots exist (a drive-less one would make this vacuous)"
      )
      eq(calls, 0, "fold (win): no realpath at all")
    end)
  end

  -- A root that is a link to the filesystem root / a whole drive would fold every path: the
  -- `too_broad` rule has to hold for the resolved spelling as well.
  do
    local base = tmp()
    vim.fn.mkdir(base, "p")
    local fs_root = base:match("^%a:") and (base:sub(1, 2) .. "/") or "/"
    if uv.fs_symlink(fs_root, base .. "/toroot", { dir = true, junction = true }) then
      with_roots({
        windows = false,
        nvim_config = false,
        vars = {},
        extra = { LINKROOT = base .. "/toroot" },
      }, function()
        local elsewhere = fs_root .. "definitely-not-below-linkroot/x"
        eq(roots.fold(elsewhere), elsewhere, "symlink root to the filesystem root folds nothing")
        eq(
          roots.fold(base .. "/toroot/y"),
          "$LINKROOT/y",
          "... the spelling as configured still does"
        )
      end)
      if remove_link(base .. "/toroot") then
        vim.fn.delete(base, "rf")
      end
    else
      vim.fn.delete(base, "rf")
    end
  end

  -- ── a root function that yields ──────────────────────────────────────────────────────────────
  --
  -- The "busy" mark of a definition was global: a function that yielded (an async task) and was
  -- never resumed left its name busy for good -- no root of that name again, not even after
  -- `setup` or `register`, and nothing in `status()` or health said why.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = {
      WORK = function()
        coroutine.yield()
        return "/work"
      end,
    },
  }, function()
    local co = coroutine.create(function()
      return roots.expand("$WORK/x")
    end)
    coroutine.resume(co) -- parked inside WORK's function, never resumed
    roots.setup({ windows = false, nvim_config = false, vars = {}, extra = { WORK = "/work" } })
    eq(roots.expand("$WORK/x"), "/work/x", "yield: a parked evaluation does not block the name")
    eq(flat(roots.roots()), "WORK=/work", "yield: ... nor the list of roots")
  end)

  -- ── NVIM_CONFIG_DIR through `vars` / `opts.names` ────────────────────────────────────────────
  --
  -- The root is stdpath("config") because the environment variable can be stale. A plugin with an
  -- option listing "all my env roots" (or a user doing the same in `vars`) brought the stale one
  -- back ahead of it.
  do
    local cfg = tmp()
    with_env({ NVIM_CONFIG_DIR = "C:/stale/inherited" }, function()
      H.with_stdpath_config(cfg, function()
        with_roots({ windows = false, vars = { "NVIM_CONFIG_DIR" } }, function()
          eq(flat(roots.roots()), "NVIM_CONFIG_DIR=" .. cfg, "vars: stdpath wins over the variable")
          eq(
            flat(roots.roots({ names = { "NVIM_CONFIG_DIR" } })),
            "NVIM_CONFIG_DIR=" .. cfg,
            "opts.names: ... also when a call lists it"
          )
        end)
        with_roots(
          { windows = false, nvim_config = false, vars = { "NVIM_CONFIG_DIR" } },
          function()
            eq(
              flat(roots.roots()),
              "NVIM_CONFIG_DIR=C:/stale/inherited",
              "vars: without nvim_config the variable the user asked for is used"
            )
          end
        )
      end)
    end)
  end

  -- ── register: identity, and names on Windows ────────────────────────────────────────────────
  --
  -- The function `register` returns compared by VALUE: two plugins registering the same string
  -- removed each other's root. And on Windows `Notes` / `NOTES` are one name but two keys.
  do
    local off_a = roots.register("SHARED_ROOT", "/data/shared")
    local off_b = roots.register("SHARED_ROOT", "/data/shared")
    with_roots({ windows = false, nvim_config = false, vars = {} }, function()
      off_a()
      eq(
        roots.expand("$SHARED_ROOT/x"),
        "/data/shared/x",
        "register: the first plugin's unregister does not remove the second's equal registration"
      )
      off_b()
      eq(roots.expand("$SHARED_ROOT/x"), "$SHARED_ROOT/x", "register: the owner's does")
    end)

    with_roots({ windows = true, nvim_config = false, vars = {} }, function()
      local first = roots.register("Notes", "C:/a")
      local second = roots.register("NOTES", "C:/b")
      eq(flat(roots.roots()), "NOTES=C:/b", "register (win): another spelling of a name replaces")
      second()
      eq(#roots.roots(), 0, "register (win): ... and nothing of the first is left behind")
      first()
      roots.register("Notes", "C:/a")
      eq(roots.unregister("NOTES"), true, "unregister (win): finds it by the case-insensitive name")
      eq(#roots.roots(), 0, "unregister (win): gone")
    end)
  end

  -- ── json: a refused name is arbitrary bytes ──────────────────────────────────────────────────
  with_roots(
    { windows = false, nvim_config = false, vars = { "BAD\255NAME" }, source = {} },
    function()
      local text = roots.json()
      eq(
        require("lib.lua.strings.safe").utf8(text),
        text,
        "json: a name that is not valid UTF-8 does not spoil the document"
      )
      eq(
        vim.json.decode(text).unresolved[1].problem,
        "invalid_name",
        "json: ... and is still reported"
      )
    end
  )

  -- ── verbatim and device prefixes ─────────────────────────────────────────────────────────────
  --
  -- `\\?\C:\...` is what `fs::canonicalize` and cargo print; it is the same path as `C:\...`.
  with_roots({
    windows = true,
    nvim_config = false,
    vars = {},
    extra = { X = "C:/repos", SHARE = "\\\\?\\UNC\\srv\\share\\r" },
  }, function()
    eq(roots.fold("\\\\?\\C:\\repos\\sub\\f.txt"), "$X/sub/f.txt", "fold (win): \\\\?\\C:\\...")
    eq(roots.fold("\\\\.\\c:\\repos\\f.txt"), "$X/f.txt", "fold (win): \\\\.\\c:\\... (device)")
    eq(roots.fold("//?/C:/repos"), "$X", "fold (win): the slash spelling, the root itself")
    eq(
      flat(roots.roots()),
      "SHARE=//srv/share/r;X=C:/repos",
      "roots (win): a verbatim UNC root is the UNC root"
    )
    eq(roots.fold("\\\\?\\UNC\\srv\\share\\r\\a"), "$SHARE/a", "fold (win): \\\\?\\UNC\\...")
    eq(
      roots.fold("\\\\?\\GLOBALROOT\\x"),
      "\\\\?\\GLOBALROOT\\x",
      "fold (win): other prefixes stay"
    )
  end)

  -- ── a backslash below the root, on POSIX ─────────────────────────────────────────────────────
  --
  -- `a\..\..\Windows` is one valid POSIX file name. Written as `$R/a\..\..\Windows` it climbs out
  -- of the root on a Windows machine that reads the text. Such a path stays absolute.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = {},
    extra = { R = "/home/u/repos" },
  }, function()
    local trap = "/home/u/repos/a\\..\\..\\Windows\\win.ini"
    eq(roots.fold(trap), trap, "fold (posix): a backslash below the root is not folded")
    eq(roots.root_of(trap), nil, "root_of (posix): ... and names no root")
    eq(roots.fold("/home/u/repos/a/b"), "$R/a/b", "fold (posix): an ordinary path is")
  end)
  with_roots({
    windows = true,
    nvim_config = false,
    vars = {},
    extra = { R = "D:/repos" },
  }, function()
    eq(roots.fold("D:\\repos\\a\\b"), "$R/a/b", "fold (win): backslashes are separators there")
  end)

  -- ── Windows: variable names of an injected source ────────────────────────────────────────────
  with_roots(
    { windows = true, nvim_config = false, vars = { "repos_dir" }, source = { REPOS_DIR = "D:/r" } },
    function()
      eq(
        flat(roots.roots()),
        "repos_dir=D:/r",
        "source (win): names are case-insensitive, as in the real environment"
      )
    end
  )
  with_roots(
    { windows = false, nvim_config = false, vars = { "repos_dir" }, source = { REPOS_DIR = "/r" } },
    function()
      eq(#roots.roots(), 0, "source (posix): names are case-sensitive")
    end
  )

  -- ══ review round 3: what the filetree migration needs, and error locations ═══════════════
  --
  -- filetree's `env_roots.vars` REPLACES the default list ("so $REPOS_DIR is no longer a root"),
  -- its `extra` is the plugin's own, and its `enable` is the plugin's own: `names` (additive) could
  -- not express the first, `register` would have published the second to every other plugin, and
  -- `remap` had no `force`. Each gets a per-call option.
  with_roots({
    windows = false,
    nvim_config = false,
    vars = { "REPOS_DIR" },
    source = { REPOS_DIR = "/repos", FT_X = "/ft" },
  }, function()
    eq(
      roots.fold("/repos/proj/a.md", { names = { "FT_X" } }),
      "$REPOS_DIR/proj/a.md",
      "baseline: names ADDS to the configured vars"
    )
    eq(
      roots.fold("/repos/proj/a.md", { vars = { "FT_X" } }),
      "/repos/proj/a.md",
      "opts.vars REPLACES them: $REPOS_DIR is no longer a root for this call"
    )
    eq(
      roots.fold("/ft/n.md", { vars = { "FT_X" } }),
      "$FT_X/n.md",
      "opts.vars: the replacement list is used"
    )
    eq(flat(roots.roots({ vars = {} })), "", "opts.vars = {}: no variable root at all")
    eq(
      flat(roots.roots({ vars = { "FT_X" }, names = { "REPOS_DIR" } })),
      "FT_X=/ft;REPOS_DIR=/repos",
      "opts.vars then opts.names, in that order"
    )
    eq(roots.fold("/repos/proj/a.md"), "$REPOS_DIR/proj/a.md", "... and only for the call")

    eq(roots.fold("/n/x.md"), "/n/x.md", "baseline: nobody knows /n")
    eq(
      roots.fold("/n/x.md", { extra = { FT_NOTES = "/n" } }),
      "$FT_NOTES/x.md",
      "opts.extra: a root this call brings along"
    )
    eq(roots.fold("/n/x.md"), "/n/x.md", "opts.extra: ... that no other caller sees")
    eq(
      roots.root_of("/n/x.md", { extra = { FT_NOTES = "/n" } }),
      "FT_NOTES",
      "root_of takes it too"
    )
    eq(
      flat(roots.roots({
        extra = {
          LATE = function()
            return "/late"
          end,
        },
      })),
      "LATE=/late;REPOS_DIR=/repos",
      "opts.extra takes a function as well, and comes before vars"
    )
  end)

  -- precedence of a per-call root: the user's `extra` first, then the call, then `register`ed
  with_registered("SAMENAME", "/from/registry", function()
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { USERS = "/from/user" },
    }, function()
      eq(
        flat(roots.roots({ extra = { SAMENAME = "/from/call" } })),
        "USERS=/from/user;SAMENAME=/from/call",
        "opts.extra beats a registered root of that name"
      )
      eq(
        flat(roots.roots({ extra = { USERS = "/from/call" } })),
        "USERS=/from/user;SAMENAME=/from/registry",
        "... and the user's own extra beats opts.extra"
      )
    end)
  end)

  -- remap takes the same options; `force` maps although the user switched folding off
  do
    local base = tmp()
    vim.fn.mkdir(base .. "/repos/proj", "p")
    vim.fn.mkdir(base .. "/mine/proj", "p")
    with_roots({
      windows = false,
      enable = false,
      nvim_config = false,
      vars = { "REPOS_DIR" },
      source = { REPOS_DIR = base .. "/repos", FT_X = base .. "/mine" },
    }, function()
      eq(#roots.remap("E:/repos/proj"), 0, "remap: off while disabled")
      eq(
        table.concat(roots.remap("E:/repos/proj", { force = true }), "|"),
        base .. "/repos/proj",
        "remap: opts.force maps anyway (the plugin's own switch is on)"
      )
      eq(
        table.concat(roots.remap("E:/mine/proj", { force = true, names = { "FT_X" } }), "|"),
        base .. "/mine/proj",
        "remap: opts.names"
      )
      eq(
        table.concat(
          roots.remap("E:/mine/proj", { force = true, extra = { MINE = base .. "/mine" } }),
          "|"
        ),
        base .. "/mine/proj",
        "remap: opts.extra"
      )
      eq(
        #roots.remap("E:/repos/proj", { force = true, vars = {} }),
        0,
        "remap: opts.vars replaces the roots here as well"
      )
    end)
    vim.fn.delete(base, "rf")
  end

  -- the error names the function the caller used, and a wrong type is refused
  with_roots({ windows = false, nvim_config = false, vars = {}, source = {} }, function()
    for fn, call in pairs({
      fold = function()
        roots.fold("/x", { typo = 1 })
      end,
      root_of = function()
        roots.root_of("/x", { typo = 1 })
      end,
      folder = function()
        roots.folder({ typo = 1 })
      end,
      remap = function()
        roots.remap("/x", { typo = 1 })
      end,
      roots = function()
        roots.roots({ typo = 1 })
      end,
    }) do
      raises(call, fn .. ": unknown option `typo`", fn .. ": the message names the function")
    end
    raises(function()
      roots.fold("/x", true)
    end, "fold: opts must be a table", "fold: opts of the wrong type")
    raises(function()
      roots.roots({ vars = "REPOS_DIR" })
    end, "roots: option `vars` must be table, got string", "roots: vars as a string")
    raises(function()
      roots.fold("/x", { nvim_config = 1 })
    end, "fold: option `nvim_config` must be boolean, got number", "fold: nvim_config as a number")
    raises(function()
      roots.remap("/x", { force = "yes" })
    end, "remap: option `force` must be boolean, got string", "remap: force as a string")
  end)

  -- A drive-less root (`/repos`) is "on the current drive" on a Windows host: it moves with
  -- `:cd` to another drive, which is what makes a relative root no root. Forced `windows = true`
  -- on another host keeps accepting it, so the Windows rules can be pinned from a POSIX runner.
  do
    local on_windows_host = require("lib.nvim.cross.platform.is_windows")()
    with_roots({
      windows = true,
      nvim_config = false,
      vars = {},
      extra = { DRIVELESS = "/some/root", WITHDRIVE = "D:/some/root" },
    }, function()
      local by_name = {}
      for _, st in ipairs(roots.status()) do
        by_name[st.name] = st
      end
      eq(by_name.WITHDRIVE.root, "D:/some/root", "driveless: a root with a drive is fine")
      if on_windows_host then
        eq(by_name.DRIVELESS.problem, "not_absolute", "driveless: refused on a Windows host")
      else
        eq(by_name.DRIVELESS.root, "/some/root", "driveless: accepted where windows=true is forced")
      end
    end)
    with_roots({
      windows = false,
      nvim_config = false,
      vars = {},
      extra = { POSIXROOT = "/some/root" },
    }, function()
      eq(flat(roots.roots()), "POSIXROOT=/some/root", "driveless: ordinary on POSIX rules")
    end)
    with_roots({
      windows = true,
      nvim_config = false,
      vars = {},
      extra = { UNCROOT = "//srv/share/r" },
    }, function()
      eq(flat(roots.roots()), "UNCROOT=//srv/share/r", "driveless: a UNC root is not driveless")
    end)
  end

  -- setup() with nothing resets: no leftover from the cases above.
  roots.setup()
  eq(roots.enabled(), true, "setup(): defaults restored")
end
