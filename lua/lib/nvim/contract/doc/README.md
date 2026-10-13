# `lib.nvim.contract.doc`

The **documents of a machine contract** (`tasks-export/1`, `rules-export/1`):
the head every document starts with, `seal` (`rev` and `digest`), `encode`
(canonical bytes, size limit) and the error document. Moved here from the
head/seal/encode part of `tasks_nvim.contract` (tasks.nvim@921a0c4). What a
document *contains* (snapshot, list, a rule) stays with the plugin.

`doc.new{...}` returns the builder of ONE plugin's contract:

```lua
local d = require("lib.nvim.contract.doc").new({
  plugin = "rules.nvim",        -- named in every head
  schema = 1,                   -- the version of the contract
  scope_key = "source",         -- head field naming the source (default "vault")
  engine_version = "0.1.0",
  plugin_root = plugin_root,    -- for engine.git; without it "unknown", git is never started
})

local doc = d.head(d.kind("snapshot"), root)     -- kind "rules.snapshot"
doc.rules = rules
local text, err = d.encode(d.seal(doc, d.rev_of(lines)))
if not text then
  text = d.encode(d.error_doc(err, root))        -- an error document is always encodable
end
```

## Config

| Key | Default | |
|---|---|---|
| `plugin` | required | The plugin named in every head. |
| `schema` | required | Whole number from 1. |
| `kind_prefix` | plugin without `.nvim` | `d.kind("hello")` is `<prefix>.hello`; `<prefix>.error` is the error kind. |
| `scope_key` | `vault` | Head field `{ id = <basename of root> }`. Part of the bytes (golden files). |
| `placeholder` | `<scope_key>` | What `redact` writes for the root, e.g. `<vault>`. |
| `engine_version` | `0.0.0` | The engine's own version (not the contract's). |
| `plugin_root` | none | The checkout whose commit `engine.git` names. |
| `max_bytes` | 8 MiB | Largest document. |
| `too_large_hint` | `ask for a page or an area` | Advice in the `payload_too_large` message. |

A wrong config raises with the position of the caller (a programmer error).

## The head

```json
{ "schema": 1, "plugin": "rules.nvim", "kind": "rules.hello",
  "generated_at": "2026-01-01T00:00:00Z", "source": { "id": "wkdbook-Lua" },
  "engine": { "version": "0.1.0", "git": "abc1234", "nvim": "v0.11.0" } }
```

`engine.git` is the short commit of `plugin_root`. A definite answer is kept for
the life of the instance; a lookup that did not finish in time is asked again,
three times at most (the first look waits 2 s, a retry 0.5 s); git saying there
is no commit stays `unknown`.

## Sealing

`seal(doc, rev)` sets `rev` (what the source looked like; `rev_of(lines)` hashes
lines the plugin builds, one per item as `id<TAB>etag`, order does not matter) and
`digest`, the hash of the compact document **without `generated_at` and
`engine`**: two runs on an unchanged source have the same digest, whenever and by
whichever build of the engine they ran.

## Nothing of this machine in a document

| | |
|---|---|
| `relative(root, path)` | `path` relative to the root with `/`, or `nil` when not inside (case-insensitive, either slash). |
| `safe_path(root, s)` | Inside the root: relative. Absolute (`/x`, `C:/x`) or `~`: `<external>/<name>`. Else as it is. |
| `redact(root, s)` | The root in a message, in both slash spellings and any case, becomes the placeholder. An empty root hides nothing. |

## Encoding

`encode(doc, opts)` gives the canonical bytes
([`json.canonical`](../../json/canonical/README.md)); `opts.indent` the readable
form. A document over `MAX_DOC_BYTES` is the error `payload_too_large`, never a
cut-off document; the error document (`<prefix>.error`) is exempt. A value JSON
cannot hold is `internal` with the path, not a raise.

`error_doc(err, root)` builds `<prefix>.error` from a
[`contract.errors`](../errors/README.md) table; the message is redacted when a
root is given, `details` is always an object.

## Seams

`clock()` (`generated_at`), `engine_info()` (`engine`) and `MAX_DOC_BYTES` are
fields of the instance, read at call time: a spec or a golden-file run replaces
them. A plugin that exposes them on its own module forwards them:

```lua
d.clock = function() return M.clock() end
d.engine_info = function() return M.engine_info() end
```
