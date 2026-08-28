-- scripts/bench_dispatcher.lua — native autocmds vs. the dispatcher: what
-- does the dispatcher cost?
--
--   nvim --clean -u NONE -c "set rtp+=." -l scripts/bench_dispatcher.lua
--
-- The dispatcher's own README says it does MORE work per event than native
-- dispatch: one autocmd fires for every occurrence and the matching happens
-- in Lua instead of C. This measures how much more, at 1 / 5 / 20 / 50
-- handlers, in the two cases that differ:
--
--   HIT   the event carries a key that has handlers -- both must run them
--   MISS  the event carries a key that has none -- native filters in C,
--         the dispatcher has to look and find nothing
--
-- MISS is the case that decides it. In a real session almost every BufEnter
-- is for an ordinary file, not for the one buffer a handler cares about, so
-- the miss path is the one that runs thousands of times a day.
--
-- The event is `User`, deliberately. A first attempt used FileType and
-- measured nothing useful: `nvim_exec_autocmds("FileType", …)` also runs
-- Neovim's own ftplugin and syntax machinery, which costs ~1.8ms per fire and
-- buried the difference completely -- the "miss" case even came out slower
-- than the "hit" case, because filetype=lua loads a real ftplugin. `User` has
-- no built-in listeners, so what is left is the dispatch itself.
--
-- Not a `TESTS/*_spec.lua`: this asserts nothing, it reports timing, which
-- varies run to run and machine to machine. Rerun it after touching the
-- dispatcher's dispatch-mode path if you want to know whether that changed.

local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")

local ITERATIONS = 2000
local RUNS = 5
local COUNTS = { 1, 5, 20, 50 }

local HIT_KEY = "BenchHit"
local MISS_KEY = "BenchMiss"

--- Median of `runs` timed repetitions, in milliseconds. Median, not mean: one
--- GC pause in the middle would otherwise decide the result.
---@param runs integer
---@param fn fun(): nil
---@return number
local function measure(runs, fn)
  local samples = {}
  for i = 1, runs do
    local t0 = vim.uv.hrtime()
    fn()
    samples[i] = (vim.uv.hrtime() - t0) / 1e6
  end
  table.sort(samples)
  return samples[math.ceil(#samples / 2)]
end

local fired = 0

---@param key string
---@return nil
local function fire(key)
  for _ = 1, ITERATIONS do
    vim.api.nvim_exec_autocmds("User", { pattern = key, modeline = false })
  end
end

--- One row: absolute median, and microseconds per single event.
---@param label string
---@param n integer
---@param hit number
---@param miss number
---@return nil
local function row(label, n, hit, miss)
  print(
    ("%-10s %-8d %8.2f %8.2f   %7.2f %7.2f"):format(
      label,
      n,
      hit,
      miss,
      hit / ITERATIONS * 1000,
      miss / ITERATIONS * 1000
    )
  )
end

print(("%d Events pro Messung, Median aus %d Laeufen"):format(ITERATIONS, RUNS))
print("")
print(
  ("%-10s %-8s %8s %8s   %7s %7s"):format(
    "variante",
    "handler",
    "hit ms",
    "miss ms",
    "hit us",
    "miss us"
  )
)
print(("-"):rep(56))

for _, n in ipairs(COUNTS) do
  -- ── native: n autocmds, each filtered by pattern in C ───────────────────
  local grp = vim.api.nvim_create_augroup("BenchNative", { clear = true })
  for _ = 1, n do
    vim.api.nvim_create_autocmd("User", {
      group = grp,
      pattern = HIT_KEY,
      callback = function()
        fired = fired + 1
      end,
    })
  end
  local nat_hit = measure(RUNS, function()
    fire(HIT_KEY)
  end)
  local nat_miss = measure(RUNS, function()
    fire(MISS_KEY)
  end)
  vim.api.nvim_del_augroup_by_id(grp)

  -- ── dispatcher: one autocmd, n handlers, matching in Lua ────────────────
  local d = dispatcher.new({
    event = "User",
    group = "BenchDispatch",
    key = function(ev)
      return ev.match
    end,
  })
  for _ = 1, n do
    d.register(HIT_KEY, function()
      fired = fired + 1
    end)
  end
  d.attach()

  local dis_hit = measure(RUNS, function()
    fire(HIT_KEY)
  end)
  local dis_miss = measure(RUNS, function()
    fire(MISS_KEY)
  end)
  d.detach()

  row("nativ", n, nat_hit, nat_miss)
  row("dispatch", n, dis_hit, dis_miss)
  print(
    ("%-10s %-8s %8s %8s   hit x%.2f  miss x%.2f"):format(
      "faktor",
      "",
      "",
      "",
      dis_hit / math.max(nat_hit, 0.0001),
      dis_miss / math.max(nat_miss, 0.0001)
    )
  )
  print("")
end

-- ── the control that makes the numbers above readable ──────────────────────
--
-- Without this, "the dispatcher is 30x slower on a miss" sounds like the
-- dispatcher's own logic is expensive. It is not: entering Lua at all costs
-- that much, and a native autocmd whose pattern does not match never enters.
do
  local function bare(pattern, setup)
    local grp = vim.api.nvim_create_augroup("BenchControl", { clear = true })
    if setup then
      setup(grp)
    end
    local ms = measure(RUNS, function()
      fire(pattern)
    end)
    vim.api.nvim_del_augroup_by_id(grp)
    return ms / ITERATIONS * 1000
  end

  print("")
  print("Kontrolle -- woher der Aufschlag kommt:")
  print(("  %-40s %6.2f us"):format("kein autocmd registriert", bare(MISS_KEY)))
  print(
    ("  %-40s %6.2f us"):format(
      "1 autocmd, pattern passt nicht (C-Filter)",
      bare(MISS_KEY, function(grp)
        vim.api.nvim_create_autocmd(
          "User",
          { group = grp, pattern = HIT_KEY, callback = function() end }
        )
      end)
    )
  )
  print(
    ("  %-40s %6.2f us"):format(
      "1 autocmd, leerer lua-callback laeuft",
      bare(HIT_KEY, function(grp)
        vim.api.nvim_create_autocmd(
          "User",
          { group = grp, pattern = HIT_KEY, callback = function() end }
        )
      end)
    )
  )
  print("")
  print("  Der Sprung nach Lua kostet das, nicht der Dispatcher.")
end

print(("(callbacks gefeuert: %d)"):format(fired))
