# `lib.nvim.contract.api`

The **one door of a machine contract**: `call(method, request)` answers with a
JSON document, never with a throw. Moved here from `tasks_nvim.api`
(tasks.nvim@6bc8d99); the mechanics are generic, the table of methods is the
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
`schema` may be left out (it is 1), a higher one is `unsupported_schema`, one
that is no whole number (a fraction, `NaN`, infinity) is `invalid_argument`;
`params` may be left out too. A request is at most 256 KiB. **A field or
parameter the method does not know is `invalid_argument`**: a request that is
silently half-understood is worse than one that is refused. A top-level `null`
is the same as leaving the field out.

The text is **UTF-8 without a byte order mark**. A request that starts with a
BOM (U+FEFF) is `invalid_argument` with a message that names the BOM (not "not
valid JSON", which would send the client after a syntax error it does not
have); it is not stripped silently.

What a method sees after decoding: an empty `[]` and an empty `{}` are both an
empty Lua table, so a parameter that may be either cannot tell them apart (the
types `object`, `string_list` and `object_list` all accept `{}`). Without
`keep_null` a `null` inside an object or a list is `nil`: a trailing one
shortens a list, one in the middle leaves a hole, so the list is no list any
more and a list type refuses it. With `keep_null` it is `vim.NIL`, in lists too.

The checks run in a fixed order: the **schema first** (a request of a newer
schema is always `unsupported_schema`, also when it carries a field or, for a
flat method, a parameter this engine does not know: that is version skew, not a
typo), then the request's fields, the parameter types, the unknown parameters
and the required ones. Where one check finds several faults (two unknown fields,
two parameters of the wrong type) the **alphabetically first** is the one told,
so the same request gets the same answer in every process.

The names of a request that a refusal repeats (an unknown method, field or parameter) are echoed through
[`contract.echo`](../echo/README.md): at most 60 characters, valid UTF-8, a control character written as an escape.

| Method key | Meaning |
|---|---|
| `params` | `name = type`. Types: `string`, `boolean`, `integer`, `number`, `object`, `string_list`, `object_list`, and the plugin's own (`cfg.types`). A value is checked, never coerced. An `integer` or `number` is finite and below 2^53 in magnitude, the numbers the contract's JSON ([`json.canonical`](../../json/canonical/README.md)) can hold: one it would refuse to write is `invalid_argument` here, not `internal` later. |
| `required` | Parameters that must be given: `<method> needs the parameter <name>` (checked after the unknown-parameter check). |
| `flat` | The parameters are the request's own fields (a write door), not under `params`. |
| `keep_null` | A JSON `null` stays `vim.NIL` (it means "remove" in a patch) instead of being absent. |
| `run(params, opts)` | Answers a document table, or `nil` and an error: a `contract.errors` table, or a text that `classify` turns into one by the patterns. A third value `info` (`{ code, retryable?, id/key/expected/actual/written/writes }`, the shape `fs.with_lock` and the other functions of the lib give) makes the code come from the source and keeps the details, so a method may simply `return fs.with_lock(...)`; only a table counts as `info`, any other third value is ignored, and a `contract.errors` table as the second value wins over it. May raise: that is `internal` with the message scrubbed; a raised value that is no text (an error table) is shown by its `message`, else by its type, never by its address (`errors.text`). A malformed error table (no `message`, a `message` that is no text, `details` that is no table) is coerced into a document by `error_doc`, not thrown on. |

## Config of `make`

| Key | Default | |
|---|---|---|
| `doc` | required | A `contract.doc` instance (schema, plugin, error kind, `encode`, `error_doc`). |
| `methods` | required | `name -> method`. Checked where it is made: a wrong shape, an unknown type or a `required` without a parameter raises at once (position of the caller). |
| `engine_opts` | `{ "root" }` | Keys of `call`'s opts that `run` receives. A list of non-empty texts, checked where it is made. |
| `root_of(engine_opts, opts)` | `engine_opts.root` | A function (checked where it is made). The root to hide in an error message. The plugin resolves it the way its engine does (a source that cannot be found is named in the message, and the path the caller gave is still a path of this machine). The root may be spelled with either slash and a trailing slash (`C:\Users\me\vault`, `C:/Users/me/vault/`): `contract.doc` hides and names it alike, so the default needs no normalising. |
| `patterns` | none | The plugin's own message patterns for `classify`. The shape is checked where `make` is called (`errors.check_patterns`): a rule that is not `{ code = string, find = string[] }` raises at once, with the position of the caller, instead of failing later when a message reaches it. `nil` and `false` mean none. |
| `types` | none | `name -> function(value) -> boolean`, names not empty; checked where it is made. |
| `max_request_bytes` | 256 KiB | A whole number of 1 or more, checked where it is made. Also the field `api.MAX_REQUEST_BYTES`, read at call time. |

Every key of the config is checked where `make` is called, and a wrong one
raises with the position of the caller. What is changed **afterwards** is not:
a method added to `api.METHODS` later (or a `MAX_REQUEST_BYTES` set later) is
taken as it is at call time, and a malformed one answers `internal`.

## The instance

| | |
|---|---|
| `call(name, request?, opts?)` | `text, code`. `opts.indent` makes the text readable (golden files). Never raises, even when a hook of the plugin does: a `root_of`, a type function of `cfg.types` or a name with an `__tostring` that raises, an `opts` that is no table, a bug in `run`, an error document that cannot be made (a `root_of` that answers no text, a `doc` that raises). The answer is a document with code `internal` and the scrubbed message (with the root hidden where the root is known), at worst `minimal_error`. |
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
