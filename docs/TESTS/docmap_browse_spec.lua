-- docs/TESTS/docmap_browse_spec.lua — lib.nvim.docmap.browse
--
-- Two halves, deliberately separated: `view`/`source` are pure and get a
-- synthetic IR (deterministic, no dependency on whether docs/map is present
-- or current), while the UI half mounts the real kit layout and drives the
-- real keymaps.

return function(H)
  local eq, ok = H.eq, H.ok

  local source = require("lib.nvim.docmap.browse.source")
  local view = require("lib.nvim.docmap.browse.view")
  local browse = require("lib.nvim.docmap.browse")

  -- A three-node tree: root -> {alpha, beta}. alpha requires beta, and
  -- alpha's `M.run` calls beta's `M.helper`.
  local function fixture()
    local ir = {
      root = "lua/x",
      meta = { title = "x" },
      order = { "lua/x", "lua/x/alpha", "lua/x/beta" },
      nodes = {
        ["lua/x"] = {
          id = "lua/x",
          kind = "namespace",
          name = "x",
          path = "lua/x",
          summary = "",
          body = "",
          children = { "lua/x/alpha", "lua/x/beta" },
          functions = {},
          requires = {},
          required_by = {},
          requires_external = {},
          symbols = {},
          types = {},
          depth = 0,
        },
        ["lua/x/alpha"] = {
          id = "lua/x/alpha",
          kind = "module",
          name = "alpha",
          path = "lua/x/alpha",
          source = "lua/x/alpha/init.lua",
          module = "x.alpha",
          summary = "Alpha does things.",
          body = "",
          parent = "lua/x",
          children = {},
          functions = {
            {
              name = "M.run",
              signature = "run(a)",
              summary = "Runs.",
              line = 12,
              params = {},
              returns = {},
            },
          },
          requires = { "lua/x/beta" },
          required_by = {},
          requires_external = { "plenary.async" },
          symbols = {},
          types = {},
          depth = 1,
        },
        ["lua/x/beta"] = {
          id = "lua/x/beta",
          kind = "module",
          name = "beta",
          path = "lua/x/beta",
          source = "lua/x/beta/init.lua",
          module = "x.beta",
          summary = "Beta helps.",
          body = "",
          parent = "lua/x",
          children = {},
          functions = {
            {
              name = "M.helper",
              signature = "helper()",
              summary = "Helps.",
              line = 30,
              params = {},
              returns = {},
            },
          },
          requires = {},
          required_by = { "lua/x/alpha" },
          requires_external = {},
          symbols = {},
          types = {},
          depth = 1,
        },
      },
      edges = {
        {
          kind = "require",
          from = "lua/x/alpha",
          to = "lua/x/beta",
          to_module = "x.beta",
          line = 3,
        },
        {
          kind = "call",
          from = "lua/x/alpha",
          to = "lua/x/beta",
          from_fn = "M.run",
          to_fn = "M.helper",
          line = 14,
          confidence = "exact",
        },
      },
    }
    return ir
  end

  local ir = fixture()

  -- ------------------------------------------------------- source.rehydrate
  --
  -- The artifact writes `nodes` as an ARRAY in walk order and carries no
  -- `order` key (that array *is* the order — a JSON object's key order would
  -- not be deterministic). In memory both exist. Rehydration bridges the two,
  -- and getting it wrong makes every node lookup miss.
  local doc = {
    root = "lua/x",
    nodes = {
      { id = "lua/x", name = "x", children = { "lua/x/alpha" } },
      { id = "lua/x/alpha", name = "alpha" },
    },
  }
  local hydrated = source.rehydrate(doc)
  eq(hydrated.nodes["lua/x"].name, "x", "rehydrate: nodes become a map keyed by id")
  eq(hydrated.order[2], "lua/x/alpha", "rehydrate: order is the original array sequence")
  eq(type(hydrated.edges), "table", "rehydrate: edges is always a table")

  -- ------------------------------------------------------- structure mode
  local st = { mode = "structure", id = "lua/x", dir = "out", depth = 2, cursor = 1 }
  local entries = view.entries(ir, st)
  eq(#entries, 2, "structure: root lists its two children")
  eq(entries[1].kind, "node", "structure: children are node entries")
  eq(entries[1].id, "lua/x/alpha", "structure: first child is alpha")

  st.id = "lua/x/alpha"
  entries = view.entries(ir, st)
  eq(#entries, 1, "structure: a leaf module lists its own functions")
  eq(entries[1].kind, "function", "structure: functions appear as function entries")
  eq(entries[1].fn, "M.run", "structure: the function entry carries its declared name")
  eq(entries[1].line, 12, "structure: the function entry carries its line, for gd")
  eq(entries[1].source, "lua/x/alpha/init.lua", "structure: and its source path")

  -- ------------------------------------------------------------- deps mode
  st = { mode = "deps", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  -- beta (resolved) + the external require, which is listed but not navigable
  eq(#entries, 2, "deps out: one resolved dependency plus one external")
  eq(entries[1].id, "lua/x/beta", "deps out: alpha requires beta")
  eq(entries[2].kind, "external", "deps out: unresolved requires are shown as external")

  st.dir = "in"
  entries = view.entries(ir, st)
  eq(#entries, 1, "deps in: nothing requires alpha... except the message")
  eq(entries[1].kind, "message", "deps in: an empty direction says so instead of rendering blank")

  st = { mode = "deps", id = "lua/x/beta", dir = "in", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(entries[1].id, "lua/x/alpha", "deps in: beta is required by alpha")

  -- depth is honored: with depth 1 from the root, only direct edges appear
  local reached = view.walk_requires(ir, "lua/x/alpha", "out", 1)
  eq(#reached, 1, "walk_requires: depth 1 reaches the direct dependency")
  eq(reached[1].depth, 1, "walk_requires: and reports its distance")

  -- ------------------------------------------------------------ calls mode
  st = { mode = "calls", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(#entries, 1, "calls out: alpha has one outgoing call")
  eq(entries[1].fn, "M.helper", "calls out: the entry names the callee")
  eq(entries[1].id, "lua/x/beta", "calls out: and the node it lives in")
  -- The jump target must be the callee's DECLARATION, not the call site:
  -- e.line (14) is in alpha, which is the file already being looked at.
  eq(entries[1].line, 30, "calls out: gd targets the callee's declaration line, not the call site")
  eq(entries[1].site_line, 14, "calls out: the call site is kept separately")

  st = { mode = "calls", id = "lua/x/beta", dir = "in", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(#entries, 1, "calls in: beta has one caller")
  eq(entries[1].fn, "M.run", "calls in: the entry names the caller")

  -- narrowing to one function
  st = { mode = "calls", id = "lua/x/alpha", fn = "M.run", dir = "out", depth = 2, cursor = 1 }
  eq(#view.entries(ir, st), 1, "calls: pinning a function keeps its own edges")
  st.fn = "M.nonexistent"
  eq(view.entries(ir, st)[1].kind, "message", "calls: pinning a function with no edges reports it")

  -- ------------------------------------------------------------ types mode
  st = { mode = "types", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(
    entries[1].kind,
    "message",
    "types: a map without LuaLS detail says so rather than looking empty"
  )

  ir.nodes["lua/x/alpha"].types_detail = {
    {
      name = "X.Alpha",
      kind = "class",
      desc = "An alpha.",
      file = "lua/x/alpha/@types/init.lua",
      fields = {},
    },
  }
  entries = view.entries(ir, st)
  eq(entries[1].kind, "type", "types: with detail present, classes are listed")
  eq(entries[1].type_name, "X.Alpha", "types: the entry carries the type name")
  ir.nodes["lua/x/alpha"].types_detail = nil

  -- ------------------------------------------------------- detail + status
  local detail = view.detail(
    ir,
    { mode = "structure", id = "lua/x/alpha" },
    { kind = "node", id = "lua/x/beta" }
  )
  eq(detail[1], "x.beta", "detail: a node detail leads with its module path")

  detail = view.detail(
    ir,
    { mode = "structure", id = "lua/x/alpha" },
    { kind = "function", id = "lua/x/alpha", fn = "M.run" }
  )
  eq(detail[1], "run(a)", "detail: a function detail leads with its signature")
  local joined = table.concat(detail, "\n")
  ok(
    joined:find("1 callers", 1, true) or joined:find("0 callers", 1, true),
    "detail: reports caller/callee counts"
  )

  eq(view.breadcrumb(ir, "lua/x/alpha"), "x ▸ alpha", "breadcrumb: walks parents to the root")
  local status = view.status(ir, { mode = "deps", id = "lua/x/alpha", dir = "in", depth = 3 })
  ok(status:find("deps", 1, true) ~= nil, "status: names the mode")
  ok(status:find("depth 3", 1, true) ~= nil, "status: shows the depth axis in deps mode")

  -- A missing node must not raise — a stale map can point anywhere.
  eq(
    view.entries(ir, { mode = "structure", id = "nope", dir = "out", depth = 2 })[1].kind,
    "message",
    "entries: an unknown node id reports instead of erroring"
  )

  -- ---------------------------------------------------------- history mode
  --
  -- The one mode whose data does not come from the IR: `init.lua` runs git
  -- and parks the result on the state. So these tests hand `view` exactly
  -- what git would have produced — which is also the point of the split.

  -- Level 1, before the commit list has arrived.
  st = { mode = "history", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(entries[1].kind, "message", "history: says it is loading rather than looking empty")

  st.commits = {}
  eq(view.entries(ir, st)[1].label, "(no commits)", "history: an empty repo says so")

  st.commits = {
    {
      sha = "a1b2c3d4e5f6a7b8c9d0",
      short = "a1b2c3d",
      author = "A",
      date = "2026-01-01",
      subject = "first",
    },
    {
      sha = "0f1e2d3c4b5a69788796",
      short = "0f1e2d3",
      author = "B",
      date = "2025-12-31",
      subject = "older",
    },
  }
  entries = view.entries(ir, st)
  eq(#entries, 2, "history: one row per commit")
  eq(entries[1].kind, "commit", "history: commit rows are their own kind")
  eq(
    entries[1].sha,
    "a1b2c3d4e5f6a7b8c9d0",
    "history: the row carries the full sha, not the short one"
  )
  ok(entries[1].label:find("first", 1, true) ~= nil, "history: the subject is in the label")

  -- Level 2: a commit is open but its analysis has not landed yet.
  st.sha = "a1b2c3d4e5f6a7b8c9d0"
  eq(view.entries(ir, st)[1].kind, "message", "history: an unanalysed commit says it is working")

  st.impact = {
    files = { "lua/x/alpha/init.lua" },
    touched = { { node = "lua/x/alpha", fn = "M.run", line = 12, signature = "run(a)" } },
    callers = { ["lua/x/alpha#M.run"] = { { node = "lua/x/beta", fn = "M.helper", line = 40 } } },
    calling_modules = { "lua/x/beta" },
    impacted_modules = { "lua/x/beta" },
    unattributed = { "README.md" },
    approximate = false,
  }
  entries = view.entries(ir, st)
  eq(#entries, 2, "history: one touched function plus the unattributed path")
  eq(entries[1].kind, "function", "history: a touched function is navigable")
  eq(entries[1].fn, "M.run", "history: named")
  eq(entries[1].id, "lua/x/alpha", "history: and placed in its node")
  eq(#entries[1].callers, 1, "history: its callers ride along on the entry")
  eq(
    entries[1].source,
    "lua/x/alpha/init.lua",
    "history: gd targets the declaration in the current tree, not the revision"
  )
  eq(
    entries[2].kind,
    "message",
    "history: a changed path with no attribution is shown but not navigable"
  )

  -- Nothing attributable at all: still not an empty pane.
  local saved_impact = st.impact
  st.impact = { files = { "README.md" }, touched = {}, callers = {}, unattributed = {} }
  eq(#view.entries(ir, st), 1, "history: a docs-only commit collapses to one message")
  eq(view.entries(ir, st)[1].kind, "message", "history: ... and it is not selectable")
  st.impact = saved_impact

  -- Detail panes.
  detail = view.detail(ir, { mode = "history", commits = st.commits }, nil)
  ok(
    table.concat(detail, "\n"):find("Commits", 1, true) ~= nil,
    "history detail: the commit list explains itself when nothing is selected"
  )

  detail = view.detail(
    ir,
    { mode = "history" },
    { kind = "commit", sha = st.commits[1].sha, commit = st.commits[1] }
  )
  eq(detail[1], "first", "history detail: a commit leads with its subject")
  ok(
    table.concat(detail, "\n"):find("a1b2c3d4e5f6a7b8c9d0", 1, true) ~= nil,
    "history detail: and shows the full hash"
  )

  detail = view.detail(ir, st, entries[1])
  local hjoined = table.concat(detail, "\n")
  eq(detail[1], "M.run", "history detail: a touched function leads with its name")
  ok(hjoined:find("Called by 1", 1, true) ~= nil, "history detail: counts the direct callers")
  ok(hjoined:find("M.helper", 1, true) ~= nil, "history detail: and names them")
  ok(hjoined:find("impacted transitively", 1, true) ~= nil, "history detail: reports the radius")

  -- The approximation caveat is the whole reason `approximate` exists: an
  -- over-reaching attribution that says nothing would be worse than no
  -- attribution at all.
  st.impact.approximate = true
  ok(
    table.concat(view.detail(ir, st, entries[1]), "\n"):find("approximated", 1, true) ~= nil,
    "history detail: an approximate analysis warns about it"
  )
  st.impact.approximate = false

  st.impact_has_map = false
  ok(
    table.concat(view.detail(ir, st, entries[1]), "\n"):find("predates", 1, true) ~= nil,
    "history detail: a revision without a committed map warns about it"
  )
  st.impact_has_map = nil

  status = view.status(ir, { mode = "history", commits = st.commits })
  ok(status:find("history", 1, true) ~= nil, "history status: names the mode")
  ok(status:find("2 commits", 1, true) ~= nil, "history status: counts the list")
  status = view.status(ir, { mode = "history", sha = st.sha, impact = st.impact })
  ok(status:find("a1b2c3d4", 1, true) ~= nil, "history status: an open commit becomes the subject")

  -- --------------------------------------------------------------- the UI
  --
  -- Mounts the real layout against this repo's own map when one exists. The
  -- artifact is a build product, so its absence is not a failure — skip
  -- rather than making the suite depend on `:LibMap` having been run.
  local root = vim.fn.getcwd():gsub("\\", "/")
  local uv = vim.uv or vim.loop
  if uv.fs_stat(root .. "/docs/map/module_map.json") then
    eq(browse.is_open(), false, "browse: closed before opening")
    eq(browse.open({ root = root }), true, "browse: opens against the repo's own map")
    eq(browse.is_open(), true, "browse: reports itself open")

    local function slot(ft)
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_get_option_value("filetype", { buf = b }) == ft then
          return w, b
        end
      end
    end

    local list_win, list_buf = slot("lib-docmap-browse-list")
    local _, detail_buf = slot("lib-docmap-browse-detail")
    local _, status_buf = slot("lib-docmap-browse-status")
    ok(list_win ~= nil, "browse: the list slot is mounted")
    ok(detail_buf ~= nil, "browse: the detail slot is mounted")
    ok(status_buf ~= nil, "browse: the status slot is mounted")
    ok(vim.api.nvim_buf_line_count(list_buf) > 0, "browse: the list has content")

    vim.api.nvim_set_current_win(list_win)
    local before = vim.api.nvim_buf_get_lines(status_buf, 0, 1, false)[1]

    -- Selecting a different row and descending must act on THAT row. This
    -- is the regression that live-cursor `selected()` exists for: with a
    -- cached index, <CR> descended into row 1 regardless of the cursor.
    local rows = vim.api.nvim_buf_line_count(list_buf)
    if rows >= 3 then
      vim.api.nvim_win_set_cursor(list_win, { 3, 0 })
      local third = vim.api.nvim_buf_get_lines(list_buf, 2, 3, false)[1]
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
      local after = vim.api.nvim_buf_get_lines(status_buf, 0, 1, false)[1]
      ok(after ~= before, "browse: <CR> navigated somewhere new")
      local leaf = (third or ""):gsub("^%s*[▸·ƒ○≡◆]?%s*", "")
      ok(
        after:find(leaf, 1, true) ~= nil,
        "browse: <CR> descended into the row under the cursor, not a cached one"
      )
    end

    -- Mode switching reaches every mode without erroring.
    for _, key in ipairs({ "2", "3", "4", "5", "1" }) do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "x", false)
      ok(browse.is_open(), "browse: still open after switching to mode " .. key)
    end

    -- History. Untested until now, and it did not work: the trail recorded
    -- only *past* positions while `hindex` was left addressing the entry
    -- before the current one, so the first <C-o> fell off the front and the
    -- second landed one stop too far back. The status line is the cheapest
    -- observable proof of "where am I".
    local function press(k)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
    end
    local function status_now()
      local _, b = slot("lib-docmap-browse-status")
      return vim.api.nvim_buf_get_lines(b, 0, 1, false)[1]
    end

    -- A fresh instance, so the trail has a known beginning: the moves above
    -- are still in the old one, and "stays put at the start" only means
    -- something when the start is where we think it is.
    browse.close()
    browse.open({ root = root })
    vim.api.nvim_set_current_win((slot("lib-docmap-browse-list")))

    local at_start = status_now()
    press("2") -- deps
    local at_deps = status_now()
    press("3") -- calls
    local at_calls = status_now()
    ok(at_deps ~= at_start and at_calls ~= at_deps, "browse: three distinct positions to walk")

    press("<C-o>")
    eq(status_now(), at_deps, "browse: <C-o> steps back exactly one position")
    press("<C-o>")
    eq(status_now(), at_start, "browse: a second <C-o> reaches the one before that")
    press("<C-o>")
    eq(status_now(), at_start, "browse: <C-o> at the start of the trail stays put")

    press("<C-i>")
    eq(status_now(), at_deps, "browse: <C-i> steps forward again")
    press("<C-i>")
    eq(status_now(), at_calls, "browse: forward reaches the newest position")
    press("<C-i>")
    eq(status_now(), at_calls, "browse: <C-i> at the end of the trail stays put")

    -- A fresh move from the middle of the trail truncates the forward half,
    -- exactly like a browser.
    press("<C-o>")
    press("4") -- types, from the middle
    local at_types = status_now()
    press("<C-i>")
    eq(status_now(), at_types, "browse: a new move drops the forward history")

    -- Keys that cannot change anything must not become history stops: a
    -- `<C-o>` that visibly does nothing reads as broken history rather than
    -- as the key having been a no-op.
    -- Each check records the position it is standing on *before* the move, so
    -- the assertion never depends on counting entries in the trail.
    local prev = status_now()
    press("1") -- structure, where depth does not apply
    local at_structure = status_now()
    press("+")
    press("+")
    eq(status_now(), at_structure, "browse: depth keys do nothing outside deps")
    press("<C-o>")
    eq(status_now(), prev, "browse: and leave no dead stop behind them")

    prev = status_now()
    press("2") -- deps, dir starts at "out"
    local at_deps_out = status_now()
    press("l") -- already outgoing
    eq(status_now(), at_deps_out, "browse: setting the direction it already has is a no-op")
    press("<C-o>")
    eq(status_now(), prev, "browse: which also leaves no dead stop")

    -- History mode against this repo's own git history, which is the only
    -- place the *clearing* half of a move is observable. `go` applies its
    -- patch with `pairs`, and `pairs` never yields a key whose value is nil —
    -- so `{ sha = nil }` was the empty patch and `-` out of an opened commit
    -- redrew the same function list forever. Nothing above catches it: every
    -- other move only ever *sets* fields.
    -- `git rev-parse` rather than testing for a `.git` *directory*: in a
    -- worktree `.git` is a file, and this suite is normally run from one.
    local in_git = vim.fn.executable("git") == 1
      and vim.system({ "git", "rev-parse", "HEAD" }, { cwd = root }):wait().code == 0
    if in_git then
      browse.close()
      browse.open({ root = root, mode = "history" })
      local h_win, h_buf = slot("lib-docmap-browse-list")
      vim.api.nvim_set_current_win(h_win)

      local commit_list = status_now()
      ok(commit_list:find("history", 1, true) ~= nil, "browse: mode=history opens on History")
      ok(
        commit_list:find("commits", 1, true) ~= nil,
        "browse: and on the commit list, not inside a commit"
      )
      ok(vim.api.nvim_buf_line_count(h_buf) > 1, "browse: git log produced rows")

      press("<CR>")
      local in_commit = status_now()
      ok(in_commit ~= commit_list, "browse: <CR> opens a commit")

      press("-")
      eq(status_now(), commit_list, "browse: - clears the open commit and returns to the list")
    end

    -- Centering on a NAMESPACE: `lua/lib/nvim/fs` has no init.lua and so
    -- declares no @module, but `lib.nvim.fs` is what a user types. Resolving
    -- only on a declared module silently lands on the root instead.
    browse.close()
    eq(
      browse.open({ root = root, center = "lib.nvim.fs" }),
      true,
      "browse: opens centered on a namespace"
    )
    local _, status2 = slot("lib-docmap-browse-status")
    local line = vim.api.nvim_buf_get_lines(status2, 0, 1, false)[1]
    ok(
      line:find("fs", 1, true) ~= nil,
      "browse: a namespace module path resolves to its node, not the root"
    )

    -- `gq` and `gd` are the two things that justify an editor-side view at
    -- all, and neither was exercised. Both are destructive to the browser
    -- (they close it), so they come last.
    browse.close()
    vim.fn.setqflist({}, "r")
    browse.open({ root = root, center = "lib.nvim.docmap" })
    vim.api.nvim_set_current_win((slot("lib-docmap-browse-list")))
    press("gq")

    eq(browse.is_open(), false, "browse: gq closes the browser")
    local qf = vim.fn.getqflist({ items = 0, title = 0 })
    ok(#qf.items > 0, "browse: gq fills the quickfix list")
    ok(
      (qf.title or ""):find("docmap", 1, true) ~= nil,
      "browse: the quickfix list is titled with the mode and breadcrumb"
    )
    local first = qf.items[1]
    ok(first.bufnr and first.bufnr > 0, "browse: quickfix entries point at a real file")
    ok(first.lnum >= 1, "browse: and carry a line number")
    vim.cmd("cclose")

    -- `gI` reports the blast radius of whatever the DETAIL PANE is showing,
    -- not of the centered node. Those differ as soon as the cursor moves, and
    -- a number that disagrees with the one two panes over is worse than none.
    browse.open({ root = root, center = "lib.nvim.notify" })
    local i_win, i_buf = slot("lib-docmap-browse-list")
    local _, i_detail = slot("lib-docmap-browse-detail")
    vim.api.nvim_set_current_win(i_win)

    local checked = 0
    for row = 1, math.min(3, vim.api.nvim_buf_line_count(i_buf)) do
      vim.api.nvim_win_set_cursor(i_win, { row, 0 })
      vim.cmd("doautocmd CursorMoved")
      local shown = table
        .concat(vim.api.nvim_buf_get_lines(i_detail, 0, -1, false), "\n")
        :match("impact%s+(%d+) module")
      if shown then
        vim.fn.setqflist({}, "r")
        press("gI")
        eq(
          #vim.fn.getqflist(),
          tonumber(shown),
          "browse: gI matches the impact the detail pane just reported"
        )
        checked = checked + 1
        vim.cmd("cclose")
        browse.open({ root = root, center = "lib.nvim.notify" })
        i_win = slot("lib-docmap-browse-list")
        _, i_detail = slot("lib-docmap-browse-detail")
        vim.api.nvim_set_current_win(i_win)
      end
    end
    ok(checked > 0, "browse: at least one row carried an impact figure to check")
    browse.close()

    -- `gO` hands the current position to the page: the fragment must carry
    -- the mode, the centered node and the direction that are on screen.
    local handed = nil
    package.loaded["lib.nvim.fs.open.url.system_opener"] = {
      open = function(url)
        handed = url
        return true
      end,
    }
    browse.open({ root = root, center = "lib.nvim.docmap" })
    vim.api.nvim_set_current_win((slot("lib-docmap-browse-list")))
    press("2") -- deps
    press("h") -- incoming
    press("gO")
    ok(handed ~= nil, "browse: gO handed a URL to the opener")
    ok((handed or ""):find("view=deps", 1, true) ~= nil, "browse: carrying the current mode")
    ok((handed or ""):find("dir=in", 1, true) ~= nil, "browse: and the current direction")
    ok((handed or ""):find("docmap", 1, true) ~= nil, "browse: and the centered node")
    ok((handed or ""):sub(1, 5) == "file:", "browse: as a file:// URL, so the fragment survives")
    browse.close()
    package.loaded["lib.nvim.fs.open.url.system_opener"] = nil

    -- `gd` on a function entry lands in its file at its declaration line.
    browse.open({ root = root, center = "lib.nvim.docmap.deps" })
    local gd_list_win, gd_list_buf = slot("lib-docmap-browse-list")
    vim.api.nvim_set_current_win(gd_list_win)
    local target_row
    for i, row in ipairs(vim.api.nvim_buf_get_lines(gd_list_buf, 0, -1, false)) do
      if row:find("ƒ", 1, true) then
        target_row = i
        break
      end
    end
    if target_row then
      vim.api.nvim_win_set_cursor(gd_list_win, { target_row, 0 })
      press("gd")
      eq(browse.is_open(), false, "browse: gd closes the browser — the floats covered the file")
      local opened = vim.api.nvim_buf_get_name(0):gsub("\\", "/")
      ok(
        opened:find("docmap/deps.lua", 1, true) ~= nil,
        "browse: gd opened the file the entry pointed at"
      )
      ok(vim.api.nvim_win_get_cursor(0)[1] > 1, "browse: at the declaration line, not line 1")
    end

    browse.close()
    eq(browse.is_open(), false, "browse: close() shuts it down")
    browse.close() -- idempotent
    eq(browse.is_open(), false, "browse: close() is idempotent")
  end
end
