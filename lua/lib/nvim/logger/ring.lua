---@module 'lib.nvim.logger.ring'
--- Fixed-capacity ring buffer holding the most recent log records in memory.
--- Bounded by construction (like lib.lua.memo.lru) so a long session cannot
--- grow it without limit. This buffer is the crash-dump payload and the
--- `:LibLogger show` source.

local Ring = {}
Ring.__index = Ring

---@param capacity integer
---@return table
function Ring.new(capacity)
  capacity = math.max(1, tonumber(capacity) or 200)
  return setmetatable({
    _cap = capacity,
    _buf = {}, -- 1.._cap slots, filled cyclically
    _len = 0, -- number of live entries (<= _cap)
    _head = 0, -- index of the newest entry
  }, Ring)
end

---Append a record, evicting the oldest when full.
---@param record Lib.Logger.Record
function Ring:push(record)
  self._head = (self._head % self._cap) + 1
  self._buf[self._head] = record
  if self._len < self._cap then
    self._len = self._len + 1
  end
end

---Return a plain array of the live records, oldest -> newest.
---@return Lib.Logger.Record[]
function Ring:snapshot()
  local out = {}
  if self._len == 0 then
    return out
  end
  -- Oldest lives at (_head - _len + 1), walking forward cyclically.
  local start = (self._head - self._len + self._cap) % self._cap + 1
  for i = 0, self._len - 1 do
    local idx = (start - 1 + i) % self._cap + 1
    out[i + 1] = self._buf[idx]
  end
  return out
end

---@return integer
function Ring:len()
  return self._len
end

function Ring:clear()
  self._buf = {}
  self._len = 0
  self._head = 0
end

return Ring
