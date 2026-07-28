# `lib.nvim.normalize`

A small, dependency-free normalization toolkit for plugin configs: strict
coercion at the config boundary (int/float/bool/enum/string/list/path/
severity/log-level) plus a couple of schema-merging utilities. Pure functions
throughout, except the (currently unexported) `apply_*` convention the module
doc-comment reserves for mutating helpers.

Neovim APIs are used opportunistically (`vim.fs.normalize`, `vim.uv`) and
fall back gracefully when unavailable.

```lua
local normalize = require("lib.nvim.normalize")
```

Backed by two lazily-required submodules, [`validators.lua`](validators.lua)
and [`utils.lua`](utils.lua) — `init.lua` just flattens both onto one table.

## Direct value normalizers (pure coercion, no error channel)

```lua
normalize.to_bool("yes")            --> true    -- true/yes/on/1, false/no/off/0 (case-insensitive); nil for anything else
normalize.to_int("3.7")             --> 3        -- truncates toward zero
normalize.to_int("3.7", 0, 2)       --> 2         -- clamped into [min, max]
normalize.to_float("1.005", nil, nil, 2)  --> 1.0   -- rounded to `precision` fractional digits
normalize.to_string(v, allow_empty, do_trim)  -- nil unless v is a string (and non-empty unless allow_empty)
normalize.to_enum("Warn", { "warn", "error" })      --> "warn"  -- case-insensitive by default
normalize.to_string_list("a, b,c", { trim = true, dedup = true })  --> { "a", "b", "c" }
normalize.to_argv('a "b c" d')       --> { "a", "b c", "d" }  -- best-effort shell-token split, double-quote segments only
normalize.to_diagnostic_severity("warn")  --> vim.diagnostic.severity.WARN
normalize.to_log_level("debug")      --> vim.log.levels.DEBUG
normalize.to_path("~/x", "directory", true)  -- expand + vim.fs.normalize, then require it to exist and match the type
```

Every one of these returns `nil` (not an error) on unparseable/invalid
input — callers combine them with `or default`.

## Validators with an `(ok, val, err)` contract

```lua
local ok, n, err = normalize.as_int("inner_pad", user.inner_pad, 0, false)
if not ok then return false, nil, err end

local ok2, b, err2 = normalize.as_bool("auto_width", user.auto_width)
```

`as_int(name, v, min, allow_nil)`: `v == nil` and `allow_nil` → `true, nil,
nil`; `v == nil` and not `allow_nil` → `false, nil, "<name> is required"`; a
non-integer number → `"<name> must be an integer"`; below `min` →
`"<name> must be ≥ <min>"`. `as_bool(name, v)` accepts **only** real Lua
booleans — no string coercion (use `to_bool` + your own apply step for
that). These exist for config boundaries that want a single user-facing error
message without throwing, and the parsed value returned instead of being
re-parsed at the call site.

```lua
normalize.is_one_of(v, { "a", "b", "c" })  -- plain ==, no coercion
normalize.buf_valid(bufnr)                  -- number + nvim_buf_is_valid
normalize.win_valid(winid)                  -- number + nvim_win_is_valid
```

## Utilities

```lua
normalize.trim(s)                    -- non-string -> ""
normalize.clamp(n, min, max)         -- either bound may be nil (unbounded)
normalize.coalesce(a, b, c)          -- first non-nil argument
normalize.path_kind(p)               -- "file" | "directory" | "" (via vim.uv.fs_stat)
normalize.normalize_path(p)          -- ~/$VAR/%VAR% expansion (lib.nvim.cross.fs.expand_path) then vim.fs.normalize
normalize.dedup_strings(list)        -- order-preserving, string entries only
```
