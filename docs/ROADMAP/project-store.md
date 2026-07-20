# `lib.nvim.store.project` — persistent, project-scoped state

> **Status:** proposal, not implemented. Surfaced while designing a
> renumbering-anchor feature for `cascade.nvim`
> ([concept doc](../../../cascade.nvim/docs/ROADMAP/renumbering_markers.md));
> a cross-repo scan afterwards showed the *storage* half of that concept is
> independently useful and already duplicated several times over.

## Problem

Several plugins need to persist small pieces of state **keyed by project**, so
that reopening the same project (possibly on a different machine, via synced
dotfiles/config) finds the same state again — as opposed to `lib.nvim.cache.disk`,
which is keyed by a caller-chosen `namespace` and has no notion of "which
project is this for".

Every one of them currently hand-rolls it:

| Repo | File | What it persists |
| --- | --- | --- |
| `sessions.nvim` | `lua/sessions/init.lua` | window/buffer layout, `project_aware` + `branch_aware` |
| `filetree.nvim` | `lua/filetree/features/org/session/init.lua` | tree scroll/cursor/expanded-dirs, explicitly "keyed by project root" |
| `language.nvim` | `lua/language/spell/core/ignore.lua` | persistent spell-ignore word list |
| `cmdlog.nvim` | `lua/cmdlog/core/favorites.lua` | favorite commands — hand-rolls Windows-specific `mkdir`/ENOENT defensive fallbacks via `plenary.Path` |
| `reposcope.nvim` | `lua/reposcope/utils/metrics.lua` | API request metrics — raw `vim.fn.writefile`/`readfile` + `vim.json.decode` |
| `gopath.nvim` | `lua/gopath/truncated/cache.lua` | filesystem-scan cache |
| `pickers.nvim` | `lua/pickers/history/init.lua` | picker history |

None of this is exotic — it's "find the project root, build a stable key from
it, load/save JSON, don't crash if the directory or file is missing" — but
each implementation differs slightly in path normalization, error handling,
and fallback behavior when there's no git repo. `cmdlog.nvim`'s file even
carries a comment documenting the Windows-specific defensive code it needed to
write from scratch.

`lib.nvim` already ships **both halves of the fix** as separate, unconnected
pieces:

- [`lib.nvim.cache.disk`](../../lua/lib/nvim/cache/disk.lua) — namespaced JSON
  persistence with TTL, `pcall`-guarded read/write, `stdpath("cache")` default.
- [`lib.nvim.git.repo_root`](../../lua/lib/nvim/git/init.lua) — git work-tree
  root detection.

Nobody combines them, because the combination — "turn a project root + a
relative file path into a stable cache namespace" — doesn't exist yet.

## Proposal

A thin module, `lib.nvim.store.project`, built entirely on the existing two
primitives — no new I/O code, no new JSON handling, no new Windows-path
edge cases to get right a second time:

```lua
local store = require("lib.nvim.store.project")

-- Key resolution: git.repo_root() if inside a work-tree, else stdpath("data")
-- as a per-machine fallback. `key` is normalized (forward slashes, lowercased
-- on case-insensitive filesystems) so it's stable across OSes for the same
-- logical project.
store.save("cascade/anchors", { version = 1, files = { ... } })
local data = store.load("cascade/anchors")  -- nil if missing/unreadable
store.clear("cascade/anchors")
```

Internally: resolve the project root once via `lib.nvim.git.repo_root()`,
derive a filesystem-safe directory from it (e.g. a short hash of the absolute
root path, to avoid deeply nested directory trees mirroring arbitrary project
locations), and delegate the actual read/write/TTL/error-handling entirely to
`lib.nvim.cache.disk` by passing it a computed `opts.dir`. `store.project` adds
exactly one thing `cache.disk` doesn't have: the root-resolution step.

Non-git projects fall back to a plain `stdpath("data")`-rooted path — still
namespaced by an absolute-path hash, still functional, just not portable
across machines (which is inherent to not being in a synced repo, not a
limitation of the module).

## What this is *not*

This is **not** the buffer-anchor system from the cascade concept doc — that
needs a second, independent primitive (edit-stable content-fingerprint
anchoring within a buffer, extmark-backed). That primitive currently has only
one real consumer candidate (`cascade.nvim`) plus one buggy hand-rolled
approximation (`buffer-ctx.nvim`'s line-number-keyed marks — see
[buffer-ctx.nvim/docs/ROADMAP/anchor-stable-marks.md](../../../buffer-ctx.nvim/docs/ROADMAP/anchor-stable-marks.md)).
Two consumers is thin for a `lib.nvim` abstraction; `store.project` is scoped
to the storage half only, which already has 7 duplicated implementations and
stands on its own merit independent of whether buffer-anchoring ever lands
anywhere.

## Suggested shape

```
lua/lib/nvim/store/
  project/
    init.lua      -- save/load/clear, root resolution + key derivation
    @types/
      init.lua
```

Mirrors the existing `lib.nvim.cache` module layout and `@types` convention.

## Migration candidates (once it exists)

Not required, but each of these could drop its own persistence code in favor
of `store.project` opportunistically, without behavior changes:

- `cmdlog.nvim` favorites — removes the hand-rolled Windows ENOENT/mkdir path
- `reposcope.nvim` metrics — removes raw `writefile`/`readfile`/`json.decode`
- `filetree.nvim` session state — already project-keyed, would become a
  thinner wrapper
- `gopath.nvim` truncated-path cache, `pickers.nvim` history

No repo should be touched preemptively — this is a "when convenient" list, not
a punch list.
