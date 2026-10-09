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
    local names = {}
    for _, st in ipairs(roots.status()) do
      names[#names + 1] = st.name .. ":" .. tostring(st.problem)
    end
    eq(
      table.concat(names, ","),
      "A:missing_dir,B:missing_dir,C:not_absolute,D:not_absolute,E:not_absolute",
      "status: a relative value and a whole drive / filesystem root are refused"
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

    -- Two anchors in one path (".../repos/data/repos/nested"): nearest anchor first, each once.
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
    local cfg = tmp()
    H.with_stdpath_config(cfg, function()
      roots.setup()
      vim.env.NVIM_CONFIG_DIR = nil
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

  -- setup() with nothing resets: no leftover from the cases above.
  roots.setup()
  eq(roots.enabled(), true, "setup(): defaults restored")
end
