---@module 'lib.lua.memo.lru'
--- O(1) LRU cache using a hashmap + doubly linked list.

local Lru = {}
Lru.__index = Lru

--- Move a node to the front (most-recent).
---@param self Lib.Memo.Lru
---@param node Lib.Memo.LruNode
---@return nil
function Lru:_move_front(node)
  if self.head == node then
    return
  end
  -- unlink
  if node.prev then
    node.prev.next = node.next
  end
  if node.next then
    node.next.prev = node.prev
  end
  if self.tail == node then
    self.tail = node.prev
  end
  -- link at head
  node.prev = nil
  node.next = self.head
  if self.head then
    self.head.prev = node
  end
  self.head = node
  if not self.tail then
    self.tail = node
  end
end

--- Evict LRU (tail) node.
---@param self Lib.Memo.Lru
---@return nil
function Lru:_evict()
  local node = self.tail
  if not node then
    return
  end
  self.map[node.key] = nil
  if node.prev then
    node.prev.next = nil
  end
  self.tail = node.prev
  if self.head == node then
    self.head = nil
  end
  self.size = self.size - 1
end

--- Get a value by key; returns value or nil.
---@param self Lib.Memo.Lru
---@param key any
---@return any|nil
function Lru:get(key)
  local node = self.map[key]
  if not node then
    return nil
  end
  self:_move_front(node)
  return node.value
end

--- Put key/value; overwrites existing and moves to front.
---@param self Lib.Memo.Lru
---@param key any
---@param value any
---@return nil
function Lru:put(key, value)
  local node = self.map[key]
  if node then
    node.value = value
    self:_move_front(node)
    return
  end
  node = { key = key, value = value, prev = nil, next = nil }
  self.map[key] = node
  self.size = self.size + 1
  self:_move_front(node)
  if self.size > self.cap then
    self:_evict()
  end
end

--- Create new LRU cache with capacity >= 1.
---@param cap integer # Cache capacity (must be >= 1)
---@return Lib.Memo.Lru
local function new_lru(cap)
  -- Validate and sanitize capacity
  if type(cap) ~= "number" then
    error(("LRU.new: expected number, got %s"):format(type(cap)), 2)
  end

  ---@type Lib.Memo.LruState
  local state = {
    cap = math.max(1, math.floor(cap)),  -- KORREKTUR: Explizite Typsicherheit
    size = 0,
    map = {},
    head = nil,
    tail = nil,
  }
  setmetatable(state, Lru)
  ---@cast state Lib.Memo.Lru
  return state
end

return { new = new_lru }
