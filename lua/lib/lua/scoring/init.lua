---@module 'lib.lua.scoring'
--- Additive score: a base value plus a list of NAMED bonuses and maluses, clamped to a range, with a
--- `details` breakdown that shows every contribution one by one (what made 87 out of 100, not just 87).
---
--- Pure Lua, no `vim`. Generalised from the scoring of `learn-cli.nvim`.
---
--- ```lua
--- local scoring = require("lib.lua.scoring")
---
--- local s = scoring.new({ base = 50, min = 0, max = 100 })
--- s:bonus("no hints used", 20)
--- s:malus("typos", 7)
--- s:bonus("fast", 40, elapsed < 30) -- only counted when the condition is true
---
--- local r = s:result()
--- r.score    --> 100   (50 + 20 - 7 + 40 = 103, clamped)
--- r.raw      --> 103
--- r.clamped  --> "max"
--- r.details  --> { { name = "no hints used", delta = 20, total = 70 }, ... }
--- ```

local M = {}

---@class Lib.Scoring.Opts
---@field base? number                              # Starting value (default 0).
---@field min? number                               # Lower bound of the score (default none).
---@field max? number                               # Upper bound of the score (default none).
---@field round? "floor"|"ceil"|"nearest"|false     # Rounding of the final score (default none).

---@class Lib.Scoring.Detail
---@field name string
---@field delta number   # Signed contribution.
---@field total number   # Running total after this contribution (before clamping).

---@class Lib.Scoring.Result
---@field score number              # `raw` clamped to `min`/`max` (and rounded).
---@field raw number                # base + every delta, unclamped, unrounded.
---@field base number
---@field clamped "min"|"max"|nil   # Which bound cut the score, if one did.
---@field details Lib.Scoring.Detail[]

---@class Lib.Scoring.Builder
---@field add fun(self: Lib.Scoring.Builder, name: string, delta: number, applies?: boolean): Lib.Scoring.Builder
---@field bonus fun(self: Lib.Scoring.Builder, name: string, points: number, applies?: boolean): Lib.Scoring.Builder
---@field malus fun(self: Lib.Scoring.Builder, name: string, points: number, applies?: boolean): Lib.Scoring.Builder
---@field result fun(self: Lib.Scoring.Builder): Lib.Scoring.Result

---@param v any
---@return boolean
local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---@param opts Lib.Scoring.Opts|nil
---@return Lib.Scoring.Opts
local function checked(opts)
  opts = opts or {}
  if opts.base ~= nil and not finite(opts.base) then
    error("lib.lua.scoring: base must be a finite number", 3)
  end
  for _, key in ipairs({ "min", "max" }) do
    if opts[key] ~= nil and not finite(opts[key]) then
      error(("lib.lua.scoring: %s must be a finite number"):format(key), 3)
    end
  end
  if opts.min ~= nil and opts.max ~= nil and opts.min > opts.max then
    error("lib.lua.scoring: min must not be greater than max", 3)
  end
  local r = opts.round
  if r ~= nil and r ~= false and r ~= "floor" and r ~= "ceil" and r ~= "nearest" then
    error('lib.lua.scoring: round must be "floor", "ceil", "nearest" or false', 3)
  end
  return opts
end

---Score a list of contributions at once.
---@param entries { name: string, delta: number, applies?: boolean }[]
---@param opts? Lib.Scoring.Opts
---@return Lib.Scoring.Result
function M.compute(entries, opts)
  opts = checked(opts)
  if type(entries) ~= "table" then
    error("lib.lua.scoring.compute: entries must be a list", 2)
  end
  local base = opts.base or 0
  local total, details = base, {}
  for i, e in ipairs(entries) do
    if type(e) ~= "table" or type(e.name) ~= "string" or e.name == "" then
      error(("lib.lua.scoring.compute: entries[%d] needs a name"):format(i), 2)
    end
    if not finite(e.delta) then
      error(("lib.lua.scoring.compute: entries[%d] (%s) needs a finite delta"):format(i, e.name), 2)
    end
    if e.applies ~= false then
      total = total + e.delta
      details[#details + 1] = { name = e.name, delta = e.delta, total = total }
    end
  end

  local score, clamped = total, nil
  if opts.min ~= nil and score < opts.min then
    score, clamped = opts.min, "min"
  elseif opts.max ~= nil and score > opts.max then
    score, clamped = opts.max, "max"
  end
  if opts.round == "floor" then
    score = math.floor(score)
  elseif opts.round == "ceil" then
    score = math.ceil(score)
  elseif opts.round == "nearest" then
    score = math.floor(score + 0.5)
  end
  return { score = score, raw = total, base = base, clamped = clamped, details = details }
end

---@class Lib.Scoring.BuilderState : Lib.Scoring.Builder
---@field private entries { name: string, delta: number, applies?: boolean }[]
---@field private opts Lib.Scoring.Opts
local Builder = {}
Builder.__index = Builder

---@param name string
---@param delta number  # signed
---@param applies? boolean  # `false` leaves the contribution out (nothing is listed)
---@return Lib.Scoring.Builder
function Builder:add(name, delta, applies)
  self.entries[#self.entries + 1] = { name = name, delta = delta, applies = applies }
  return self
end

---@param name string
---@param points number  # added as given
---@param applies? boolean
---@return Lib.Scoring.Builder
function Builder:bonus(name, points, applies)
  return self:add(name, points, applies)
end

---@param name string
---@param points number  # subtracted: `malus("typos", 7)` is -7, whichever sign was passed
---@param applies? boolean
---@return Lib.Scoring.Builder
function Builder:malus(name, points, applies)
  if finite(points) then
    points = -math.abs(points)
  end
  return self:add(name, points, applies)
end

---@return Lib.Scoring.Result
function Builder:result()
  return M.compute(self.entries, self.opts)
end

---A builder: collect contributions with `bonus`/`malus`/`add`, read the outcome with `result`.
---@param opts? Lib.Scoring.Opts
---@return Lib.Scoring.Builder
function M.new(opts)
  return setmetatable({ entries = {}, opts = checked(opts) }, Builder)
end

return M
