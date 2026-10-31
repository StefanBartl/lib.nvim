-- TESTS/data_classes_cases_spec.lua — lib.nvim.data_classes against the shared case list of tasks-desktop
--
-- tasks-desktop keeps one list of `areas.json` cases (ui/web/classes-cases.mjs) that its Rust hub (classes.rs) and its
-- web reader must answer alike; ui/web/classes-cases-dump.mjs prints it as JSON. This spec holds the Lua reader to the
-- same list, read from the vendored fixture TESTS/fixtures/data_classes_cases.json (source commit and sha256 in
-- data_classes_cases.source.json), so it runs in CI without a checkout and without node.
--
-- The comparison with a checkout and the regenerate step are tested on throwaway repositories with a fake dump (no
-- node). A last check compares the fixture with a local tasks-desktop checkout (`TASKS_DESKTOP_DIR`, else a sibling
-- of this repo) and fails when the fixture lags behind the list committed there; it is [SKIPPED] with the reason
-- when there is nothing to compare (no checkout, no node, a checkout that does not contain the fixture's commit, a
-- dump that fails). Regenerate with scripts/regen_data_classes_cases.lua (see TESTS/README.md).

return function(H)
  local eq, ok = H.eq, H.ok
  local dc = require("lib.nvim.data_classes")
  local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
  local fixture = dofile(vim.fs.joinpath(here, "support", "data_classes_cases.lua"))

  local text, cases, source = fixture.read_fixture()
  ok(text ~= nil, cases)
  ok(type(cases) == "table" and #cases > 100, "the fixture has the cases")

  local failed = {}
  for _, case in ipairs(cases) do
    local classes = dc.parse(fixture.bytes(case.hex))
    if case.refused then
      if classes.problem == nil then
        failed[#failed + 1] = case.name .. ": not refused"
      end
    elseif classes.problem ~= nil then
      failed[#failed + 1] = ("%s: refused (%s)"):format(case.name, classes.problem)
    else
      for area, want in pairs(case.shows) do
        local got = classes:shown(area)
        if got ~= want then
          failed[#failed + 1] = ("%s: %s is %s, not %s"):format(case.name, area, got, want)
        end
      end
    end
    -- a file that is refused releases nothing
    if classes.problem ~= nil then
      for area in pairs(case.shows) do
        if classes:shown(area) ~= "unclassified" then
          failed[#failed + 1] = case.name .. ": refused but releases " .. area
        end
      end
    end
  end
  eq(#failed, 0, table.concat(failed, "\n      "))

  -- the fixture is what the sidecar says it is: written by the regenerate script, not edited by hand
  eq(source.repo, "tasks-desktop", "the fixture's source repo")
  ok(
    type(source.commit) == "string" and #source.commit == 40,
    "the fixture names its source commit"
  )
  eq(source.cases, #cases, "the fixture's case count")
  eq(
    vim.fn.sha256(text),
    source.sha256,
    "the fixture's sha256 (regenerate: " .. fixture.REGENERATE .. ")"
  )
  ok(fixture.encode(cases) == text, "the fixture is in the regenerate script's form")

  -- the hex runs: `<pair>*<count>;` for MIN_RUN equal bytes or more, expanded byte for byte
  eq(fixture.hex_compress("41" .. ("20"):rep(16) .. "42"), "4120*16;42", "a run is compressed")
  eq(fixture.hex_compress(("20"):rep(15)), ("20"):rep(15), "a short run stays as it is")
  eq(fixture.hex_compress(("aB"):rep(20)), "aB*20;", "a pair keeps its case")
  for _, plain in ipairs({
    "",
    "00",
    ("ff"):rep(17),
    "41" .. ("20"):rep(300) .. ("0a"):rep(16) .. "7b",
    ("20"):rep(16) .. ("21"):rep(16) .. ("20"):rep(16),
  }) do
    eq(fixture.hex_expand(fixture.hex_compress(plain)), plain, "hex round trip of " .. #plain)
  end
  eq(fixture.bytes("4120*3;42"), "A   B", "bytes of a compressed hex")
  ok(not pcall(fixture.hex_expand, "4"), "an odd hex is refused")
  ok(not pcall(fixture.hex_expand, "20*3"), "an unterminated run is refused")
  local exact, over
  for _, case in ipairs(cases) do
    if case.name == "a file of exactly 256 KiB is read" then
      exact = case
    elseif case.name == "a file over 256 KiB is refused" then
      over = case
    end
  end
  ok(exact and over, "the fixture has the 256 KiB cases")
  eq(#fixture.bytes(exact.hex), 256 * 1024, "the 256 KiB case expands to 256 KiB")
  eq(#fixture.bytes(over.hex), 256 * 1024 + 1, "the over-256-KiB case expands to one byte more")
  ok(#exact.hex < 200, "the 256 KiB case is stored compressed")

  -- the comparison with a checkout and the regenerate step, on a throwaway repository with a fake dump that reads the
  -- committed `ui/web/cases.json` of the exported tree (no node)
  local F = dofile(vim.fs.joinpath(here, "git_fixture.lua"))(H)
  local function case_list(n)
    local list = {}
    for i = 1, n do
      list[i] =
        { name = "case " .. i, hex = ("%02x"):format(i), refused = false, shows = { a = "public" } }
    end
    return list
  end
  local runner = function(tree)
    local f = assert(io.open(vim.fs.joinpath(tree, "ui", "web", "cases.json"), "rb"))
    local body = f:read("*a")
    f:close()
    local okd, list = pcall(vim.json.decode, body)
    if not okd then
      return nil, "the dump failed: SyntaxError"
    end
    return list
  end
  local repo = F.init("-tasks-desktop")
  local cases_json = vim.fs.joinpath(repo, "ui", "web", "cases.json")
  F.write(vim.fs.joinpath(repo, "ui", "web", "classes-cases-dump.mjs"), "// fake\n")
  F.write(cases_json, vim.json.encode(case_list(2)))
  local a = F.commit(repo, "A")
  F.write(cases_json, vim.json.encode(case_list(3)))
  local b = F.commit(repo, "B")
  F.git(repo, { "checkout", "-q", "-b", "side", a })
  F.write(cases_json, vim.json.encode(case_list(1)))
  F.commit(repo, "E, diverged from B")
  F.git(repo, { "checkout", "-q", "-b", "broken", b })
  F.write(cases_json, "{ half-done")
  F.commit(repo, "D, a dump that fails")
  local function at(rev)
    F.git(repo, { "checkout", "-q", "--force", rev })
    F.git(repo, { "clean", "-fdq" })
  end
  local text_a, text_b = fixture.encode(case_list(2)), fixture.encode(case_list(3))
  local function compare(commit, ftext)
    return fixture.compare(repo, { commit = commit }, ftext, runner)
  end

  at("main")
  eq(compare(a, text_a).state, "lags", "HEAD B, fixture A: lags")
  eq(compare(b, text_b).state, "current", "HEAD B, fixture B: current")
  -- another session halfway through the list: uncommitted, untracked -- the committed list counts
  F.write(cases_json, vim.json.encode(case_list(5)))
  F.write(vim.fs.joinpath(repo, "ui", "web", "scratch.txt"), "x")
  eq(compare(b, text_b).state, "current", "a dirty ui/web is not compared")
  F.write(cases_json, "{ half-done")
  eq(compare(b, text_b).state, "current", "half-done work is not dumped")

  local out = F.tmpdir("-fixture")
  local out_fixture = vim.fs.joinpath(out, "cases.json")
  local out_source = vim.fs.joinpath(out, "cases.source.json")
  local regen = function(force)
    return fixture.regenerate(
      repo,
      { force = force, runner = runner, fixture = out_fixture, source = out_source }
    )
  end
  local rok, msg = regen()
  ok(rok, msg)
  ok(msg:find("ignored", 1, true), "regenerate notes the ignored changes: " .. msg)
  local rtext, _, rsource = fixture.read_fixture(out_fixture, out_source)
  eq(rtext, text_b, "regenerate writes the committed list, not the working tree")
  eq(rsource.commit, b, "regenerate names HEAD")

  at(a)
  local older = compare(b, text_b)
  eq(older.state, "n/a", "HEAD A, fixture B: n/a")
  ok(older.reason:find("does not contain", 1, true), older.reason)
  rok, msg = regen()
  ok(not rok and msg:find("refusing to go back", 1, true), "regenerate refuses an older checkout")
  eq(fixture.read_fixture(out_fixture, out_source), text_b, "a refused regenerate writes nothing")
  rok, msg = regen(true)
  ok(rok, msg)
  rtext, _, rsource = fixture.read_fixture(out_fixture, out_source)
  eq(rsource.commit, a, "--force goes back")
  eq(rtext, text_a, "--force writes the older list")

  at("side")
  eq(compare(b, text_b).state, "n/a", "a diverged checkout: n/a")
  at("main")
  ok(regen(), "the sidecar still names A, which B contains")
  at("side")
  rok, msg = regen()
  ok(not rok and msg:find("refusing to go back", 1, true), "regenerate refuses a diverged checkout")

  at("broken")
  local broken = compare(b, text_b)
  eq(broken.state, "n/a", "a dump that fails: n/a")
  ok(broken.reason:find("the dump failed", 1, true), broken.reason)
  rok = regen()
  ok(not rok, "regenerate refuses a dump that fails")

  local unknown = compare(("0"):rep(39) .. "1", text_b)
  eq(unknown.state, "n/a", "a commit the checkout does not know: n/a")
  ok(unknown.reason:find("does not know", 1, true), unknown.reason)
  eq(fixture.compare(F.tmpdir("-empty"), source, text, runner).state, "n/a", "no checkout: n/a")
  F.cleanup()

  -- the fixture keeps up with a local tasks-desktop checkout, when there is one that contains its commit
  local dir = fixture.checkout_dir()
  local res = fixture.compare(dir, source, text)
  if res.state == "n/a" then
    H.skipped("data_classes cases vs tasks-desktop", tostring(res.reason))
    return
  end
  if res.state ~= "current" then
    error(
      ("FAIL the fixture (tasks-desktop@%s, %d cases) lags behind the case list committed at %s (HEAD %s, %d cases); run %s"):format(
        source.commit,
        #cases,
        dir,
        tostring(res.head),
        res.count,
        fixture.REGENERATE
      )
    )
  end
end
