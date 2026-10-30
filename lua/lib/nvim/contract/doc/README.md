# `lib.nvim.contract.doc`

The **documents of a machine contract** (`tasks-export/1`, `rules-export/1`):
the head every document starts with, `seal` (`rev` and `digest`), `encode`
(canonical bytes, size limit) and the error document. Moved here from the
head/seal/encode part of `tasks_nvim.contract` (tasks.nvim@6bc8d99). What a
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

local json = require("lib.nvim.json.canonical")

local doc = d.head(d.kind("snapshot"), root)     -- kind "rules.snapshot"
doc.rules = json.memo(rules)                     -- the big part: written once for the digest, reused by encode
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
| `plugin_root` | none | The checkout whose commit `engine.git` names; a non-empty path (trailing slashes are dropped, `/` and `C:/` stay as they are). |
| `max_bytes` | 8 MiB | Largest document: a whole number from 1. |
| `too_large_hint` | `ask for a page or an area` | Advice in the `payload_too_large` message. |
| `prewarm` | `false` | `true` calls `d.prewarm()` right away: the git lookup of `engine.git` starts in the background. |

A wrong config raises with the position of the caller (a programmer error): every
key is checked, not only `plugin` and `schema`. `schema` is a whole number (not
`inf`); `kind_prefix`, `scope_key`, `placeholder` and `plugin_root` are non-empty
strings when given, `engine_version` and `too_large_hint` strings, `max_bytes` a
whole number from 1, `prewarm` a boolean. A `scope_key` must not be a field of the documents themselves
(`schema`, `plugin`, `kind`, `generated_at`, `engine`, `rev`, `digest`, `code`,
`message`, `retryable`, `details`): it would overwrite that field in every head.

## The head

```json
{ "schema": 1, "plugin": "rules.nvim", "kind": "rules.hello",
  "generated_at": "2026-01-01T00:00:00Z", "source": { "id": "wkdbook-Lua" },
  "engine": { "version": "0.1.0", "git": "abc1234", "nvim": "0.11.0+v0.11.0" } }
```

`source.id` is the last part of the root, however the root is spelled (either
slash, a trailing slash); a root without a name (`""`, `/`, `C:/`) gives `""`.
`engine.nvim` is `tostring(vim.version())`: no leading `v`, with the build
metadata (`0.12.2+v0.12.2`; a nightly looks like `0.13.0-dev+g<hash>`). Like all of
`engine` it is not part of the digest.

`engine.git` is the short commit of `plugin_root`. A definite answer is kept for
the life of the instance; a lookup that did not finish in time is asked again,
three times at most (the first look waits 2 s, a retry 0.5 s); git saying there
is no commit stays `unknown`. Only the commit of `plugin_root` **itself** counts:
git is asked for `--show-toplevel` too, and a `plugin_root` that is no checkout
of its own (a folder inside another repo: `git -C` walks up) is `unknown`, not
the commit of the repo above it (both sides resolved with `fs_realpath`, case
ignored on Windows and macOS). Git runs without the variables that would point
it at another repository (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`,
`GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`,
`GIT_NAMESPACE`): a host started from a git hook inherits them, and they win
over `-C`. The lookup is synchronous: the first `head()` (or
`engine_info()`) of an instance waits for git, usually about 100 ms on a warm
machine, up to 2 s on a loaded one. A command-line tool does not notice.

An editor host that answers on the UI loop calls `d.prewarm()` once while it
starts (or passes `prewarm = true` to `new`): git runs in the background
(`vim.system` with a callback and a 2 s timeout) and its answer fills the same
cache under the same rules (a timeout is one of the three tries, a retry later
is synchronous with 0.5 s). A `head()` while that lookup still runs does not
wait: it says `unknown` for that document, caches nothing and counts no try, so
the next document after the callback carries the commit. `prewarm()` does
nothing when the answer is known, a lookup runs already, or there is no
`plugin_root`.

## Sealing

`seal(doc, rev)` sets `rev` (what the source looked like; `rev_of(lines)` hashes
lines the plugin builds, one per item as `id<TAB>etag`, order does not matter; the
lines are sorted by byte value, not by locale) and
`digest`, the hash of the compact document **without `generated_at` and
`engine`**: two runs on an unchanged source have the same digest, whenever and by
whichever build of the engine they ran.

`seal` writes the whole compact document once, and `encode` writes it again.
Wrap the big part in `json.memo(t)` ([`json.canonical`](../../json/canonical/README.md))
and the second pass reuses the text of the first; `t` must not change after
`seal`. Digest and bytes are the same with and without it, only the cost differs.

A value JSON cannot hold (NaN, `inf`, a function, a cycle) makes `seal` **raise**
with the message `encode` would give (the path in the document, e.g.
`json: $.rules[1].score is nan; ...`, no file:line), and the document is left as it
was (time, engine, `rev`, `digest`). `d.encode(d.seal(doc, rev))` therefore raises
for such a document; call `encode` on it first, or `pcall` the seal, when the
document is built from foreign values.

## Nothing of this machine in a document

| | |
|---|---|
| `relative(root, path)` | `path` relative to the root with `/`, or `nil` when not inside (case-insensitive, either slash). `.` and `..` segments and doubled slashes are resolved as text first (root and path): `<root>/../x` is **not** inside. No disk access, so a symlink is not followed. An empty root is no root: nothing is inside it. |
| `safe_path(root, s)` | Inside the root: relative. Absolute (`/x`, `C:/x`, resolved like `relative`) or `~`: `<external>/<name>` (`<root>/a/..` is `<external>/<name of the root>`). Else as it is. With an empty root every absolute path is external. |
| `redact(root, s)` | The root in a message, in any slash spelling (either slash, mixed) and any case, becomes the placeholder. A root without a name (`""`, `/`) hides nothing. One pass: the cost follows the length of the text, not the number of hits. |

The root may be spelled with either slash, mixed, and with a trailing slash
(`C:\Users\me\vault`, `C:/Users/me/vault/`): all three functions and the head see
the same root, so the plugin does not have to normalise it first. "Any case" means
Unicode letters too (`Ö` and `ö` are one folder on NTFS): a letter beyond ASCII is
folded with Vim's simple case mapping. The few letters whose lower case has another
length in bytes (`İ`, `Ⱥ`, the Kelvin sign) and a byte that is no UTF-8 are compared
as they are.

## Encoding

`encode(doc, opts)` gives the canonical bytes
([`json.canonical`](../../json/canonical/README.md)); `opts.indent` the readable
form. A document over `MAX_DOC_BYTES` is the error `payload_too_large`, never a
cut-off document; the error document (`<prefix>.error`) is exempt. A value JSON
cannot hold is `internal` with the path, not a raise (this is `encode` alone: a
`seal` before it raises, see Sealing).

`error_doc(err, root)` builds `<prefix>.error` from a
[`contract.errors`](../errors/README.md) table; the message is redacted when a
root is given, `details` is always an object. A malformed `err` is made into a
document, never a throw: a value that is no table is an `internal` error with its
text, a `message` that is no text is shown as one (the `code` when there is none),
a `code` that is no text is `internal` (the document always has a code a client
can match), `details` that is no table is left out.

## Seams

`clock()` (`generated_at`), `engine_info()` (`engine`) and `MAX_DOC_BYTES` are
fields of the instance, read at call time: a spec or a golden-file run replaces
them (the real `engine_info` asks Neovim for its version once per instance, not on
every head). A plugin that exposes them on its own module forwards them:

```lua
d.clock = function() return M.clock() end
d.engine_info = function() return M.engine_info() end
```
