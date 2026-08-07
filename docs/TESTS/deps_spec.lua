-- docs/TESTS/deps_spec.lua — lib.nvim.deps.{spec,pm,install,view,health}
--
-- Covers docs/INSTALL.md (fenced-YAML) and docs/install.json parsing,
-- validation (bin/why/pkg required, required defaults false), load()'s
-- extension dispatch, find()/plugins()' runtimepath lookup, package-manager
-- command composition, install-plan computation, the report renderer, and
-- health.report / health.from_tools not erroring.
--
-- Package-manager assertions pass an explicit manager rather than using
-- whatever this host has installed, so the suite behaves identically on a
-- CI container and a dev machine. `install.run` is only exercised on its
-- refusal paths — the success path opens a terminal, which a headless run
-- has no business doing.

return function(H)
  local eq, ok = H.eq, H.ok

  local spec = require("lib.nvim.deps.spec")
  local health = require("lib.nvim.deps.health")

  -- ------------------------------------------------------------- parse_markdown
  do
    local text = [[
# Optional tools

Some prose here that isn't a fenced block at all.

```install-tool
bin: pdftotext
required: false
why: "Enables the fast plain-text extraction backend."
pkg:
  apt: poppler-utils
  brew: poppler
```

More prose in between blocks.

```install-tool
bin: tesseract
required: true
why: "Enables OCR extraction for scanned PDFs."
pkg:
  apt: tesseract-ocr
```
]]
    local result = spec.parse_markdown(text)
    eq(#result.tools, 2, "parse_markdown: two install-tool blocks -> two tools")
    eq(#result.errors, 0, "parse_markdown: well-formed blocks -> no errors")

    eq(result.tools[1].bin, "pdftotext", "parse_markdown: tool 1 bin")
    eq(result.tools[1].required, false, "parse_markdown: tool 1 required (explicit false)")
    eq(
      result.tools[1].why,
      "Enables the fast plain-text extraction backend.",
      "parse_markdown: tool 1 why"
    )
    eq(result.tools[1].pkg.apt, "poppler-utils", "parse_markdown: tool 1 pkg.apt")
    eq(result.tools[1].pkg.brew, "poppler", "parse_markdown: tool 1 pkg.brew")

    eq(result.tools[2].bin, "tesseract", "parse_markdown: tool 2 bin")
    eq(result.tools[2].required, true, "parse_markdown: tool 2 required")
  end

  do
    local text = [[
```install-tool
bin: ffmpeg
pkg:
  apt: ffmpeg
```
]]
    local result = spec.parse_markdown(text)
    eq(#result.tools, 0, "parse_markdown: missing why -> no tool produced")
    eq(#result.errors, 1, "parse_markdown: missing why -> exactly one error")
    eq(result.errors[1].field, "why", "parse_markdown: error field is 'why'")

    -- required omitted entirely (as opposed to explicit false above) still
    -- defaults correctly once why/pkg are fixed:
    local text2 =
      text:gsub("bin: ffmpeg", 'bin: ffmpeg\nwhy: "Transcodes audio for the voice-note backend."')
    local result2 = spec.parse_markdown(text2)
    eq(#result2.tools, 1, "parse_markdown: fixed entry now produces a tool")
    eq(result2.tools[1].required, false, "parse_markdown: omitted 'required' defaults to false")
  end

  do
    local text = [[
```install-tool
required: false
why: "No bin given, should fail."
pkg:
  apt: something
```
]]
    local result = spec.parse_markdown(text)
    eq(#result.tools, 0, "parse_markdown: missing bin -> no tool produced")
    ok(#result.errors >= 1, "parse_markdown: missing bin -> at least one error")
  end

  do
    local text = [[
```install-tool
bin: something
why: "No pkg given, should fail."
```
]]
    local result = spec.parse_markdown(text)
    eq(#result.tools, 0, "parse_markdown: missing pkg -> no tool produced")
    local has_pkg_error = false
    for _, e in ipairs(result.errors) do
      if e.field == "pkg" then
        has_pkg_error = true
      end
    end
    ok(has_pkg_error, "parse_markdown: missing pkg -> reports field 'pkg'")
  end

  eq(
    #spec.parse_markdown("just prose, no fenced blocks at all").tools,
    0,
    "parse_markdown: no blocks -> empty tools"
  )

  -- ----------------------------------------------------------------- parse_json
  do
    local text = vim.json.encode({
      tools = {
        {
          bin = "magick",
          required = false,
          why = "Converts SVGs to PNG for terminals that can't decode SVG themselves.",
          pkg = { apt = "imagemagick", brew = "imagemagick" },
        },
      },
    })
    local result = spec.parse_json(text)
    eq(#result.tools, 1, "parse_json: one entry -> one tool")
    eq(#result.errors, 0, "parse_json: well-formed -> no errors")
    eq(result.tools[1].bin, "magick", "parse_json: bin")
    eq(result.tools[1].pkg.brew, "imagemagick", "parse_json: nested pkg map")
  end

  eq(
    #spec.parse_json("{not valid json").errors,
    1,
    "parse_json: malformed JSON -> one file-level error"
  )
  eq(
    #spec.parse_json('{"nope": []}').errors,
    1,
    "parse_json: missing 'tools' key -> one file-level error"
  )

  -- ---------------------------------------------------------------------- load
  do
    local md_path = H.tmpfile(".md")
    local f = io.open(md_path, "w")
    f:write('```install-tool\nbin: rg\nwhy: "Fast search backend."\npkg:\n  apt: ripgrep\n```\n')
    f:close()
    local result = spec.load(md_path)
    eq(#result.tools, 1, "load: .md path dispatches to parse_markdown")
    eq(result.tools[1].bin, "rg", "load: .md parsed tool bin")
    os.remove(md_path)

    local json_path = H.tmpfile(".json")
    local jf = io.open(json_path, "w")
    jf:write(vim.json.encode({
      tools = { { bin = "fzf", why = "Fuzzy picker backend.", pkg = { apt = "fzf" } } },
    }))
    jf:close()
    local jresult = spec.load(json_path)
    eq(#jresult.tools, 1, "load: .json path dispatches to parse_json")
    eq(jresult.tools[1].bin, "fzf", "load: .json parsed tool bin")
    os.remove(json_path)

    local missing_result, err = spec.load(H.tmpfile(".md"))
    eq(missing_result, nil, "load: nonexistent file -> nil result")
    ok(err ~= nil, "load: nonexistent file -> error message")
  end

  -- ---------------------------------------------------------------------- find
  do
    eq(
      spec.find("a-plugin-name-that-definitely-does-not-exist.nvim"),
      nil,
      "find: unknown plugin -> nil"
    )

    local base = vim.fn.tempname()
    vim.fn.mkdir(base, "p")
    local plugin_dir = base .. "/some-fixture-plugin.nvim"
    vim.fn.mkdir(plugin_dir .. "/docs", "p")
    local install_path = plugin_dir .. "/docs/install.json"
    local f = io.open(install_path, "w")
    f:write(vim.json.encode({ tools = {} }))
    f:close()

    vim.opt.rtp:prepend(plugin_dir)
    local found = spec.find("some-fixture-plugin.nvim")
    ok(found ~= nil, "find: locates docs/install.json once the plugin dir is on runtimepath")
    if found then
      ok(
        found:gsub("\\", "/"):match("some%-fixture%-plugin%.nvim/docs/install%.json$") ~= nil,
        "find: resolved path shape"
      )
    end
    vim.opt.rtp:remove(plugin_dir)
  end

  -- ------------------------------------------------------------------ plugins
  do
    local base = vim.fn.tempname()
    local plugin_dir = base .. "/plugins-fixture.nvim"
    vim.fn.mkdir(plugin_dir .. "/docs", "p")
    local f = io.open(plugin_dir .. "/docs/install.json", "w")
    f:write(vim.json.encode({ tools = {} }))
    f:close()

    vim.opt.rtp:prepend(plugin_dir)
    local names = spec.plugins()
    local found = false
    for _, n in ipairs(names) do
      if n == "plugins-fixture.nvim" then
        found = true
      end
    end
    ok(found, "plugins: lists a plugin shipping docs/install.json")
    vim.opt.rtp:remove(plugin_dir)
  end

  -- ------------------------------------------------- lazy.nvim (not-yet-loaded)
  -- lazy.nvim only puts a plugin on runtimepath once it actually loads, so a
  -- runtimepath-only lookup misses every pending plugin (measured on a real
  -- config: 120 configured, 44 loaded, 76 pending). These two assertions pin
  -- the fallback that covers them: the fixture below is deliberately NOT on
  -- runtimepath, so it is only findable via lazy's registry.
  do
    local base = vim.fn.tempname()
    local plugin_dir = base .. "/lazy-only-fixture.nvim"
    vim.fn.mkdir(plugin_dir .. "/docs", "p")
    local f = io.open(plugin_dir .. "/docs/install.json", "w")
    f:write(vim.json.encode({
      tools = {
        {
          bin = "ghostbin",
          why = "Only reachable through lazy's registry.",
          pkg = { apt = "ghost" },
        },
      },
    }))
    f:close()

    eq(spec.find("lazy-only-fixture.nvim"), nil, "find: not on runtimepath and no lazy -> nil")

    local had = package.loaded["lazy.core.config"]
    package.loaded["lazy.core.config"] = {
      plugins = { ["lazy-only-fixture.nvim"] = { dir = plugin_dir } },
    }

    local found = spec.find("lazy-only-fixture.nvim")
    ok(found ~= nil, "find: falls back to lazy.nvim's registry for a not-yet-loaded plugin")

    local listed = false
    for _, n in ipairs(spec.plugins()) do
      if n == "lazy-only-fixture.nvim" then
        listed = true
      end
    end
    ok(listed, "plugins: includes not-yet-loaded lazy.nvim plugins")

    -- A registry entry pointing at a plugin with no spec file must not be
    -- listed just because lazy knows about it.
    package.loaded["lazy.core.config"] = { plugins = { ["no-spec.nvim"] = { dir = base } } }
    local spurious = false
    for _, n in ipairs(spec.plugins()) do
      if n == "no-spec.nvim" then
        spurious = true
      end
    end
    ok(not spurious, "plugins: a lazy plugin without a spec file is not listed")

    package.loaded["lazy.core.config"] = had
  end

  -- ------------------------------------------------------------------------ pm
  do
    local pm = require("lib.nvim.deps.pm")

    ok(pm.get("apt") ~= nil, "pm.get: known manager id resolves")
    eq(pm.get("not-a-package-manager"), nil, "pm.get: unknown id -> nil")
    ok(#pm.ids() >= 9, "pm.ids: every known manager is listed")

    -- Composition is asserted against explicit manager definitions rather
    -- than whatever this machine happens to have installed, so the spec
    -- behaves the same on a CI container and a dev laptop.
    local brew = pm.get("brew")
    local cmds = pm.commands(brew, { "poppler", "tesseract" })
    eq(#cmds, 1, "pm.commands: multi-capable manager -> one combined command")
    eq(pm.render(cmds[1]), "brew install poppler tesseract", "pm.commands: brew argv")

    local winget = pm.get("winget")
    local wcmds = pm.commands(winget, { "A.One", "B.Two" })
    eq(#wcmds, 2, "pm.commands: winget cannot batch -> one command per package")
    eq(pm.render(wcmds[1]), "winget install A.One", "pm.commands: winget first argv")

    eq(#pm.commands(brew, {}), 0, "pm.commands: no packages -> no commands")

    local pac = pm.commands(pm.get("pacman"), { "poppler" })[1]
    ok(
      table.concat(pac, " "):match("pacman %-S %-%-needed poppler$") ~= nil,
      "pm.commands: pacman keeps its own confirmation prompt (no --noconfirm)"
    )

    eq(pm.render({ "a b", "c" }), '"a b" c', "pm.render: quotes only tokens that need it")

    eq(type(pm.is_root()), "boolean", "pm.is_root: always returns a boolean")
    eq(
      pm.needs_terminal(brew),
      false,
      "pm.needs_terminal: brew never needs root -> false regardless of is_root()"
    )
    if not pm.is_root() then
      eq(
        pm.needs_terminal(pm.get("apt")),
        true,
        "pm.needs_terminal: a root-requiring manager needs a terminal when not already root"
      )
    end
  end

  -- ------------------------------------------------------------------- install
  do
    local deps_install = require("lib.nvim.deps.install")
    local brew = require("lib.nvim.deps.pm").get("brew")

    local tools = {
      -- `nvim` is guaranteed present: this suite runs inside it.
      {
        bin = "nvim",
        required = true,
        why = "The editor this all runs in.",
        pkg = { brew = "neovim" },
      },
      {
        bin = "a-binary-that-does-not-exist-anywhere",
        required = false,
        why = "Enables the hypothetical backend under test.",
        pkg = { brew = "ghost-package" },
      },
      {
        bin = "another-binary-that-does-not-exist",
        required = false,
        why = "Has no brew package declared, so it cannot be installed here.",
        pkg = { apt = "apt-only-package" },
      },
    }

    local plan = deps_install.plan(tools, { manager = brew })
    eq(#plan.present, 1, "plan: one tool already on PATH")
    eq(plan.present[1].bin, "nvim", "plan: present tool is the one that exists")
    eq(#plan.missing, 2, "plan: two tools missing")
    eq(#plan.installable, 1, "plan: only the missing tool with a brew package is installable")
    eq(#plan.unsupported, 1, "plan: the apt-only tool is unsupported under brew")
    eq(plan.packages[1], "ghost-package", "plan: package name comes from the manager's pkg key")
    eq(#plan.commands, 1, "plan: one combined brew command")
    eq(
      require("lib.nvim.deps.pm").render(plan.commands[1]),
      "brew install ghost-package",
      "plan: composed command installs only what's missing and supported"
    )

    -- Two tools, one package (pdftotext + pdftoppm are both poppler-utils).
    -- The command must name the package once; both tools still count as
    -- installable, since the report lists tools rather than packages.
    local shared = deps_install.plan({
      {
        bin = "a-missing-bin-one",
        required = false,
        why = "First half of one package.",
        pkg = { brew = "shared-pkg" },
      },
      {
        bin = "a-missing-bin-two",
        required = false,
        why = "Second half of one package.",
        pkg = { brew = "shared-pkg" },
      },
    }, { manager = brew })
    eq(#shared.installable, 2, "plan: both tools of a shared package are installable")
    eq(#shared.packages, 1, "plan: a package shared by two tools is listed once")
    eq(
      require("lib.nvim.deps.pm").render(shared.commands[1]),
      "brew install shared-pkg",
      "plan: shared package appears once in the composed command"
    )

    local all_present = deps_install.plan({ tools[1] }, { manager = brew })
    eq(#all_present.missing, 0, "plan: nothing missing -> empty missing list")
    eq(#all_present.commands, 0, "plan: nothing missing -> no commands")
    eq(
      deps_install.run(all_present, { confirm = false }),
      false,
      "install.run: nothing to do -> returns false without opening anything"
    )

    -- The no-package-manager plan is built by hand rather than via
    -- `plan(tools, { manager = nil })`: a nil override falls back to
    -- `pm.detect()`, so on any machine that *has* a package manager (this
    -- one included) that call would quietly test the opposite path.
    eq(
      deps_install.run({
        manager = nil,
        present = {},
        missing = { tools[2] },
        installable = {},
        unsupported = { tools[2] },
        packages = {},
        commands = {},
      }, { confirm = false }),
      false,
      "install.run: no package manager -> returns false without opening anything"
    )

    -- A plan whose manager has no package for any missing tool: `run` must
    -- refuse rather than open a terminal with a package-less command.
    local unsupported_only = deps_install.plan({ tools[3] }, { manager = brew })
    eq(#unsupported_only.commands, 0, "plan: only apt-declared tool under brew -> no commands")
    eq(
      deps_install.run(unsupported_only, { confirm = false }),
      false,
      "install.run: nothing installable under this manager -> returns false"
    )
  end

  -- ---------------------------------------------------------------------- view
  do
    local view = require("lib.nvim.deps.view")
    local brew = require("lib.nvim.deps.pm").get("brew")

    local result = {
      tools = {
        {
          bin = "a-missing-required-tool",
          required = true,
          why = "Without this the whole feature is unavailable.",
          pkg = { brew = "ghost" },
        },
        {
          bin = "a-missing-optional-tool",
          required = false,
          why = "short",
          pkg = { brew = "ghost2" },
        },
        {
          bin = "nvim",
          required = false,
          why = "The editor this all runs in.",
          pkg = { brew = "neovim" },
        },
      },
      errors = { { index = 2, field = "why", message = "example problem" } },
    }

    local lines = view.lines("fixture.nvim", result, { manager = brew })
    local text = table.concat(lines, "\n")

    ok(text:match("# fixture%.nvim"), "view.lines: titled with the plugin name")
    ok(
      text:match("%[MISSING, required%] a%-missing%-required%-tool"),
      "view.lines: flags a missing required tool"
    )
    ok(text:match("%[ok%] nvim"), "view.lines: marks a present tool as ok")
    ok(
      text:match("Without this the whole feature is unavailable%."),
      "view.lines: shows each tool's why"
    )
    ok(text:match("this 'why' is very short"), "view.lines: nudges on a low-effort why")
    ok(text:match("brew install ghost"), "view.lines: shows the per-tool install command")
    ok(text:match("## Spec problems"), "view.lines: surfaces spec validation errors")

    -- Missing-and-required must be rendered before the merely-missing one,
    -- which must in turn come before anything already installed: the whole
    -- point of the view is finding what isn't there.
    local required_at = text:find("a%-missing%-required%-tool")
    local optional_at = text:find("a%-missing%-optional%-tool")
    local present_at = text:find("%[ok%] nvim")
    ok(required_at < optional_at, "view.lines: required-missing sorts before optional-missing")
    ok(optional_at < present_at, "view.lines: missing sorts before present")

    local empty = view.lines("empty.nvim", { tools = {}, errors = {} }, { manager = brew })
    ok(
      table.concat(empty, "\n"):match("declares no external tools"),
      "view.lines: empty spec says so rather than rendering a bare header"
    )
  end

  -- ---------------------------------------------------- view.render (ui state)
  do
    local view = require("lib.nvim.deps.view")
    local brew = require("lib.nvim.deps.pm").get("brew")
    local result = {
      tools = {
        {
          bin = "ghostbin",
          required = true,
          why = "Testing streamed output.",
          pkg = { brew = "ghost" },
        },
      },
      errors = {},
    }

    -- render(..., {}) must equal lines() exactly: the interactive overlay
    -- must not change anything when nothing is running.
    eq(
      table.concat(view.render("fixture", result, { manager = brew }, {}).lines, "\n"),
      table.concat(view.lines("fixture", result, { manager = brew }), "\n"),
      "view.render: empty ui table renders identically to lines()"
    )

    local ui = { ghostbin = { lines = {}, running = true, done = false, collapsed = false } }
    local running = view.render("fixture", result, { manager = brew }, ui)
    local running_text = table.concat(running.lines, "\n")
    ok(running_text:match("installing…"), "view.render: running state shows an installing marker")
    ok(running_text:match("<CR> to collapse"), "view.render: running+expanded offers to collapse")

    -- line_tools must point back at the right tool for a line inside the
    -- header block, so a keymap can resolve "which tool is the cursor on".
    local header_idx
    for i, l in ipairs(running.lines) do
      if l:match("^%[MISSING") then
        header_idx = i
      end
    end
    ok(header_idx ~= nil, "view.render: found the tool's header line")
    eq(
      running.line_tools[header_idx] and running.line_tools[header_idx].bin,
      "ghostbin",
      "view.render: line_tools maps the header line back to its tool"
    )
    eq(running.line_tools[1], nil, "view.render: line_tools is nil for non-tool lines (the title)")

    ui.ghostbin.lines = { "Downloading...", "Installing..." }
    local with_output =
      table.concat(view.render("fixture", result, { manager = brew }, ui).lines, "\n")
    ok(with_output:match("| Downloading%.%.%."), "view.render: streamed lines appear, expanded")

    ui.ghostbin.collapsed = true
    local collapsed =
      table.concat(view.render("fixture", result, { manager = brew }, ui).lines, "\n")
    ok(not collapsed:match("Downloading"), "view.render: collapsed hides the streamed output")
    ok(collapsed:match("<CR> to expand"), "view.render: collapsed offers to expand")

    ui.ghostbin.running = false
    ui.ghostbin.done = true
    ui.ghostbin.exit_code = 0
    ui.ghostbin.collapsed = false
    local done_text =
      table.concat(view.render("fixture", result, { manager = brew }, ui).lines, "\n")
    ok(done_text:match("exit 0"), "view.render: done state shows the exit code")
    ok(not done_text:match("installing…"), "view.render: done state no longer shows 'installing'")
  end

  -- --------------------------------------------------------------- forget_exec
  -- End-to-end, not just "doesn't error": a binary that genuinely appears on
  -- PATH mid-session must still read as missing until forget_exec clears the
  -- cached miss — this is exactly the gap that made view.lua's inline
  -- install leave a just-installed tool's line stuck on `[missing]`.
  do
    local core = require("lib.nvim.core")
    local is_windows = require("lib.nvim.cross.platform.is_windows")()

    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local name = "fx-forget-exec-probe"
    local bin_path = dir .. "/" .. name .. (is_windows and ".cmd" or "")

    ok(core.has_exec(name) == false, "forget_exec: not yet on PATH -> miss")

    local f = io.open(bin_path, "w")
    f:write(is_windows and "@echo off\r\n" or "#!/bin/sh\nexit 0\n")
    f:close()
    if not is_windows then
      os.execute("chmod +x " .. bin_path)
    end

    local had_path = vim.env.PATH
    vim.env.PATH = dir .. (is_windows and ";" or ":") .. had_path

    ok(
      core.has_exec(name) == false,
      "forget_exec: cached miss survives PATH actually gaining the binary"
    )
    core.forget_exec(name)
    ok(core.has_exec(name) == true, "forget_exec: cleared -> re-probes and finds it")

    vim.env.PATH = had_path
    os.remove(bin_path)
  end

  -- -------------------------------------------------------------------- health
  -- No dedicated assertions on :checkhealth output (no other module in this
  -- suite unit-tests health.lua rendering either) — just confirm neither
  -- entry point errors, including the mixed bin/python_module/missing-both
  -- shapes and the tools-list bridge.
  health.report({
    { bin = "a-binary-name-that-should-not-exist-anywhere", required = false, hint = "n/a" },
    { bin = "a-binary-name-that-should-not-exist-anywhere", required = true, hint = "n/a" },
    { python_module = "a_module_that_should_not_exist", hint = "n/a" },
  })
  health.from_tools({
    {
      bin = "a-binary-name-that-should-not-exist-anywhere",
      required = false,
      why = "test",
      pkg = { apt = "x" },
    },
  })
end
