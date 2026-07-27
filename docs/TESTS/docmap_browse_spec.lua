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
    for _, key in ipairs({ "2", "3", "4", "1" }) do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "x", false)
      ok(browse.is_open(), "browse: still open after switching to mode " .. key)
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

    browse.close()
    eq(browse.is_open(), false, "browse: close() shuts it down")
    browse.close() -- idempotent
    eq(browse.is_open(), false, "browse: close() is idempotent")
  end
end
