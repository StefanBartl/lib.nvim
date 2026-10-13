# `lib.nvim.contract.api`

The **one door of a machine contract**: `call(method, request)` answers with a
JSON document, never with a throw. Moved here from `tasks_nvim.api`
(tasks.nvim@921a0c4); the mechanics are generic, the table of methods is the
plugin's.

Everything outside the engine (an app, an agent, CI) asks through here and gets
the canonical bytes of one document of the contract
([`contract.doc`](../doc/README.md)): the answer, or an error document with a
stable code ([`contract.errors`](../errors/README.md)) and whether asking again
can help.

```lua
local api = require("lib.nvim.contract.api").make({
  doc = d,                                     -- lib.nvim.contract.doc
  methods = {
    hello = { params = {}, run = function(_, opts) return contract.hello(opts) end },
    rule = {
      params = { id = "string" },
      required = { "id" },
      run = function(p, opts) return contract.rule(p.id, opts) end,
    },
  },
  engine_opts = { "root" },                    -- keys of call's opts handed to run
  root_of = function(engine_opts) return resolve_root(engine_opts) end,
  patterns = PATTERNS,                         -- the plugin's error-message patterns
})

local text, code = api.call("rule", '{"params":{"id":"LUA-12"}}', { root = root })
-- code is nil for an answer, else the error code; text is always a document
```

## The request

A JSON object `{ "schema": 1, "params": { ... } }`, as text or already decoded.
`schema` may be left out (it is 1), a higher one is `unsupported_schema`;
`params` may be left out too. A request is at most 256 KiB. **A field or
parameter the method does not know is `invalid_argument`**: a request that is
silently half-understood is worse than one that is refused. A top-level `null`
is the same as leaving the field out.

| Method key | Meaning |
|---|---|
| `params` | `name = type`. Types: `string`, `boolean`, `integer`, `number`, `object`, `string_list`, `object_list`, and the plugin's own (`cfg.types`). A value is checked, never coerced. |
| `required` | Parameters that must be given: `<method> needs the parameter <name>` (checked after the unknown-parameter check). |
| `flat` | The parameters are the request's own fields (a write door), not under `params`. |
| `keep_null` | A JSON `null` stays `vim.NIL` (it means "remove" in a patch) instead of being absent. |
| `run(params, opts)` | Answers a document table, or `nil` and an error: a `contract.errors` table, or a text that `classify` turns into one by the patterns. May raise: that is `internal` with the message scrubbed. |

## Config of `make`

| Key | Default | |
|---|---|---|
| `doc` | required | A `contract.doc` instance (schema, plugin, error kind, `encode`, `error_doc`). |
| `methods` | required | `name -> method`. Checked where it is made: a wrong shape, an unknown type or a `required` without a parameter raises at once (position of the caller). |
| `engine_opts` | `{ "root" }` | Keys of `call`'s opts that `run` receives. |
| `root_of(engine_opts, opts)` | `engine_opts.root` | The root to hide in an error message. The plugin resolves it the way its engine does (a source that cannot be found is named in the message, and the path the caller gave is still a path of this machine). |
| `patterns` | none | The plugin's own message patterns for `classify`. |
| `types` | none | `name -> function(value) -> boolean`. |
| `max_request_bytes` | 256 KiB | Also the field `api.MAX_REQUEST_BYTES`, read at call time. |

## The instance

| | |
|---|---|
| `call(name, request?, opts?)` | `text, code`. `opts.indent` makes the text readable (golden files). Never raises. |
| `methods()` | The names, sorted. |
| `METHODS` | The plugin's table (a host reads `flat` from it). |
| `MAX_REQUEST_BYTES` | Seam. |
| `minimal_error(code, message)` | The smallest valid error document as text, for the moment the real one cannot be made (it did not encode, the host failed). `call` uses it as its last resort. |

Not its job: building a document (`contract.doc`, the plugin) and the command
line.

## Checked against `tasks_nvim.api`

Built from `tasks.nvim`'s own `METHODS` (and with `tasks_nvim.json` replaced by
[`json.canonical`](../../json/canonical/README.md)), this dispatcher answers 93
requests (reads, errors, a 876 KB snapshot, write requests as dry runs) against a
real vault **byte for byte** like `tasks_nvim.api.call`.
