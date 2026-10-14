# `lib.nvim.contract.ops`

The **write door of a machine contract**: a list of operations, answered with
one `<prefix>.result` document. Moved here from the shell of `tasks_nvim.ops`
(tasks.nvim@921a0c4); what an operation *does* (`set`, `new`, `retire`, ...)
stays with the plugin as a handler.

A front end that is not the editor (an app, an agent) changes the source only
through here. A request is

```json
{ "schema": 1, "client_op_id": "c-81f2", "dry_run": false, "ops": [ { "op": "set", "id": "..." } ] }
```

```lua
local door = require("lib.nvim.contract.ops").make({
  doc = d,                                  -- lib.nvim.contract.doc
  order = { "set", "new" },                 -- the order the messages name the operations in
  ops = {
    set = { fields = { id = "string", patch = "object", if_match = "string" }, run = do_set },
    new = { fields = { title = "string", body = "string" }, run = do_new },
  },
  context = function(params, opts) return { root = opts.root } end,  -- or: nil, err
  finish = function(ctx, results) end,     -- once, at the end
})

methods.ops = door.method()                 -- the entry for contract.api
```

A handler is `run(op, ctx) -> entry`: `entry.ok` (boolean), `outcome`,
`error`, `changed_ids`, `etag_before`/`etag_after`, `inverse`, ... are the
plugin's own. `ctx.dry` says dry run: check everything, write nothing.

## Rules the door keeps

- **The shape is checked first, for the whole request.** An unknown operation or
  field, a wrong type, too many operations is `invalid_argument` (or
  `payload_too_large`) and **nothing runs**. The fault that is told is the first
  in byte order (the fields of an operation, then the operations), the same in
  every process.
- After that every operation runs on its own: one that fails does not stop the
  others. This is **not all-or-nothing**, and `ok` is true only if every entry is.
- **A handler never takes the door down.** One that raises, or answers nothing,
  is an `internal` entry with the message scrubbed and the root hidden; the
  others still run.
- **No path of this machine in an entry**: `failure` and the `internal` entry
  hide the root ([`contract.doc`](../doc/README.md)).
- `null` for a field is the same as leaving it out; the handler never sees
  `vim.NIL` as an op field (inside a `patch` it stays: it means "remove").
- A request text echoed in a refusal (an operation name, a field name) is cut at
  60 characters: a request may be 256 KiB.
- The document is sealed (`digest`, no `rev`); a value JSON cannot hold in an
  entry makes `run` answer `nil, internal` (with the path in the document), never
  raise.

## Config of `make`

| Key | Default | |
|---|---|---|
| `doc` | required | A `contract.doc` instance. |
| `ops` | required | `name -> { fields = { name = type }, run }`. Checked where it is made (position of the caller). A field that is not listed is refused. |
| `order` | byte order of the names | The order the "operations: ..." message names them in. |
| `context(params, opts)` | `{ root = opts.root }` | Builds `ctx` (needs `root`, a text, to hide it); `nil, err` refuses the request (after the shape check). `ctx.dry` is set by the door. |
| `finish(ctx, results)` | none | Once after the last operation, **also on a dry run** (look at `ctx.dry`). May change the entries (the index of every area that changed). If it raises, `ok` is false and the document says why in `finish_error`. |
| `types` | none | `name -> { is, label }`: the plugin's own field types, refused as "<field> must be <label>". |
| `limits` | `{ batch_ops = 100, client_op_id = 64 }` | |
| `patterns` | none | The plugin's own error-message patterns for `failure`. |

Field types: `string` ("text"), `object` ("an object"), `strings` ("text or a
list of text"), `integer` ("a whole number from 1", below 1e6), `boolean`.

## The instance

| | |
|---|---|
| `run(params, opts)` | `doc, nil` or `nil, err`. Fits the `run` of a `contract.api` method. |
| `method()` | The `contract.api` method entry: `flat`, `keep_null`, `client_op_id`/`dry_run`/`ops`. |
| `check_shape(params)` | `nil` or the `invalid_argument`/`payload_too_large` error. |
| `failure(root, err, info?)` | The entry of an operation that did not happen: `contract.errors.classify` (the plugin's patterns), the root hidden, `details` an object. |
| `refuse(code, message, details?)` | The same with a code of your own. |
| `OPS`, `limits` | The names and the sizes. |

Guards for the handlers, on the module: `has_control(value)` (a control
character, a C1 control or a Unicode line separator in a text or a list of
texts: it must not reach a source from a front end) and `too_long(text, max)`
(characters, not bytes).

## Checked against `tasks_nvim.ops`

Built with the field tables of `tasks_nvim.ops`, the shape check answers 35
malformed requests with the **same code and the same message** as
`tasks_nvim.ops.run`. Differences, on purpose: the first fault is the first in
byte order (the original followed `pairs`), `dry_run` is typed, an operation
that is no object is `ops[n]: must be an object` (the original raised), and a
table as operation name is shown as `<table>`.
