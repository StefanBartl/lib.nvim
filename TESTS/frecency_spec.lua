-- TESTS/frecency_spec.lua — lib.nvim.frecency
--
-- What these assertions protect, in order of how quietly each would break:
--
--   1. **One handle per namespace.** Two handles on one file each hold their
--      own copy and overwrite the other on flush. That surfaces months later
--      as "my counts sometimes reset", on a machine that is not the one this
--      was written on.
--   2. **Recency beats raw frequency.** The whole point of frecency over a
--      visit counter is that something picked twice this hour outranks
--      something picked five times last year. A regression here still passes
--      any "does it count" test.
--   3. **A zero is absent, not present.** `lookup` omits keys that score
--      nothing, so no consumer has to test for both shapes.

return function(H)
  local eq, ok = H.eq, H.ok
  local frecency = require("lib.nvim.frecency")

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  ---A fresh store on its own namespace, never auto-flushing (a spec must not
  ---leave a `VimLeavePre` autocmd behind for every case it opens).
  ---@param namespace string
  ---@param opts? table
  local function open(namespace, opts)
    return frecency.store(
      vim.tbl_extend("force", { namespace = namespace, dir = dir, autoflush = false }, opts or {})
    )
  end

  -- --------------------------------------------------------------- scoring
  local s = open("scoring")

  eq(s:score("never-seen"), 0, "frecency: an unrecorded key scores zero")
  eq(next(s:lookup({ "never-seen" })), nil, "frecency: lookup omits a zero rather than listing it")

  s:record("/a/one.lua")
  ok(s:score("/a/one.lua") > 0, "frecency: a recorded key scores above zero")

  s:record("/a/two.lua")
  s:record("/a/two.lua")
  ok(
    s:score("/a/two.lua") > s:score("/a/one.lua"),
    "frecency: at equal recency, more visits scores higher"
  )

  -- Recency beats frequency: five visits a year ago against two just now.
  -- Written straight into the entry table via a reloaded store, because the
  -- alternative is a spec that waits a year.
  local stale = open("recency")
  stale:record("/old.lua")
  stale:flush()

  local path = dir .. "/recency.json"
  local f = assert(io.open(path, "r"), "frecency spec: the store file must exist after flush")
  local saved = vim.json.decode(f:read("*a"))
  f:close()
  saved.data["/old.lua"] = { count = 5, last = os.time() - 400 * 86400 }
  saved.data["/new.lua"] = { count = 2, last = os.time() }
  local fw = assert(io.open(path, "w"), "frecency spec: the store file must be writable")
  fw:write(vim.json.encode(saved))
  fw:close()

  stale:reset()
  ok(
    stale:score("/new.lua") > stale:score("/old.lua"),
    "frecency: two visits today outrank five from last year"
  )

  -- ------------------------------------------------------------ persistence
  local p = open("persist")
  p:record("/kept.lua")
  p:flush()
  p:reset()
  ok(p:score("/kept.lua") > 0, "frecency: a flushed visit survives a reload")

  p:clear()
  eq(p:score("/kept.lua"), 0, "frecency: clear forgets in memory")
  p:reset()
  eq(p:score("/kept.lua"), 0, "frecency: clear forgot on disk too")

  -- ----------------------------------------------------------------- weight
  -- An argument, not a store property: one handle, two weights, and the
  -- second must not be the first one frozen in. That is the whole reason it
  -- is not an option -- a handle lives for the session, a config value does
  -- not.
  local w = open("weighted")
  w:record("/w.lua")
  local plain_score = w:lookup({ "/w.lua" })["/w.lua"]
  local heavy_score = w:lookup({ "/w.lua" }, 10)["/w.lua"]
  ok(plain_score and heavy_score, "frecency: the key scored under both weights")
  ok(
    math.abs(heavy_score - plain_score * 10) < 0.001,
    "frecency: weight scales the looked-up score"
  )
  eq(w:score("/w.lua"), plain_score, "frecency: and leaves the stored score alone")

  -- --------------------------------------------------- one handle, one file
  local first = open("shared")
  local second = open("shared")
  ok(rawequal(first, second), "frecency: the same namespace returns the same handle")

  first:record("/shared.lua")
  ok(
    second:score("/shared.lua") > 0,
    "frecency: a visit recorded through one reference is visible through the other"
  )

  -- A different directory is a different store, even under the same name.
  local other_dir = vim.fn.tempname()
  vim.fn.mkdir(other_dir, "p")
  local elsewhere = frecency.store({ namespace = "shared", dir = other_dir, autoflush = false })
  ok(not rawequal(first, elsewhere), "frecency: dir is part of a store's identity")
  eq(elsewhere:score("/shared.lua"), 0, "frecency: and its entries do not leak across")

  -- ------------------------------------------------------------- guardrails
  ---@diagnostic disable-next-line: missing-fields
  eq(
    pcall(frecency.store, { dir = dir }),
    false,
    "frecency: a store without a namespace is refused, not silently shared"
  )

  -- Deliberately untyped: these are the shapes a caller gets wrong, and the
  -- store has to survive them rather than the annotation having to allow them.
  ---@type any
  local absent = nil

  local guards = open("guards")
  guards:record("")
  guards:record(absent)
  eq(guards:score(""), 0, "frecency: an empty key is not recorded")
  eq(guards:score(absent), 0, "frecency: nor scored")

  frecency._reset_handles()
end
