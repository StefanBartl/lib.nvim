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
  60 characters, never inside one: a request may be 256 KiB. The names are the
  client's, so the echo is printable: a control character (ESC, BEL, a C1
  control, a Unicode line separator) is written as an escape (`\x1b`,
  `\u009b`), a byte that is no UTF-8 as U+FFFD.
- The document is sealed (`digest`, no `rev`). **One entry never costs the
  answer for the others**: a value JSON cannot hold in an entry (`NaN`, a whole
  number of 2^53 or more, nesting deeper than 64) turns that entry into an
  `internal` one (`the operation ran, but its entry cannot be reported: ...`,
  with its place in the document), keeping `n`, `op` and `changed_ids`; `ok` is
  false. The operations did run, and a client that is told nothing would repeat
  the writes. Only a document that cannot be sealed for another reason makes
  `run` answer `nil, internal`; it never raises.
- The text of `doc.results` is remembered when the document is sealed
  (`json.memo`: the answer of `contract.api` reuses it instead of writing the
  entries a second time), so a caller must not change `doc.results` after `run`
  returns.

## Config of `make`

| Key | Default | |
|---|---|---|
| `doc` | required | A `contract.doc` instance. |
| `ops` | required | `name -> { fields = { name = type }, run }`. Checked where it is made (position of the caller). A field that is not listed is refused. |
| `order` | byte order of the names | The order the "operations: ..." message names them in. |
| `context(params, opts)` | `{ root = opts.root }` | Builds `ctx` (needs `root`, a text, to hide it); `nil, err` refuses the request (after the shape check): `run` answers `nil, err` as an error of the contract (`failure`: a text is classified and the root hidden). `ctx.dry` is set by the door. |
| `finish(ctx, results)` | none | Once after the last operation, **also on a dry run** (look at `ctx.dry`). May change the entries (the index of every area that changed); `ok` is judged after it, on the entries it left. If it raises, `ok` is false and the document says why in `finish_error`. |
| `types` | none | `name -> { is, label }`: the plugin's own field types, refused as "<field> must be <label>". |
| `limits` | `{ batch_ops = 100, client_op_id = 64 }` | |
| `patterns` | none | The plugin's own error-message patterns for `failure`. |

Field types: `string` ("text"), `object` ("an object"), `strings` ("text or a
list of text"), `integer` ("a whole number from 1 to 999999"), `boolean`.

## The instance

| | |
|---|---|
| `run(params, opts)` | `doc, nil` or `nil, err` (always an error of the contract: `{ code, message, retryable }`). Fits the `run` of a `contract.api` method. |
| `method()` | The `contract.api` method entry: `flat`, `keep_null`, `client_op_id`/`dry_run`/`ops`. |
| `check_shape(params)` | `nil` or the `invalid_argument`/`payload_too_large` error. |
| `failure(root, err, info?)` | The entry of an operation that did not happen: `contract.errors.classify` (the plugin's patterns), the root hidden (first, so a root with a space in it is found), `details` an object; an error with a code and no message shows the code. |
| `refuse(code, message, details?)` | The same with a code of your own. |
| `OPS`, `limits` | The names and the sizes. |

Guards for the handlers, on the module: `has_control(value)` (a control
character — a CR or a form feed too, so a CRLF text is refused —, a C1 control,
a Unicode line separator or text that is not valid UTF-8, in a text or a list
of texts: it must not reach a source from a front end) and `too_long(text,
max)` (characters, not bytes; a NUL counts as one character, `has_control` is
what refuses it, so the order of the two does not matter).

## Checked against `tasks_nvim.ops`

Built with the field tables of `tasks_nvim.ops`, the shape check answers 35
malformed requests with the **same code and the same message** as
`tasks_nvim.ops.run`. Differences, on purpose: the first fault is the first in
byte order (the original followed `pairs`), `dry_run` is typed, an operation
that is no object is `ops[n]: must be an object` (the original raised), a
table as operation name is shown as `<table>` and a JSON `null` as `null`, a
whole-number field is refused as `a whole number from 1 to 999999` (the
original said `from 1`), and
an operation or field name in a refusal is cut at 60 characters and made
printable (the original echoed it in full).
