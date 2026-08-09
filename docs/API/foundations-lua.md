# API Reference — `lib.lua.*` (editor-independent foundations)

Part of the [lib.nvim API reference](README.md). Every module here is pure
Lua with **no** dependency on the `vim` global — usable outside Neovim.
Aggregator (`lib.lua`) lazily dispatches to every submodule below via
`__index`, so `require("lib.lua").trim(...)` and
`require("lib.lua.strings").trim(...)` reach the same function.

For narrative usage examples, see each module's own `README.md` next to its
source (linked inline as "(see README)"); this document lists every public
function signature so you can scan for "does X already exist" without
opening files one by one.

---

## Strings — `lib.lua.strings.*`

`lib.lua.strings` (aggregator, `strings/init.lua`, see README) eagerly
flattens every submodule below onto one table — `strings.trim`,
`strings.split`, `strings.slugify`, etc. all resolve directly.

### `lib.lua.strings.core` (see README)
Trimming, splitting, joining, casing, padding, indenting.

```
S.trim(s: any): string
S.starts_with(s: string, prefix: string): boolean
S.ends_with(s: string, suffix: string): boolean
S.contains(s: string, needle: string): boolean
S.split(s: string, sep: string): string[]
S.join(parts: string[], sep: string): string
S.replace_all(s: string, from: string, to: string): string
S.normalize_ws(s: string): string|nil
S.capitalize(s: string): string
S.uncapitalize(s: string): string
S.slugify(s: string): string
S.kebab_case(s: string): string
S.snake_case(s: string): string
S.camel_case(s: string): string
S.pad_start(s: string, width: integer): string
S.pad_end(s: string, width: integer): string
S.pad_center(s: string, width: integer): string
S.indent(s: string, n: integer): string
S.dedent(s: string): string
S.is_empty_or_space(s: any): boolean
S.count_lines(s: string): integer
```

### `lib.lua.strings.case` (see README)
Case-shape detection/reapplication, distinct from `core`'s case-format
converters.

```
M.case_shape(word: string): "lower"|"upper"|"capital"|"mixed"
M.apply_shape(word: string, shape: "lower"|"upper"|"capital"|"mixed"): string
M.change_case(str: string, mode: "title"|"sentence"|"upper"|"lower"): string
```

### `lib.lua.strings.patterns` (see README)
Escaping, plain find/replace, surrounding, ANSI stripping.

```
P.escape_lua_magic(s: string): string
P.find_plain(s: string, needle: string): integer|nil start, integer|nil finish
P.replace_plain(s: string, from: string, to: string): string
P.surround(s: string, left: string, right: string): string
P.strip_ansi(s: string): string   -- SGR + OSC sequences + null bytes + a broader CSI catch-all
```

### `lib.lua.strings.links` (see README)
URI decode, anchor normalization, simple scanners.

```
M.uri_decode(s: string): string
M.normalize_anchor(s: string): string
M.has_scheme(s: string): boolean
M.is_web_url(s: string): boolean
M.url_under_cursor(line: string, col: integer): string|nil
```

### `lib.lua.strings.utf8` (see README)
Minimal UTF-8 codepoint encode/decode (Lua 5.1/LuaJIT compatible, no
external dependency).

```
M.char_len(lead_byte: integer): integer          -- 1-4
M.encode(cp: integer): string
M.decode(str: string, i?: integer): integer|nil cp, integer next_i
M.iter(str: string): fun(): integer|nil, integer|nil   -- codepoint, byte_index
```

### `lib.lua.strings.encoding` (see README)
Percent-encoding (URL) and base64.

```
M.url_encode(str: string): string
M.url_decode(str: string): string
M.base64_encode(data: string): string
M.base64_decode(data: string): string
```

### `lib.lua.strings.distance` (see README)

```
M.levenshtein(a: string, b: string): integer
M.similarity(a: string, b: string): number
```

### `lib.lua.strings.format` (see README)
Human-readable number/byte-size formatting.

```
M.format_bytes(n: integer, decimals?: integer): string   -- decimals default 1
M.format_number(n: number, sep?: string): string          -- sep default ","
```

### `lib.lua.strings.location` (see README)
Parse `"path:line:col"`-style location strings out of arbitrary text (grep
output, compiler errors, stack traces).

```
M.parse_location(str: string): { path: string, line: integer|nil, col: integer|nil } | nil
```

### `lib.lua.strings.remove_prefix` (see README)
Module itself is a function.

```
return function(s: string, list: table): string
```

### `lib.lua.strings.wrap` (see README)
Word-aware text centering.

```
M.center_text(str: string, width: integer): string
M.center_text_lines(lines: string[], width: integer): string[]
```

### `lib.lua.strings.transform` (aggregator, see README)
A curated subset re-export of `strings` — casing/padding/trim/prefix-remover
only: `remove_prefix, trim, slugify, kebab_case, snake_case, camel_case,
capitalize, uncapitalize, normalize_ws, pad_start, pad_end, pad_center,
indent, dedent`.

### `lib.lua.strings.convert.hex_to_string` (no README)
Converts a hex codepoint string (e.g. `"F0056"`) to a UTF-8 character via
`vim.fn.nr2char`. **Note:** unlike the rest of this namespace, this one file
does depend on `vim.fn` — not actually editor-independent.

```
return function(hex: string): string   -- "" on invalid input
```

---

## Tables — `lib.lua.tables.*`

`lib.lua.tables` (aggregator, see README) lazily re-exports `array` / `core`
/ `dict` (dict-prefixed: `dict_clone`, `dict_pick`, …) / `set` / `safe`.
**Not** re-exported through the aggregator — require these three directly:
`lib.lua.tables.functional`, `lib.lua.tables.unique_table`,
`lib.lua.tables.with`.

### `lib.lua.tables.array` (see README)
Helpers for dense `Array<T>` (contiguous `1..n` lists); preallocated
outputs, single-pass where possible.

```
M.len(xs): integer
M.clone(xs): table                          -- shallow copy
M.map(xs, f): table
M.filter(xs, pred): table
M.reduce(xs, f, init): any
M.partition(xs, pred): pass, fail
M.flatten(xss): table                       -- one level of nesting
M.unique(xs): table                         -- dedup by ==, order preserved
M.pluck(xs, key): table                     -- skips nils
M.sorted(xs, cmp): table                    -- sorts a copy, non-mutating
```

### `lib.lua.tables.core` (see README)
Shape checks, copies, key/value helpers, merging, slicing. Pure unless
marked mutating.

```
M.is_table(t): boolean
M.is_array(t): boolean                      -- empty or dense 1..n
M.shallow_copy(t): table
M.deep_copy(t): table                       -- cycle-safe
M.keys(t): string[]
M.values(t): table
M.invert_set(list): table<string, true>
M.pick(t, pick_keys): table
M.omit(t, omit_keys): table
M.merge_shallow(dst, src): table            -- mutates + returns dst, one level
M.merge_deep(dst, src): table                -- recursive
M.deep_merge(dst, src): table                -- same as merge_deep, explicit-contract name
M.dedup_list(list): table
M.dedup_indices(list, key_fn): table        -- indices to drop, pure
M.slice(list, i, j): table                  -- Python-style negative indices
M.unique_push(list, v): boolean             -- push only if absent
M.binary_search(list, cmp, x): index, found -- list must be pre-sorted
M.group_by(list, key): table<K, T[]>
M.partition(list, pred): pass, fail
M.count_by(list, key): table<K, integer>
```

### `lib.lua.tables.dict` (see README)
Exposed on the aggregator with a `dict_` prefix to avoid clashing with
array-oriented names.

```
M.clone(t): table
M.pick(t, keys): table                      -- skips absent keys
M.omit(t, keys): table
M.merge(a, b): table                        -- new table, b wins on conflicts
M.keys(t): table
M.values(t): table
M.group_by(xs, keyfn): table<K, T[]>
```

### `lib.lua.tables.set` (see README)
Generic `Set<T>` as `table<T, true>`, no wrapper object/metatable.

```
M.from_array(xs): table
M.to_array(s): table                        -- no order guarantee
M.add(s, v): nil                            -- mutates
M.add_all(s, xs): nil                       -- mutates
M.remove(s, v): nil                         -- mutates
M.remove_all(s, xs): nil                    -- mutates
M.clear(s): nil                             -- mutates
M.has(s, v): boolean
M.size(s): integer
M.copy(s): table
M.from_keys(t): table
M.union(a, b): table
M.intersection(a, b): table
M.difference(a, b): table                   -- a \ b
M.symmetric_difference(a, b): table
M.is_subset(a, b): boolean
M.is_superset(a, b): boolean
M.equals(a, b): boolean
M.filter(s, pred): table                    -- aggregator: set_filter
M.map(s, fn): table                         -- aggregator: set_map
M.iter(s): fun                              -- iterator
```

### `lib.lua.tables.safe` (see README)
Safe, defensive mutators and iteration guards.

```
S.ensure_list(list): table
S.ensure_table(t): table
S.push(list, v): integer                    -- new length
S.pop(list): any|nil
S.insert_at(list, idx, v): boolean ok
S.remove_at(list, idx): boolean ok
S.snapshot_shallow(t): table
S.safe_ipairs(list): fun                    -- snapshots #list up front
```

### `lib.lua.tables.functional` (no README — require directly, not aggregated)

```
F.map(list: T[], fn: fun(item:T, index:integer):U): U[]
F.filter(list: T[], pred: fun(item:T, index:integer):boolean): T[]
F.reduce(list: T[], init: U, fn: fun(acc:U, item:T, index:integer):U): U
F.find(list: T[], pred: fun(item:T, index:integer):boolean): T|nil
F.any(list: T[], pred: fun(item:T):boolean): boolean
F.all(list: T[], pred: fun(item:T):boolean): boolean
F.flat_map(list: T[], fn: fun(item:T):U[]): U[]
```

### `lib.lua.tables.unique_table` (no README — require directly, not aggregated)

```
M.unique(list): table
M.unique_by(list, key_fn): table
M.is_unique(list): boolean
```

### `lib.lua.tables.with` (no README — require directly, not aggregated)
Module itself is a function.

```
return function(base: table|nil, extra: table|nil): table
```

---

## Functional / meta helpers — `lib.lua.functions.*`

### `lib.lua.functions` (aggregator, see README)
Tiny, allocation-free helpers — re-exports `functions.meta`'s 6 functions.

### `lib.lua.functions.meta`

```
M.noop(): nil
M.identity(v: T): T
M.always_true(): boolean
M.always_false(): boolean
M.const(value: T): fun(): T
M.raise(err: any): nil       -- always calls error(err, 0)
```

---

## Encoding formats — JSON / YAML / UUID

### `lib.lua.json` (aggregator, see README)
Aggregates `decode` and `encode` below.

### `lib.lua.json.decode` (see README)
**Not a JSON text parser** — coerces an already-decoded value (or arbitrary
string/table/scalar) into a `string[]`.

```
M.is_array_like(v: any): boolean                    -- strict contiguous 1..n keys only
M.table_to_string_array(tbl: table): string[]        -- dict-shaped -> sorted "key: value" pairs
M.ensure_string_array(v: any): string[]               -- strings split on \n, else tostring
```

### `lib.lua.json.encode` (see README)
Pure-Lua JSON encoder (does not delegate to `vim.json.encode`, for
cross-runtime consistency). Callable module:
`require("lib.lua.json.encode")(value) == M.encode(value)`.

```
M.encode(value: any, opts?: Lib.JSON.EncodeOpts): string|nil encoded, string|nil err
M.pretty(value: any, opts?: Lib.JSON.EncodeOpts): string|nil, string|nil   -- indent defaults to 2
```
`opts`: `indent` (integer=spaces, string=literal unit, nil/0/""=compact), `sort_keys` (default `true`).

### `lib.lua.yaml` (see README)
Deliberately minimal, dependency-free YAML-ish decoder — no anchors/aliases,
multi-doc streams, flow style, or block scalars.

```
M.simple_parse(text: string): table|nil data, string|nil err
```

### `lib.lua.uuid` (see README)
UUIDv4 generation/formatting. **Not** cryptographically secure.

```
M.generate(): string uuid                                    -- lowercase, hyphenated
M.format(uuid: string, style?: "compact"|"upper"|"braced"): string
M.get(style?: "compact"|"upper"|"braced"): string             -- = format(generate(), style)
```

---

## Time / date

No top-level `lib.lua.time` aggregator — require the three submodules
directly.

### `lib.lua.time.diff` (see README)
High-precision timer with checkpoint tracking. Module is callable (returns
a factory); each `require()` call yields an **independent timer instance**,
auto-started on creation.

```
instance.start(): nil
instance.check(unit?: "ns"|"us"|"ms"|"s"): number elapsed
instance.result(unit?): number|nil total
instance.get(idx: integer, unit?): number|nil elapsed
instance.fastest(unit?): number|nil
instance.longest(unit?): number|nil
instance.average(unit?): number|nil
instance.median(unit?): number|nil
instance.stddev(unit?): number|nil          -- nil if < 2 checkpoints
instance.cv(): number|nil                    -- coefficient of variation %, nil if < 2 checkpoints
instance.calc_diff(iv1, iv2, unit?): number|nil   -- index / "average"|"fastest"|"longest"|"median" / raw value
instance.next(label?: string, unit?): string|number|nil        -- iterator
instance.reset_iterator(label?: string, show_index?: boolean): nil
instance.results(unit?): string             -- summary of all checkpoints
instance.pretty(unit?): string              -- formatted table
-- callable / __tostring: diff() / print(diff) == diff.results()
```

### `lib.lua.time.format` (see README)
Formats a unix timestamp using named style presets.

```
M.format_timestamp(ts?: integer, fmt?: "iso"|"human"|"short"|"log"|"filename"|"unix", opts?: table): string
```

### `lib.lua.time.presets` (see README)
Date-range preset resolver (pure `os.time`/`os.date`). All presets accept
optional `now` for reproducibility.

```
M.today(now?: integer): { from: integer, to: integer }
M.yesterday(now?: integer): { from, to }
M.last_week(now?: integer): { from, to }        -- last 7 full days, not calendar Mon-Sun
M.this_month(now?: integer): { from, to }
M.this_quarter(now?: integer): { from, to }
M.this_year(now?: integer): { from, to }
M.custom(from: integer, to: integer): { from, to } | nil range, string|nil err
```

---

## Numeral conversion

### `lib.lua.numeral` (aggregator, see README)
Bundles `roman` and `alpha`.

### `lib.lua.numeral.roman`
Roman numeral conversion (1-3999).

```
M.to_roman(n: integer): string|nil, string|nil err   -- "out of range"
M.to_int(s: string): integer|nil, string|nil err     -- "invalid roman numeral"; rejects non-canonical forms
```

### `lib.lua.numeral.alpha`
Bijective base-26 conversion (spreadsheet-column style: a...z, aa, ab...).

```
M.to_alpha(n: integer): string|nil, string|nil err   -- "out of range"
M.to_int(s: string): integer|nil
```

---

## Diff / dump / error handling

### `lib.lua.diff` (aggregator, see README)
Two line-diff strategies.

### `lib.lua.diff.lines`
Cheap common-prefix/common-suffix trim producing a single splice region —
fast "did anything change" check.

```
M.diff(a: string[], b: string[]): { start, a_end, b_end } | nil   -- 1-based inclusive; nil if arrays equal
```

### `lib.lua.diff.myers`
Correct full line-diff via O(n·m) DP LCS backtrack, producing an ordered
edit script.

```
M.diff(a: string[], b: string[]): { op: "equal"|"insert"|"delete", value: string }[]
```

### `lib.lua.dump` (see README)
Recursive Lua value dumper (alternative/complement to `vim.inspect`), hard
recursion-depth limit against cycles/huge structures.

```
M.to_lines(value: any, opts?: {max_depth?: integer}): string[]   -- max_depth default 30
M.to_string(value: any, opts?: {max_depth?: integer}): string
```

### `lib.lua.error` (see README)
Structured-error + safe-call-with-traceback convention.

```
M.new(kind: string, message: string, data?: any): LibErrorValue   -- {kind, message, data, __lib_error=true}
M.is(value: any): boolean
M.safe_call(fn: function, ...: any): boolean ok, any ...           -- xpcall w/ debug.traceback
```

---

## Infrastructure — lazy loading, memoization

### `lib.lua.lazy` (see README)
Reusable lazy-module-loading helpers — avoids eager `require()` at startup.

```
lazy.module(name: string): Lib.LazyModule       -- wrapper object; call .get() for the module
lazy.require(name: string): T                    -- returns the module directly, cached (recommended)
lazy.fn(module: string, function_name: string): function   -- re-binds after first call
```

### `lib.lua.memo` (aggregator, see README)
Small, self-contained caching infrastructure — Neovim-independent.

```
M.lru   -- = lib.lua.memo.lru submodule
M.memo  -- = lib.lua.memo.memo submodule
M.fn(func: fun(...):any, opts?: table|integer): fun(...):any   -- memoize with default settings
```

### `lib.lua.memo.lru`
Classic LRU cache: O(1) get/put, hashmap + doubly linked list.

```
Lru.new(cap: integer): Lib.Memo.Lru   -- factory, cap >= 1
Lru:get(key: any): any|nil            -- moves entry to head
Lru:put(key: any, value: any): nil    -- overwrites, moves to head, evicts LRU on overflow
```

### `lib.lua.memo.memo`
Memoization wrapper based on `lru.lua`.

```
M.memoize(fn: fun(...):any, cap?: integer, keyer?: fun(...):string): fun(...):any
  -- default cap 128; default key = table.concat({...}, "\31"); nil results not cached
M.memoize2(fn: fun(...):any, cap?: integer, keyer?: fun(...):string): fun(...):any
  -- same contract; default keyer is vim.inspect-based instead of naive table.concat
  -- (fixes a string-concat bug with complex/table arguments)
```
