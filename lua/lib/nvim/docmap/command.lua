---@module 'lib.nvim.docmap.command'
--- `:LibMap` — regenerate or verify the module map from inside Neovim.
---
---   :LibMap          regenerate the artifacts
---   :LibMap check    verify without writing (what the hook runs)
---   :LibMap full     regenerate with LuaLS enrichment (class/alias detail,
---                    type-reference edges) — slower, opt-in per invocation
---   :LibMap open     open the generated HTML in the system browser
---
--- Opt-in: nothing here runs unless a caller invokes `setup()`, so requiring
--- `lib.nvim.docmap` in a plugin does not silently register a command in the
--- user's editor.
---
--- Built on `docmap.registry`: `setup()` ensures a live handle exists for
--- `opts.root` (reusing one from a prior `docmap.install()` call rather than
--- scanning a second time) and drives every action through it, so `:LibMap`
--- and any `on_change` subscriber another plugin registered stay in sync
--- with the same IR instead of each holding their own stale copy.
---
--- `opts.command_name` (default "LibMap") is what lets a second `setup()`
--- call — a consuming plugin generating its own map — pick a different name
--- instead of silently overwriting this one; `usercmd.create` defaults to
--- `force = true`, so two `setup()` calls with the same name is not an error,
--- just a bug that changing the name avoids.

local M = {}

---Resolve a user-typed name to a node id.
---
---Three ways, in order of how specific they are: a declared `@module` path, a
---raw node id, and — for a **namespace**, a directory with no `init.lua` and
---therefore no `@module` at all — the module path its location implies. That
---last one is not a nicety: `lua/lib/nvim/fs` is a namespace, so
---`:LibMap graph deps lib.nvim.fs` found nothing until it was added, and
---namespaces are precisely the aggregation points a dependency graph is
---interesting at.
---@param ir Lib.Docmap.IR
---@param name string
---@param lua_root string
---@return string? node_id
function M.find_node(ir, name, lua_root)
  local check = require("lib.nvim.docmap.check")
  local fallback
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module == name or id == name then
      return id
    end
    if not fallback and not node.module then
      if check.expected_module(node.path .. "/init.lua", lua_root) == name then
        fallback = id
      end
    end
  end
  return fallback
end

---Resolve the repository root the map should be generated for.
---
---`vim.fn.getcwd()` is wrong when the user is editing lib.nvim from somewhere
---else, so this walks up from this very file instead — five levels from
---`lua/lib/nvim/docmap/command.lua` is the repo root.
---@return string
local function self_root()
  local this = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  -- docmap/ -> nvim/ -> lib/ -> lua/ -> repo root
  return vim.fn.fnamemodify(this, ":h:h:h:h:h")
end

---@param opts Lib.Docmap.Opts?
---@return Lib.Docmap.Handle
function M.setup(opts)
  local usercmd = require("lib.nvim.usercmd")
  local notify = require("lib.nvim.notify").create("[docmap]")
  local registry = require("lib.nvim.docmap.registry")
  local docmap = require("lib.nvim.docmap")

  local root = (opts and opts.root) or self_root()
  local cfg = opts or require("lib.nvim.docmap.config")(root)
  local command_name = cfg.command_name or "LibMap"

  local handle = registry.get(cfg.root) or registry.install(cfg)

  ---Open the generated HTML, optionally at a specific state.
  ---
  ---The page's whole navigable state is already in its URL fragment, so
  ---"open the deps graph for module X" needs no new rendering path — it is
  ---the existing `open` action with a hash appended.
  ---@param hash string? Fragment including the leading "#", or nil for the default view.
  ---@return boolean opened
  local function open_map(hash)
    local target = cfg.root .. "/" .. (cfg.out_dir or "docs/map") .. "/index.html"
    if vim.uv.fs_stat(target) == nil then
      notify.warn("No map generated yet — run :" .. command_name .. " first.")
      return false
    end

    -- Prefer the server when one is running: same page, but over an origin
    -- where `fetch` is allowed, which is the only way the History tab can
    -- ask anything. Without a server this stays exactly what it always was.
    local serve = require("lib.nvim.docmap.serve")
    local info = serve.info()
    if info then
      require("lib.nvim.fs.open.url.system_opener").open(info.url .. (hash or ""))
      return true
    end

    -- A fragment is only meaningful on a URL. Appended to a bare filesystem
    -- path it becomes part of the filename, and every opener this dispatches
    -- to (`explorer.exe`, `open`, `xdg-open`) then looks for a file called
    -- `index.html#tab=…` and fails silently. The plain no-fragment path stays
    -- a filesystem path, which is what it has always been.
    local url = hash and (vim.uri_from_fname(target) .. hash) or target
    require("lib.nvim.fs.open.url.system_opener").open(url)
    return true
  end

  usercmd.create(command_name, function(args)
    local action = vim.trim(args.args or "")

    if action == "open" then
      open_map()
      return
    end

    -- :LibMap serve [stop]
    --
    -- The runtime docmap deliberately did without until the History tab
    -- needed it: a `file://` page cannot fetch, so "compute this commit when
    -- I click it" requires an origin, and an origin requires a server. See
    -- `serve.lua` for the security and lifecycle rules that come with it.
    if action == "serve" or action:match("^serve%s") then
      local serve = require("lib.nvim.docmap.serve")
      local sub = vim.trim(action:match("^serve%s*(.-)$") or "")

      if sub == "stop" then
        if serve.stop() then
          notify.info("Map server stopped.")
        else
          notify.info("No map server was running.")
        end
        return
      end
      if sub ~= "" then
        notify.warn(("Unknown serve argument '%s' (expected nothing or 'stop')."):format(sub))
        return
      end

      local already = serve.is_running()
      local url, err = serve.start(cfg)
      if not url then
        notify.warn("Could not start the map server: " .. tostring(err))
        return
      end
      notify.info(
        (already and "Map server already running at %s" or "Map server listening at %s"):format(url)
          .. "  (:"
          .. command_name
          .. " serve stop to close)"
      )
      return
    end

    -- :LibMap graph {deps|calls} [module]
    --
    -- The CLI-side counterpart to right-clicking a box: it answers the same
    -- question from where the code is being read, without hunting for the
    -- module in the tree once the page is open. `module` is matched against
    -- the declared `@module` path first and the node id second, so both
    -- "lib.nvim.fs" and "lua/lib/nvim/fs" work.
    local graph_kind, graph_target = action:match("^graph%s+(%a+)%s*(.-)$")
    if graph_kind then
      if graph_kind ~= "deps" and graph_kind ~= "calls" then
        notify.warn("Unknown graph: " .. graph_kind .. " (expected deps or calls)")
        return
      end
      local ir = handle.ir()
      local center = ir.root
      if graph_target ~= "" then
        local found = M.find_node(ir, graph_target, cfg.lua_root or "lua")
        if not found then
          notify.warn("No module matching '" .. graph_target .. "' in the map.")
          return
        end
        center = found
      end
      open_map(
        ("#tab=hierarchy&center=%s&view=%s&dir=out&depth=2"):format(
          vim.uri_encode(center, "rfc2396"),
          graph_kind
        )
      )
      return
    end

    -- :LibMap diff [ref]
    --
    -- The committed artifact is in every commit, so any revision can be
    -- compared without generating anything. `git show <ref>:<artifact>` is the
    -- whole retrieval; the comparison itself is `docmap.diff`, which is pure
    -- and therefore also usable from a CI job with no editor involved.
    local diff_ref = action:match("^diff%s*(.-)$")
    if action == "diff" or action:match("^diff%s") then
      local ref = (diff_ref ~= "" and diff_ref) or "HEAD"
      local rel = (cfg.out_dir or "docs/map") .. "/module_map.json"

      local proc = vim
        .system({ "git", "show", ("%s:%s"):format(ref, rel) }, {
          cwd = cfg.root,
          text = true,
        })
        :wait()
      if proc.code ~= 0 then
        notify.warn(("Cannot read %s at %s: %s"):format(rel, ref, vim.trim(proc.stderr or "")))
        return
      end

      -- `luanil` for the same reason `browse.source` needs it: the artifact
      -- writes a literal `null` for absent optional fields, and `vim.NIL` is
      -- truthy — without it every one of them reads as present.
      local ok_decode, doc = pcall(vim.json.decode, proc.stdout, {
        luanil = { object = true, array = true },
      })
      if not ok_decode or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
        notify.warn(("The map at %s is not a readable docmap artifact."):format(ref))
        return
      end

      local before = require("lib.nvim.docmap.browse.source").rehydrate(doc)
      local diff_mod = require("lib.nvim.docmap.diff")
      local result = diff_mod.compare(before, handle.ir())
      local lines = diff_mod.render(result, before, handle.ir(), ref)

      vim.cmd("enew")
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].filetype = "markdown"
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "hide"
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = false

      if diff_mod.is_empty(result) then
        notify.info(("Nothing structural changed since %s."):format(ref))
      else
        notify.info(
          ("%d module(s), %d function(s), %d dependency change(s) since %s"):format(
            #result.nodes_added + #result.nodes_removed,
            #result.functions_added + #result.functions_removed,
            #result.deps_added + #result.deps_removed,
            ref
          )
        )
      end
      return
    end

    -- :LibMap impact [ref]
    --
    -- `diff` answers what changed about the tree's *shape*; this answers where
    -- the changed *lines* radiate to — which functions they touch and who
    -- calls those. `docmap.history` does all of it purely; this handler is the
    -- git and quickfix half.
    --
    -- Semantics are deliberately the same as `diff`: everything between `ref`
    -- and the working tree, `HEAD` by default. So bare `:LibMap impact` is
    -- "what does my uncommitted work affect" — the pre-commit question — and
    -- on a clean tree `impact HEAD~1` is exactly "what did the last commit
    -- affect". One rule, and it puts the *live* IR on the `+` side, which
    -- matters: the live IR always carries `line_end`, so the new side is
    -- always attributed exactly and only the historical side can degrade.
    --
    -- The out_dir exclusion is not optional. Measured on one commit here, the
    -- full diff is 4.8 MB of which all but 27 KB is the regenerated map —
    -- without it this analyses mostly its own output.
    local impact_ref = action:match("^impact%s*(.-)$")
    if action == "impact" or action:match("^impact%s") then
      local ref = (impact_ref ~= "" and impact_ref) or "HEAD"
      local out_dir = cfg.out_dir or "docs/map"

      local dproc = vim
        .system({
          "git",
          "diff",
          "--unified=0",
          ref,
          "--",
          ".",
          (":(exclude)%s"):format(out_dir),
        }, { cwd = cfg.root, text = true })
        :wait()
      if dproc.code ~= 0 then
        notify.warn(("Cannot diff against %s: %s"):format(ref, vim.trim(dproc.stderr or "")))
        return
      end
      if vim.trim(dproc.stdout or "") == "" then
        notify.info(("Nothing changed since %s (outside %s)."):format(ref, out_dir))
        return
      end

      -- The parent artifact is a convenience, not a requirement: without it
      -- the `-` side simply contributes nothing, which is the honest result
      -- for a revision that predates the map. So a failure here is a notice,
      -- not an abort.
      local before
      local rel = out_dir .. "/module_map.json"
      local sproc = vim
        .system({ "git", "show", ("%s:%s"):format(ref, rel) }, { cwd = cfg.root, text = true })
        :wait()
      if sproc.code == 0 then
        local ok_decode, doc = pcall(vim.json.decode, sproc.stdout, {
          luanil = { object = true, array = true },
        })
        if ok_decode and type(doc) == "table" and type(doc.nodes) == "table" then
          before = require("lib.nvim.docmap.browse.source").rehydrate(doc)
        end
      end

      local ir = handle.ir()
      local history = require("lib.nvim.docmap.history")
      local result = history.analyze(dproc.stdout, ir, before)

      vim.fn.setqflist({}, " ", {
        title = ("docmap impact: %s → working tree"):format(ref),
        items = history.quickfix_items(result, ir, cfg.root),
      })

      if #result.touched == 0 then
        notify.info(
          ("%d file(s) changed since %s, but no scanned function was touched."):format(
            #result.files,
            ref
          )
        )
      else
        notify.info(
          ("%d function(s) touched · %d caller module(s) · %d impacted transitively%s"):format(
            #result.touched,
            #result.calling_modules,
            #result.impacted_modules,
            -- Said out loud rather than implied: an approximated span means the
            -- attribution over-reaches into the gaps between functions, and a
            -- reader deserves to know which kind of answer this is.
            result.approximate and "  (spans approximated — pre-line_end artifact)" or ""
          )
        )
      end
      vim.cmd("copen")
      return
    end

    -- :LibMap dot [deps|calls] [module]
    --
    -- Opens the DOT source in a scratch buffer rather than writing a file or
    -- shelling out to `dot`. Shelling out would add an external dependency
    -- and a "dot not found" failure mode to a feature whose entire output is
    -- text; a buffer is something to yank, `:w`, or pipe through
    -- `:%!dot -Tsvg` — all of which the user can already do better than a
    -- flag could.
    local dot_kind, dot_target = action:match("^dot%s*(%a*)%s*(.-)$")
    if action == "dot" or action:match("^dot%s") then
      dot_kind = (dot_kind == "" or dot_kind == "deps") and "require" or dot_kind
      if dot_kind ~= "require" and dot_kind ~= "calls" then
        notify.warn("Unknown graph: " .. dot_kind .. " (expected deps or calls)")
        return
      end
      local ir = handle.ir()
      local scope
      if dot_target ~= "" then
        scope = M.find_node(ir, dot_target, cfg.lua_root or "lua")
        if not scope then
          notify.warn("No module matching '" .. dot_target .. "' in the map.")
          return
        end
      end

      local src = docmap.render.dot(ir, {
        kind = dot_kind == "calls" and "call" or "require",
        scope = scope,
      })

      -- A name identifies the query, so asking the same one twice should
      -- reuse it rather than fail. `nvim_buf_set_name` *raises* on a
      -- collision, and the error was swallowed by the command wrapper: the
      -- second `:LibMap dot` produced an unnamed buffer and no message at
      -- all. Wiping the previous one first is both the fix and the behaviour
      -- one would want — this is a regenerated scratch view, not a document.
      local name = ("docmap-%s%s.dot"):format(
        dot_kind,
        scope and ("-" .. scope:gsub("[^%w]+", "_")) or ""
      )
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_valid(b) and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == name
        then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end

      vim.cmd("enew")
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(src, "\n", { plain = true }))
      vim.bo[buf].filetype = "dot"
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "hide"
      vim.bo[buf].swapfile = false
      pcall(vim.api.nvim_buf_set_name, buf, name)
      notify.info("Pipe it: :%!dot -Tsvg > graph.svg")
      return
    end

    -- :LibMap why <a> <b>
    --
    -- "Why does A end up pulling in B?" — the question the Deps view can only
    -- be walked by hand to answer. The chain goes to the quickfix list rather
    -- than to a message, because every hop *is* a location: the edge carries
    -- the line the `require` is written on, so each entry jumps straight to
    -- the line that creates that link. A message would have been something to
    -- read; this is something to act on.
    local why_a, why_b = action:match("^why%s+(%S+)%s+(%S+)%s*$")
    if action == "why" or action:match("^why%s") then
      if not why_a then
        notify.warn("Usage: :" .. command_name .. " why <from> <to>")
        return
      end
      local ir = handle.ir()
      local lua_root = cfg.lua_root or "lua"
      local from_id = M.find_node(ir, why_a, lua_root)
      local to_id = M.find_node(ir, why_b, lua_root)
      if not from_id or not to_id then
        notify.warn(("No module matching '%s' in the map."):format(from_id and why_b or why_a))
        return
      end

      local chain = require("lib.nvim.docmap.deps").path(ir, from_id, to_id)
      if not chain then
        notify.info(("%s does not reach %s at all."):format(why_a, why_b))
        return
      end
      if #chain == 0 then
        notify.info("Those are the same module.")
        return
      end

      local items, names = {}, { ir.nodes[from_id].module or from_id }
      local lazy = false
      for _, e in ipairs(chain) do
        local target = ir.nodes[e.to]
        names[#names + 1] = (target.module or e.to) .. (e.deferred and " (lazy)" or "")
        lazy = lazy or e.deferred == true
        items[#items + 1] = {
          filename = cfg.root .. "/" .. ((ir.nodes[e.from] or {}).source or e.from),
          lnum = e.line or 1,
          col = 1,
          text = ("%s → %s%s"):format(
            (ir.nodes[e.from] or {}).module or e.from,
            target.module or e.to,
            e.deferred and "  (lazy)" or ""
          ),
        }
      end

      vim.fn.setqflist({}, " ", {
        title = ("docmap why: %s → %s"):format(why_a, why_b),
        items = items,
      })
      notify.info(("%d hop%s%s:  %s"):format(
        #chain,
        #chain == 1 and "" or "s",
        -- A path that only exists through a deferred require does not run
        -- at load time, which is usually the difference between "has to go"
        -- and "is fine" — so it is said up front, not buried in the list.
        lazy and ", lazy somewhere" or ", all at load time",
        table.concat(names, " → ")
      ))
      vim.cmd("copen")
      return
    end

    if action == "check" then
      local _, findings = handle.rescan()
      local tally = docmap.tally(findings)
      local summary = ("%d errors · %d warnings · %d info"):format(
        tally.error,
        tally.warn,
        tally.info
      )
      if tally.error > 0 then
        notify.warn("Module map drift: " .. summary)
      else
        notify.info("Module map: " .. summary)
      end
      -- Route the detail through the quickfix list rather than a notification
      -- so findings are navigable instead of scrolling past.
      local items = {}
      for _, f in ipairs(findings) do
        if f.severity ~= "info" then
          items[#items + 1] = {
            filename = cfg.root .. "/" .. (f.node or ""),
            text = ("[%s] %s: %s"):format(f.severity, f.check, f.message),
            type = f.severity == "error" and "E" or "W",
          }
        end
      end
      vim.fn.setqflist({}, " ", { title = "Module map drift", items = items })
      if #items > 0 then
        vim.cmd("copen")
      end
      return
    end

    if action == "full" then
      local ir, findings = handle.rescan({ luals = true })
      local written = docmap.write_artifacts(ir, findings, cfg)
      local tally = docmap.tally(findings)
      notify.info(
        ("Wrote %d artifacts with LuaLS enrichment (%d modules, %d edges, %d errors)"):format(
          #written,
          ir.meta.counts.module,
          #(ir.edges or {}),
          tally.error
        )
      )
      return
    end

    local ir, findings = handle.rescan()
    local written = docmap.write_artifacts(ir, findings, cfg)
    local tally = docmap.tally(findings)
    notify.info(
      ("Wrote %d artifacts (%d modules, %d errors)"):format(
        #written,
        ir.meta.counts.module,
        tally.error
      )
    )
  end, {
    nargs = "*",
    desc = "Regenerate the module map (:"
      .. command_name
      .. " [check|full|open|graph|why <a> <b>|dot|diff <ref>|impact <ref>|serve [stop]])",
    complete = function(lead, line)
      -- Two completion levels: the action, then — once "graph" is typed — the
      -- module paths the map actually knows, which is the argument nobody
      -- wants to type by hand.
      local candidates =
        { "check", "full", "open", "graph", "why", "dot", "diff", "impact", "serve" }
      local after_graph = line:match("graph%s+%a*%s+(.*)$") or line:match("graph%s+(%a*)$")
      if line:match("graph%s+%a+%s") or line:match("why%s") or line:match("dot%s+%a+%s") then
        -- Offers exactly what `find_node` resolves, namespaces included —
        -- completing a name the command then rejects is worse than no
        -- completion at all.
        local check = require("lib.nvim.docmap.check")
        local lua_root = cfg.lua_root or "lua"
        candidates = {}
        for _, id in ipairs(handle.ir().order) do
          local node = handle.ir().nodes[id]
          local name = node.module or check.expected_module(node.path .. "/init.lua", lua_root)
          if name then
            candidates[#candidates + 1] = name
          end
        end
        table.sort(candidates)
      elseif after_graph or line:match("dot%s+%a*$") then
        candidates = { "deps", "calls" }
      end
      return vim.tbl_filter(function(c)
        return c:find(lead, 1, true) == 1
      end, candidates)
    end,
  })

  -- :LibBrowse [live] [module] — the same map, navigated inside the editor.
  --
  -- Its own command rather than a `:LibMap browse` subcommand: `:LibMap` is a
  -- *generator* (every action of it writes or verifies artifacts), while this
  -- only ever reads. Folding a read-only viewer into a command whose bare form
  -- rewrites files on disk is the kind of surprise that gets a command bound
  -- to a key and then regretted.
  local browse_command_name = cfg.browse_command_name or "LibBrowse"

  usercmd.create(browse_command_name, function(args)
    local browse = require("lib.nvim.docmap.browse")
    local rest = vim.trim(args.args or "")

    local live = false
    local mode = nil
    local target = rest
    local head, tail = rest:match("^(%S+)%s*(.-)$")
    if head == "live" then
      live = true
      target = tail
      head, tail = target:match("^(%S+)%s*(.-)$")
    end
    -- `history` opens straight into the commit list. It takes no module, so
    -- anything after it would be meaningless — unlike `live`, which is a
    -- prefix the module name follows.
    if head == "history" then
      mode = "history"
      target = tail or ""
    end

    browse.open({
      root = cfg.root,
      source = cfg.source,
      out_dir = cfg.out_dir,
      lua_root = cfg.lua_root,
      live = live,
      mode = mode,
      center = target ~= "" and target or nil,
    })
  end, {
    nargs = "*",
    desc = ("Browse the module map in the editor (:%s [live] [history|module])"):format(
      browse_command_name
    ),
    complete = function(lead, line)
      -- `live` only makes sense as the first token; after it (or after any
      -- module name) the only useful completion is a module path.
      -- `history` stands where a module name would, so it stays on offer for
      -- as long as module names do.
      local candidates = { "history" }
      if not line:match("%s%S+%s") then
        candidates[#candidates + 1] = "live"
      end
      local check = require("lib.nvim.docmap.check")
      local lua_root = cfg.lua_root or "lua"
      local ir = handle.ir()
      for _, id in ipairs(ir.order) do
        local node = ir.nodes[id]
        local name = node.module or check.expected_module(node.path .. "/init.lua", lua_root)
        if name then
          candidates[#candidates + 1] = name
        end
      end
      table.sort(candidates)
      return vim.tbl_filter(function(c)
        return c:find(lead, 1, true) == 1
      end, candidates)
    end,
  })

  return handle
end

return M
