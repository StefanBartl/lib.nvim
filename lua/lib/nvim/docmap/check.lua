---@module 'lib.nvim.docmap.check'
--- Drift checks over a docmap IR.
---
--- This is the half of docmap that earns its keep. A rendered map is a nice
--- artifact; a map that *fails* when documentation and reality diverge is a
--- test. Every check here corresponds to a defect class actually observed in
--- the tree it was written against — most sharply `lib.find_root`, which was
--- declared on the aggregate `Lib` class but wired into none of the export
--- strategies, so the published type was simply false and stayed that way
--- until it was found by accident.
---
--- Checks are pluggable: the generic ones below make no assumption beyond
--- "annotated Lua tree", and anything repo-specific (aggregator wiring, for
--- instance) is passed in through `opts.extra_checks` so another plugin can
--- reuse this file without inheriting lib.nvim's conventions.

local M = {}

local uv = vim.uv or vim.loop

---@alias Lib.Docmap.Severity "error"|"warn"|"info"

---@param list Lib.Docmap.Finding[]
---@param severity Lib.Docmap.Severity
---@param check string
---@param node_id string?
---@param message string
local function add(list, severity, check, node_id, message)
  list[#list + 1] = { severity = severity, check = check, node = node_id, message = message }
end

---Derive the module path a file *should* declare from where it lives.
---
---Exported because it is also the only sane way to name a **namespace**: a
---directory without `init.lua` declares no `@module` at all, but
---`lua/lib/nvim/fs` is still "lib.nvim.fs" to anyone typing it — and those
---directories are exactly the aggregation points a dependency graph is asked
---about. Deriving it in a second place would be a drift risk.
---@param path string Repo-relative, forward slashes
---@param lua_root string
---@return string|nil
function M.expected_module(path, lua_root)
  local prefix = lua_root .. "/"
  if path:sub(1, #prefix) ~= prefix then
    return nil
  end
  local rest = path:sub(#prefix + 1)
  rest = rest:gsub("%.lua$", ""):gsub("/init$", "")
  return (rest:gsub("/", "."))
end

--- Every module and helper file should say what it is in one sentence — that
--- sentence is what the map, the README tables and the vimdoc all render.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_summaries(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind ~= "namespace" then
      if not node.module then
        add(
          findings,
          "error",
          "missing-module-tag",
          id,
          ("%s has no ---@module annotation"):format(node.source or id)
        )
      elseif node.summary == "" then
        add(
          findings,
          "warn",
          "missing-summary",
          id,
          ("%s has ---@module but no description line"):format(node.source or id)
        )
      end
    end
  end
end

--- A copy-pasted module header that still names its origin is invisible in
--- review and actively misleading in the map.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_module_paths(ir, findings, opts)
  local lua_root = opts.lua_root or "lua"
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.source then
      local want = M.expected_module(node.source, lua_root)
      if want and want ~= node.module then
        add(
          findings,
          "error",
          "module-path-mismatch",
          id,
          ("%s declares @module '%s' but lives at '%s'"):format(node.source, node.module, want)
        )
      end
    end
  end
end

--- Not every module needs a README, but the absence should be a decision
--- rather than an oversight, so this is reported at `info`.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_readmes(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind == "module" and not node.readme then
      add(findings, "info", "missing-readme", id, ("%s has no README.md"):format(node.path))
    end
  end
end

--- README module tables in this repo carry deep relative links that nothing
--- validates today; a moved module silently leaves 404s behind.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_readme_links(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.readme then
      local abs = root .. "/" .. node.readme
      local fd = io.open(abs, "r")
      if fd then
        local content = fd:read("*a")
        fd:close()
        local base = node.path
        local seen = {}
        for target in content:gmatch("%]%(([^)#]+)%)") do
          if not target:match("^%a+://") and not target:match("^#") and not seen[target] then
            seen[target] = true
            -- Resolve relative to the README's own directory.
            local joined = base .. "/" .. target
            local parts, stack = {}, {}
            for seg in joined:gmatch("[^/]+") do
              parts[#parts + 1] = seg
            end
            for _, seg in ipairs(parts) do
              if seg == ".." then
                table.remove(stack)
              elseif seg ~= "." then
                stack[#stack + 1] = seg
              end
            end
            local resolved = table.concat(stack, "/")
            if not uv.fs_stat(root .. "/" .. resolved) then
              add(
                findings,
                "warn",
                "dead-readme-link",
                id,
                ("%s links to '%s' which does not exist"):format(node.readme, target)
              )
            end
          end
        end
      end
    end
  end
end

--- A module that exists on disk but is required by nothing above it was
--- either written and never wired up, or orphaned by a refactor.
---
--- Reads `node.required_by`, which `docmap.deps` fills during the scan. An
--- earlier version re-read every source file here to collect `require` strings
--- into one flat set — which answered this one question and discarded the
--- thing that made a dependency graph possible, namely *which* file each
--- require came from. Same answer now, from data that also draws the Deps
--- view, at no I/O.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_orphans(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.kind ~= "namespace" and id ~= ir.root then
      -- A module may legitimately be reached only through the aggregator's
      -- string map rather than a literal require, so this stays at `info`.
      if #(node.required_by or {}) == 0 then
        add(
          findings,
          "info",
          "unreferenced-module",
          id,
          ("%s is required by no other file in the tree"):format(node.module)
        )
      end
    end
  end
end

--- Strongly connected components of the **load-time** require graph.
---
--- Exported because two callers need exactly this: the drift check below, and
--- `docmap.diff`, which reports cycles a change introduced. Duplicating
--- Tarjan for the second one would have been two implementations of the one
--- thing in this module most likely to be subtly wrong.
---
--- Deferred requires — `require(...)` inside a function body, the standard way
--- this tree breaks initialisation order on purpose — are excluded, which is
--- why this builds its own adjacency instead of reusing `node.requires`. Run
--- against lib.nvim without that exclusion, every cycle reported was a
--- deliberate lazy load: a check that only ever fires on intentional code is
--- one people learn to skim past, so it would have cost the real ones too.
---
--- Iterative rather than recursive: the graph is as deep as the tree is wide
--- and Lua's default C stack is not something to spend here.
---@param ir Lib.Docmap.IR
---@return string[][] components Each sorted, each with at least two members.
function M.require_cycles(ir)
  local adj = {}
  for _, id in ipairs(ir.order) do
    adj[id] = {}
  end
  for _, edge in ipairs(ir.edges or {}) do
    if edge.kind == "require" and not edge.deferred and adj[edge.from] then
      adj[edge.from][#adj[edge.from] + 1] = edge.to
    end
  end

  local components = {}
  local index, low, on_stack, idx = {}, {}, {}, 0
  local stack = {}

  for _, start in ipairs(ir.order) do
    if index[start] == nil then
      -- Each frame carries its own child cursor, which is what turns the
      -- recursive formulation into a loop without changing the algorithm.
      local frames = { { id = start, child = 1 } }

      while #frames > 0 do
        local frame = frames[#frames]
        local id = frame.id

        if frame.child == 1 then
          index[id], low[id] = idx, idx
          idx = idx + 1
          stack[#stack + 1] = id
          on_stack[id] = true
        end

        local children = adj[id] or {}
        local advanced = false

        while frame.child <= #children do
          local child = children[frame.child]
          frame.child = frame.child + 1
          if index[child] == nil then
            frames[#frames + 1] = { id = child, child = 1 }
            advanced = true
            break
          elseif on_stack[child] then
            low[id] = math.min(low[id], index[child])
          end
        end

        if not advanced then
          if low[id] == index[id] then
            local component = {}
            repeat
              local popped = table.remove(stack)
              on_stack[popped] = false
              component[#component + 1] = popped
            until popped == id
            if #component > 1 then
              table.sort(component)
              components[#components + 1] = component
            end
          end

          table.remove(frames)
          local parent = frames[#frames]
          if parent then
            low[parent.id] = math.min(low[parent.id], low[id])
          end
        end
      end
    end
  end

  table.sort(components, function(a, b)
    return a[1] < b[1]
  end)
  return components
end

--- A cycle among load-time requires is the one that actually breaks: two
--- modules that require each other at the top of the file get a
--- half-initialised table on the second one in, and the failure reads as
--- anything but a cycle. Reported at `warn`, so `--check` does not go red over
--- a deliberate one.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_require_cycles(ir, findings)
  for _, component in ipairs(M.require_cycles(ir)) do
    local names = {}
    for _, member in ipairs(component) do
      names[#names + 1] = ir.nodes[member].module or member
    end
    local joined = table.concat(names, " → ")
    -- Reported once per member, not once per cycle: findings attach to a
    -- node, and a cycle with no node attached is unclickable in the HTML
    -- findings table and unjumpable in the quickfix list.
    for _, member in ipairs(component) do
      add(
        findings,
        "warn",
        "require-cycle",
        member,
        ("require cycle across %d modules: %s"):format(#component, joined)
      )
    end
  end
end

--- Architectural layering, expressed as module-path prefixes: modules under
--- `rule.from` may not require modules under `rule.to`. Opt-in via
--- `opts.layers`, because a layering that is not declared cannot be violated —
--- there is no generic default that would be true of an arbitrary tree.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_layers(ir, findings, opts)
  local rules = opts.layers or {}
  if #rules == 0 then
    return
  end

  ---Prefix match on module-path segments, not raw string prefix: `lib.vim`
  ---must match `lib.vim.buffer` and never `lib.vimx`.
  ---@param module string
  ---@param prefix string
  ---@return boolean
  local function under(module, prefix)
    return module == prefix or module:sub(1, #prefix + 1) == prefix .. "."
  end

  for _, edge in ipairs(ir.edges or {}) do
    if edge.kind == "require" then
      local from = ir.nodes[edge.from]
      local to = ir.nodes[edge.to]
      if from.module and to.module then
        for _, rule in ipairs(rules) do
          if under(from.module, rule.from) and under(to.module, rule.to) then
            add(
              findings,
              "warn",
              "layer-violation",
              edge.from,
              ("%s requires %s, but %s must not reach into %s%s"):format(
                from.module,
                to.module,
                rule.from,
                rule.to,
                rule.why and (" — " .. rule.why) or ""
              )
            )
          end
        end
      end
    end
  end
end

--- `@see` is only useful if its target actually resolves to something in the
--- map — same reasoning as `dead-readme-link` for README links. A target
--- resolves against a node's `module` path, a qualified `module.bare_name`,
--- or a function's raw declared name (e.g. "M.scan_full", as written).
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_see_targets(ir, findings)
  local known = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module then
      known[node.module] = true
    end
    for _, fn in ipairs(node.functions) do
      known[fn.name] = true
      if node.module then
        -- "M.foo" -> "foo": this repo's universal local-table convention is
        -- `local M = {}`, so a leading capitalized identifier + dot is the
        -- table, not part of the function's own name. A bare `local function
        -- foo` has no dot and passes through unchanged.
        local bare = fn.name:gsub("^%u[%w_]*%.", "")
        known[node.module .. "." .. bare] = true
      end
    end
  end

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      for _, target in ipairs(fn.see) do
        if not known[target] then
          add(
            findings,
            "warn",
            "dead-see-target",
            id,
            ("%s: @see target '%s' does not resolve to a known module or function"):format(
              fn.name,
              target
            )
          )
        end
      end
    end
  end
end

--- Comma-split the raw signature parameter list into declared names, in
--- source order. `...` is kept as its own token (both checks below treat it
--- specially rather than dropping it silently) so a caller comparing
--- positions still sees a real entry there instead of the list quietly
--- shifting.
---
--- Exported (not `local`) because `doccoverage.lua` (R4) needs the same
--- "how many params does the signature actually declare" question
--- `undocumented-param` already answers, and duplicating the comma-split
--- would be a second place for the two to quietly disagree.
---@param fn Lib.Docmap.FunctionInfo
---@return string[]
function M.declared_param_names(fn)
  local inside = fn.signature:match("%((.-)%)")
  local names = {}
  if not inside or inside == "" then
    return names
  end
  for token in inside:gmatch("[^,]+") do
    token = vim.trim(token)
    if token ~= "" then
      names[#names + 1] = token
    end
  end
  return names
end

--- Text-based heuristic, not a real arity check: counts comma-separated
--- names in the raw signature parameter list and compares against the
--- number of `@param` lines. Deliberately `info`, not `warn`/`error` — a
--- complex signature (default-valued table unpacking, `...`) can make this
--- heuristic wrong, and it should never be the thing that fails `--check`.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_undocumented_params(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      -- `@internal` says this is implementation, not published surface, so
      -- the documentation bar is the author's own. Nagging about it is how a
      -- heuristic check earns its way onto someone's ignore list.
      if not fn.internal then
        local declared = 0
        for _, token in ipairs(M.declared_param_names(fn)) do
          if token ~= "..." then
            declared = declared + 1
          end
        end
        if declared > #fn.params then
          add(
            findings,
            "info",
            "undocumented-param",
            id,
            ("%s has %d parameter(s) but only %d @param line(s)"):format(
              fn.name,
              declared,
              #fn.params
            )
          )
        end
      end
    end
  end
end

--- R5: `undocumented-param` only ever compares *counts*, so a renamed
--- parameter whose `@param` line was never updated — the signature says
--- `path`, the doc still says `file` — passes it silently as long as both
--- lists are the same length. This compares the *names* at each shared
--- position instead.
---
--- Positional, not set-based: Lua has no keyword arguments, so "the doc's
--- third `@param` describes the signature's third parameter" is the actual
--- contract a reader relies on, not "every doc name appears somewhere in the
--- signature" (which would happily accept two params silently swapped).
---
--- Deliberately `info`, same reasoning as `undocumented-param`: text-based,
--- can be wrong on a signature this heuristic does not really understand,
--- and must never be the thing that fails `--check`.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
local function check_param_name_mismatch(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      if not fn.internal then
        local declared = M.declared_param_names(fn)
        local doc_params = fn.params
        -- A colon-declared method's own `self` is Lua's implicit sugar, so
        -- `declared_param_names` never sees it — but documenting it
        -- explicitly (`---@param self Foo`) is common and legitimate LuaCATS
        -- style, verified against this repo's own `Lru:get`/`Lru:put`.
        -- Left uncorrected, every such function would misreport every real
        -- parameter shifted one position early. Skipping the doc's leading
        -- `self` line realigns the comparison instead of guessing it away.
        if fn.name:find(":") and doc_params[1] and doc_params[1].name == "self" then
          local shifted = {}
          for i = 2, #doc_params do
            shifted[#shifted + 1] = doc_params[i]
          end
          doc_params = shifted
        end
        local n = math.min(#declared, #doc_params)
        for i = 1, n do
          local sig_name = declared[i]
          local doc_name = doc_params[i].name
          -- `...` has no name to compare a doc line against; the varargs
          -- shape is exactly what `@vararg`/a bare `...` @param already
          -- means, not a mismatch.
          if sig_name ~= "..." and sig_name ~= doc_name then
            add(
              findings,
              "info",
              "param-name-mismatch",
              id,
              ("%s: @param #%d is documented as '%s' but the signature "):format(
                fn.name,
                i,
                doc_name
              ) .. ("declares '%s' at that position"):format(sig_name)
            )
          end
        end
      end
    end
  end
end

--- Functions nothing appears to use.
---
--- The trap this check is built around, stated plainly: **a library consists
--- of functions with no internal caller by design.** That is what a library
--- is. A naive "no callers ⇒ dead" would report most of the published API of
--- any tree worth mapping, and be switched off the same day. So it fires in
--- two tiers.
---
--- Always on, because there the statement holds:
---   * a **file-local** function (`local function foo`) that its own file
---     never mentions again, and that no call edge reaches;
---   * an `@internal` function no call edge reaches — the tag is the author
---     saying this is not surface, so "nobody calls it" is a real finding.
---
--- Only with `opts.dead_code`, because there it is a question rather than an
--- answer: any other function with no caller in the tree.
---
--- Three things deliberately count as "used", each because it would otherwise
--- produce a confident wrong answer:
---   * `local_refs` — a function passed as a *value* (`vim.system(cmd,
---     on_exit)`) has no call site naming it, and flagging every callback in
---     the tree is exactly the failure this check must not have;
---   * a heuristic call edge, even though it is a guess — for *this* question
---     a guess that something is used is the safe direction;
---   * being someone's `@see` target, which is a documented relationship.
---
--- A colon-declared method (`function Lru:put()`) is qualified on a table
--- exactly as `M.foo` is, just spelled with `:` — not a private local.
--- Treating it as file-local would be doubly wrong: not only is it not
--- private, but `calls.lua`'s callee resolution has no case for method-call
--- syntax at all (`self:put(...)` never becomes a call edge, colon call
--- sites are structurally invisible to it), so every colon method in the
--- tree would be misreported as dead the moment its only callers use `:`.
--- Verified against this repo's own `Lru:get`/`Lru:put`
--- (`lua/lib/lua/memo/lru.lua`), which are the public API and are called
--- only from other files, only via `:` — an earlier name-shape heuristic
--- here (`"^%u[%w_]*%."`, requiring a literal dot) flagged both as dead by
--- default; run against this tree it produced 76 findings where checking the
--- declared name for `:` as well as `.` produces 0.
---
--- Never above `info`, and never a reason for `--check` to fail: dynamic
--- dispatch is invisible to the scanner (`lib.nvim.require`'s metatable and
--- lazy strategies call things that appear nowhere in the source), so a
--- confident verdict here is not available at any severity.
---@param ir Lib.Docmap.IR
---@param findings Lib.Docmap.Finding[]
---@param opts Lib.Docmap.Opts
local function check_dead_functions(ir, findings, opts)
  local called = {}
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" and e.to and e.to_fn then
      called[e.to .. "#" .. e.to_fn] = true
    end
  end

  -- Anything a `@see` points at is documented as related, which is a use.
  local seen_by_see = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      for _, target in ipairs(fn.see or {}) do
        seen_by_see[target] = true
      end
    end
  end

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      local key = id .. "#" .. fn.name
      local bare = fn.name:match("([%w_]+)$") or fn.name
      local file_local = not fn.name:find("[.:]")
      -- `local_refs` has to count as "used" here, not only inside the
      -- file-local branch below: a function bound as a callback
      -- (`vim.system(cmd, on_exit)`) never gets a call edge no matter how
      -- public its name is, and with `opts.dead_code` on, the third tier
      -- below fires on *any* unused function — it would have reported every
      -- callback in the tree passed by value, which is precisely the
      -- confident-wrong-answer this check exists to avoid.
      local used = called[key]
        or seen_by_see[fn.name]
        or seen_by_see[bare]
        or (node.module and seen_by_see[node.module .. "." .. bare])
        or (fn.local_refs or 0) > 0

      if not used then
        local why
        if file_local then
          why = "is file-local and nothing in its own file mentions it"
        elseif fn.internal then
          why = "is marked @internal and nothing in the tree calls it"
        elseif opts.dead_code then
          why = "has no caller anywhere in the tree"
        end

        if why then
          add(findings, "info", "dead-function", id, ("%s %s"):format(fn.name, why))
        end
      end
    end
  end
end

---Run every check and return findings sorted by severity.
---@param ir Lib.Docmap.IR
---@param opts Lib.Docmap.Opts
---@return Lib.Docmap.Finding[]
function M.run(ir, opts)
  local findings = {}

  check_summaries(ir, findings)
  check_module_paths(ir, findings, opts)
  check_readmes(ir, findings)
  check_readme_links(ir, findings, opts)
  check_orphans(ir, findings)
  check_require_cycles(ir, findings)
  check_layers(ir, findings, opts)
  check_see_targets(ir, findings)
  check_undocumented_params(ir, findings)
  check_param_name_mismatch(ir, findings)
  check_dead_functions(ir, findings, opts)

  for _, extra in ipairs(opts.extra_checks or {}) do
    for _, f in ipairs(extra(ir, opts) or {}) do
      findings[#findings + 1] = f
    end
  end

  local rank = { error = 1, warn = 2, info = 3 }
  table.sort(findings, function(a, b)
    if rank[a.severity] ~= rank[b.severity] then
      return rank[a.severity] < rank[b.severity]
    end
    if a.check ~= b.check then
      return a.check < b.check
    end
    return (a.node or "") < (b.node or "")
  end)

  return findings
end

---Group findings by severity for reporting.
---@param findings Lib.Docmap.Finding[]
---@return table<Lib.Docmap.Severity, integer>
function M.tally(findings)
  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end
  return t
end

return M
