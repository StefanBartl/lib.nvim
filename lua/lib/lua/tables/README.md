# `lib.lua.tables`

Aggregates every table helper under `lib.lua.tables.*` onto one flat table.
Pure Lua, no `vim` API. Unlike `lib.lua.strings`, `init.lua` here goes through
`lib.lua.lazy` — each submodule (`array`, `core`, `dict`, `set`, `safe`) is
only `require`d the first time one of its functions is actually read off `M`.

```lua
local tables = require("lib.lua.tables")
```

## Array ops ([`array.lua`](array.lua))

High-performance helpers for dense `Array<T>` (contiguous `1..n` lists) —
preallocated outputs, single-pass where possible.

```lua
tables.len(xs)                  -- #xs
tables.clone(xs)                -- shallow copy
tables.map(xs, function(v) return v * 2 end)
tables.filter(xs, function(v) return v > 0 end)
tables.reduce(xs, function(acc, v) return acc + v end, 0)
tables.partition(xs, pred)      --> pass, fail
tables.flatten(xss)             -- one level of nesting
tables.unique(xs)                -- dedup by ==, order preserved
tables.pluck(items, "name")     -- items[i].name, skipping nils
tables.sorted(xs, cmp)          -- sort a *copy*, does not mutate xs
```

## Core utilities ([`core.lua`](core.lua))

Shape checks, copies, key/value helpers, merging, slicing.

```lua
tables.is_table(v)              -- type(v) == "table"
tables.is_array(t)               -- contiguous 1..#t keys, no stray non-int keys beyond #t
tables.shallow_copy(t)
tables.deep_copy(t)              -- cycle-safe (tracks seen tables, preserves shared identity)
tables.keys(t)                   -- string keys only
tables.values(t)
tables.invert_set(list)          -- string[] -> table<string, true>
tables.pick(t, { "a", "b" })
tables.omit(t, { "a" })
tables.merge_shallow(dst, src)   -- mutates + returns dst, one level deep
tables.merge_deep(dst, src)      -- recursive merge when both sides are tables
tables.deep_merge(dst, src)      -- same recursive rule as merge_deep, distinct name/contract for callers who want the right-biased-recursive semantics explicit
tables.dedup_list(list)          -- dedup by == , order preserved
tables.dedup_indices(list, key_fn)  -- indices to DROP so only first-per-key survives (pure, does not mutate)
tables.slice(list, i, j)         -- Python-style negative indices supported
tables.unique_push(list, v)      -- push v only if not already present (O(n) scan); returns whether it was added
tables.binary_search(list, cmp, x)  --> index, found  (list must be sorted per cmp)
tables.group_by(list, key_fn)    --> table<K, T[]>
tables.count_by(list, key_fn)    --> table<K, integer>
```

`merge_deep` and `deep_merge` currently implement the identical recursive
merge rule (nested-table-into-nested-table recurses, anything else is
overwritten right-biased) — kept as two names for call-site clarity, not two
behaviors.

## Dictionary ops ([`dict.lua`](dict.lua))

Exposed with a `dict_` prefix on the aggregator to avoid clashing with the
array-oriented names above.

```lua
tables.dict_clone(t)
tables.dict_pick(t, keys)        -- skips keys not present in t
tables.dict_omit(t, keys)
tables.dict_merge(a, b)          -- new table, b wins on key conflicts
tables.dict_keys(t)
tables.dict_values(t)
tables.dict_group_by(xs, keyfn)  -- array of items -> table<key, items[]>
```

## Set ops ([`set.lua`](set.lua))

A set is a plain `table<T, true>` — no wrapper object, no metatable.

```lua
local s = tables.from_array({ 1, 2, 3 })
tables.add(s, 4)
tables.has(s, 4)                 --> true
tables.size(s)                   --> 4
tables.to_array(s)                -- no order guarantee
tables.from_keys(t)               -- set of t's keys
tables.union(a, b)
tables.intersection(a, b)         -- iterates the smaller of the two sets
tables.difference(a, b)           -- a \ b
tables.symmetric_difference(a, b)
tables.is_subset(a, b)
tables.is_superset(a, b)
tables.equals(a, b)
tables.set_filter(s, pred)
tables.set_map(s, fn)             -- collisions (two keys mapping to one) dedup naturally
for v in tables.iter(s) do ... end
```

`add`/`add_all`/`remove`/`remove_all`/`clear` mutate the set in place and
return nothing.

## Safe / defensive ops ([`safe.lua`](safe.lua))

```lua
tables.ensure_list(maybe_nil)     -- maybe_nil or {}  (any non-table -> {})
tables.ensure_table(maybe_nil)
tables.push(list, v)              --> new length
tables.pop(list)                  --> removed value, or nil if empty
tables.insert_at(list, idx, v)    --> boolean ok (false if idx out of [1, #list+1])
tables.remove_at(list, idx)       --> boolean ok
tables.snapshot_shallow(t)
for i, v in tables.safe_ipairs(list) do ... end  -- snapshots #list up front,
                                                   -- safe against mutation during iteration
```
