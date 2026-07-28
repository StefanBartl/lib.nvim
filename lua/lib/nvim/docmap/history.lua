---@module 'lib.nvim.docmap.history'
--- Where a diff radiates to: which functions a set of changed lines touches,
--- and which callers — and therefore which modules — those functions have.
---
--- `diff.lua` answers what a revision changed about the *shape* of the tree
--- (modules and functions added or removed, dependencies gained, cycles
--- introduced). This answers the other question a reviewer actually has:
--- these concrete lines changed — *who calls the code that changed*.
---
--- Pure, exactly like `diff.lua`: text and IRs in, a structure out. No git,
--- no filesystem, no rendering. `command.lua` fetches the diff and the two
--- historical artifacts; a CI job or a server route could do the same
--- without an editor.
---
--- ## Why two IRs
---
--- A hunk carries two line ranges, and they index different files: the
--- `-` side numbers lines in the parent revision, the `+` side in the
--- revision itself. Resolving both against one IR would silently
--- misattribute every removal in any file that shifted. So the old side is
--- resolved against `ir_before` and the new side against `ir_after`, and the
--- results are merged. Both are optional — a first commit has no parent, and
--- an artifact that predates function scanning has no functions to resolve
--- against (see "Honest degradation" below).
---
--- Getting those IRs is cheap and needs no extra generation step, because
--- the artifact is committed: `git show <ref>:docs/map/module_map.json` is
--- the whole retrieval, the same trick `diff.lua` already relies on.
---
--- ## What counts as "touched"
---
--- A function is touched when a changed line falls within `[line, line_end]`
--- — its body, deliberately not its doc comment. A doc-comment edit is a
--- real change, but it does not radiate to callers, and this module exists
--- to answer where behaviour radiates. `docmap.check`'s documentation drift
--- findings already cover the other half.
---
--- ## Honest degradation
---
--- Three cases produce a changed file with no function attribution, and all
--- three are legitimate rather than errors: the path is not a scanned node
--- (a README, a script), the IR predates function scanning (schema 1
--- artifacts carry no `functions` at all), or the changed lines sit outside
--- every function (module-level tables, requires, comments). They are
--- collected in `unattributed` rather than dropped, so a caller can say
--- "changed, but nothing to trace" instead of implying the commit touched
--- nothing. This mirrors `diff.lua`, which states that sections are not
--- comparable instead of comparing incomparable things.
---
--- ## What the caller must filter
---
--- Nothing here excludes the generated artifacts, and it should not: that is
--- a pathspec decision belonging to whoever invokes git. It matters though —
--- measured on this repo, one commit's full diff is 4.8 MB, of which all but
--- ~16 KB is the regenerated `docs/map/`. Callers pass
--- `:(exclude)<out_dir>` or they analyse mostly generated noise.

local M = {}

---Parse `git diff --unified=0` output into per-file changed line ranges.
---
---`--unified=0` is what makes this tractable: with no context lines, every
---hunk header's ranges *are* the changed lines, so no counting back through
---context is needed. Verified against real output from this repo:
---
---    @@ -2003 +2003,47 @@      old line 2003; new lines 2003..2049
---    @@ -2034,0 +2082,3 @@      nothing removed; new lines 2082..2084
---
---A missing count means 1 (git omits it); a count of 0 means that side has
---no lines at all — a pure insertion has `-N,0`, a pure deletion `+N,0`.
---Those produce an empty range rather than a one-line range at N, which
---would attribute the change to whatever function happens to contain the
---insertion point.
---@param text string Raw `git diff --unified=0` output.
---@return Lib.Docmap.History.FileDiff[]
function M.parse_diff(text)
  local files = {}
  local current

  ---@param s string
  ---@param count_text string
  ---@return { first: integer, last: integer }|nil
  local function range(s, count_text)
    local start = tonumber(s)
    local count = count_text == "" and 1 or tonumber(count_text)
    if not start or not count or count == 0 then
      return nil
    end
    return { first = start, last = start + count - 1 }
  end

  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^diff %-%-git ") then
      current = { old_path = nil, new_path = nil, old = {}, new = {} }
      files[#files + 1] = current
    elseif current and line:match("^%-%-%- ") then
      local p = line:match("^%-%-%- a/(.*)$")
      current.old_path = p -- nil for /dev/null (added file)
    elseif current and line:match("^%+%+%+ ") then
      local p = line:match("^%+%+%+ b/(.*)$")
      current.new_path = p -- nil for /dev/null (deleted file)
    elseif current and line:match("^@@ ") then
      local os_, oc, ns, nc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      if os_ then
        local o = range(os_, oc)
        local n = range(ns, nc)
        if o then
          current.old[#current.old + 1] = o
        end
        if n then
          current.new[#current.new + 1] = n
        end
      end
    end
  end

  return files
end

---Index a scanned IR by the source file each node owns, which is what a
---diff path has to be matched against: a module node's `id` is its
---directory (`lua/lib/nvim/fs`) while the diff names the file
---(`lua/lib/nvim/fs/init.lua`), so matching on `id` alone would miss every
---module and hit only plain file nodes.
---@param ir Lib.Docmap.IR
---@return table<string, string> source path -> node id
local function index_by_source(ir)
  local by_source = {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node and node.source then
      by_source[node.source] = id
    end
  end
  return by_source
end

---@param ranges { first: integer, last: integer }[]
---@param first integer
---@param last integer
---@return boolean
local function overlaps(ranges, first, last)
  for _, r in ipairs(ranges) do
    if not (r.last < first or r.first > last) then
      return true
    end
  end
  return false
end

---The line span of every function in `node`, plus whether any of them had
---to be approximated.
---
---`line_end` only exists in artifacts generated after it was added, so every
---older revision — which is most of the history this module exists to
---analyse — carries only `line`. Falling back to `line` alone would mean
---"a change counts only if it lands exactly on the `function` keyword",
---which measured against this repo found **zero** of the two functions a
---real commit demonstrably changed (`1ce752e`, whose hunks sit at lines
---235-239 and 249-254 of `S.dedent`'s body). That is not a degradation, it
---is silence dressed up as an answer.
---
---So an absent `line_end` is approximated as *the next function's start
---minus one*, since `functions` is ordered by line and only top-level
---functions are ever scanned (no nesting to confuse the ordering). The last
---function extends to infinity.
---
---The approximation over-attributes rather than under-attributes: the gap
---between two functions holds blank lines, module-level code and the *next*
---function's doc comment, so a change there is credited to the preceding
---function. That is the safe direction for this question — the same
---reasoning `local_refs` and `fn.tested` already follow — but callers are
---told via `Impact.approximate` so a UI can say so rather than implying
---precision it does not have.
---@param node Lib.Docmap.Node
---@return { fn: Lib.Docmap.FunctionInfo, first: integer, last: number }[]
---@return boolean approximate
local function spans_for(node)
  local sorted = {}
  for _, fn in ipairs(node.functions or {}) do
    if fn.line then
      sorted[#sorted + 1] = fn
    end
  end
  table.sort(sorted, function(a, b)
    return a.line < b.line
  end)

  local out, approximate = {}, false
  for i, fn in ipairs(sorted) do
    local last = fn.line_end
    if not last then
      approximate = true
      local nxt = sorted[i + 1]
      last = nxt and (nxt.line - 1) or math.huge
    end
    out[#out + 1] = { fn = fn, first = fn.line, last = last }
  end
  return out, approximate
end

---Collect the functions in `ir` whose span overlaps `ranges` for `path`.
---Mutates `acc` (keyed `"<node>#<fn>"`) so both diff sides can accumulate
---into one set without deduplicating afterwards.
---@param ir Lib.Docmap.IR|nil
---@param by_source table<string, string>|nil
---@param path string|nil
---@param ranges { first: integer, last: integer }[]
---@param acc table<string, Lib.Docmap.History.Touched>
---@return boolean attributed True when at least one function matched.
---@return boolean approximate True when this node's spans had to be approximated.
local function collect_side(ir, by_source, path, ranges, acc)
  if not ir or not by_source or not path or #ranges == 0 then
    return false, false
  end
  local id = by_source[path]
  if not id then
    return false, false
  end
  local node = ir.nodes[id]
  if not node then
    return false, false
  end

  local spans, approximate = spans_for(node)
  local hit = false
  for _, s in ipairs(spans) do
    if overlaps(ranges, s.first, s.last) then
      acc[id .. "#" .. s.fn.name] = {
        node = id,
        fn = s.fn.name,
        line = s.fn.line,
        signature = s.fn.signature or s.fn.name,
      }
      hit = true
    end
  end
  return hit, (hit and approximate) or false
end

---Every call edge that targets `node`/`fn` — the direct callers, which is
---the precise half of "where does this radiate". Reads `ir.edges` rather
---than a derived index because call edges are only ever consumed this way;
---`node.requires`/`required_by` exist as indexes because the graph views
---walk them repeatedly.
---@param ir Lib.Docmap.IR
---@param node string
---@param fn string
---@return Lib.Docmap.History.Caller[]
function M.callers(ir, node, fn)
  local out = {}
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" and e.to == node and e.to_fn == fn then
      out[#out + 1] = { node = e.from, fn = e.from_fn, line = e.line }
    end
  end
  table.sort(out, function(a, b)
    if a.node ~= b.node then
      return a.node < b.node
    end
    if a.fn ~= b.fn then
      return a.fn < b.fn
    end
    return (a.line or 0) < (b.line or 0)
  end)
  return out
end

---Analyse one diff against the IRs of the revisions it sits between.
---
---`ir_after` is the map at the revision itself, `ir_before` the map at its
---parent. Both optional — see the module header on degradation.
---@param diff_text string Raw `git diff --unified=0` output.
---@param ir_after Lib.Docmap.IR|nil
---@param ir_before Lib.Docmap.IR|nil
---@return Lib.Docmap.History.Impact
function M.analyze(diff_text, ir_after, ir_before)
  local files = M.parse_diff(diff_text)
  local after_index = ir_after and index_by_source(ir_after) or nil
  local before_index = ir_before and index_by_source(ir_before) or nil

  local touched_set = {}
  local changed_files, unattributed = {}, {}
  local approximate = false

  for _, f in ipairs(files) do
    local path = f.new_path or f.old_path
    if path then
      changed_files[#changed_files + 1] = path
      local a, a_approx = collect_side(ir_after, after_index, f.new_path, f.new, touched_set)
      local b, b_approx = collect_side(ir_before, before_index, f.old_path, f.old, touched_set)
      approximate = approximate or a_approx or b_approx
      if not a and not b then
        unattributed[#unattributed + 1] = path
      end
    end
  end

  local touched = {}
  for _, t in pairs(touched_set) do
    touched[#touched + 1] = t
  end
  table.sort(touched, function(x, y)
    if x.node ~= y.node then
      return x.node < y.node
    end
    return x.fn < y.fn
  end)

  -- Callers are resolved against `ir_after` only: "who calls this now" is
  -- the actionable question. Resolving against the parent too would report
  -- callers that the commit itself may have just removed.
  local callers, module_set = {}, {}
  if ir_after then
    for _, t in ipairs(touched) do
      local list = M.callers(ir_after, t.node, t.fn)
      callers[t.node .. "#" .. t.fn] = list
      for _, c in ipairs(list) do
        module_set[c.node] = true
      end
    end
  end

  -- The coarser, transitive answer alongside the precise one: every module
  -- that would be affected by changing the modules the diff touched, via
  -- `required_by`. `deps.impact` already owns that walk — the same one
  -- `:LibBrowse gI` and `diff.lua` use, so all three agree by construction.
  local reachable = {}
  if ir_after then
    local deps = require("lib.nvim.docmap.deps")
    local seen = {}
    for _, t in ipairs(touched) do
      if not seen[t.node] then
        seen[t.node] = true
        for _, id in ipairs(deps.impact(ir_after, t.node)) do
          reachable[id] = true
        end
      end
    end
  end

  ---@param set table<string, boolean>
  ---@return string[]
  local function sorted_keys(set)
    local out = {}
    for k in pairs(set) do
      out[#out + 1] = k
    end
    table.sort(out)
    return out
  end

  table.sort(changed_files)
  table.sort(unattributed)

  return {
    files = changed_files,
    touched = touched,
    callers = callers,
    calling_modules = sorted_keys(module_set),
    impacted_modules = sorted_keys(reachable),
    unattributed = unattributed,
    approximate = approximate,
  }
end

---Turn an `Impact` into quickfix entries.
---
---Here rather than in `command.lua` for the same reason `diff.render` is in
---`diff.lua`: the analysis and the shape of its answer belong together, and
---keeping the command a thin git-and-UI shell means this half stays testable
---without a repository. A CI job that wants the same list gets it without an
---editor.
---
---Two entry kinds, in the order a reviewer reads them: each touched function
---at its declaration, then its call sites indented beneath it. The call sites
---are the actionable half — "these places run the code you changed" — and
---they are real locations, which is the whole reason this is a quickfix list
---rather than a message.
---
---`unattributed` files come last. They are still information (they explain
---why the count is lower than the diff looks), but they are not findings, so
---they must not push the actionable entries down.
---@param impact Lib.Docmap.History.Impact
---@param ir Lib.Docmap.IR Resolves node ids to files and module names.
---@param root string Absolute repo root; quickfix wants absolute paths.
---@return { filename: string, lnum: integer, col: integer, text: string }[]
function M.quickfix_items(impact, ir, root)
  local items = {}

  ---@param id string
  ---@return string
  local function node_file(id)
    local n = ir.nodes[id]
    return root .. "/" .. ((n and n.source) or id)
  end

  for _, t in ipairs(impact.touched) do
    local callers = impact.callers[t.node .. "#" .. t.fn] or {}
    items[#items + 1] = {
      filename = node_file(t.node),
      lnum = t.line or 1,
      col = 1,
      text = ("changed: %s   (%d caller%s)"):format(
        t.signature or t.fn,
        #callers,
        #callers == 1 and "" or "s"
      ),
    }
    for _, c in ipairs(callers) do
      items[#items + 1] = {
        filename = node_file(c.node),
        lnum = c.line or 1,
        col = 1,
        text = ("  ← %s calls it   (%s)"):format(
          c.fn or "?",
          (ir.nodes[c.node] or {}).module or c.node
        ),
      }
    end
  end

  for _, path in ipairs(impact.unattributed) do
    items[#items + 1] = {
      filename = root .. "/" .. path,
      lnum = 1,
      col = 1,
      text = "changed, nothing to trace (not a scanned function)",
    }
  end

  return items
end

return M
