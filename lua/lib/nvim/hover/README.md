# `lib.nvim.hover`

Rest the cursor on something that points at a file — a markdown link, or a
path written as plain text — and a small float shows what it points at.

```
See ./docs/architecture.md#modules for details.
    └──────── hover here ────────┘

┌ architecture.md ──────────────────┐
│ ## Modules                        │
│                                   │
│ Every module owns one directory   │
│ with an `init.lua` …              │
└───────────────────────────────────┘
```

## Why this lives in lib.nvim

It began inside `markdown.nvim`, where the only thing that could start a
hover was markdown link syntax. Almost none of it turned out to be *about*
markdown: classification, the float, the file/directory/URL previews, the
debounce, the cache and the bare-path detection are all just "a path is a
path". What genuinely needs markdown — resolving a `#heading`, and finding a
link or `<figure>` in a line — is roughly a tenth of the code.

Putting it in `images.nvim` instead would have been the same mistake wearing
different clothes: that plugin draws pictures, and would then have owned
directory listings, file heads and URL fetching. So it moved here, where
neither the markdown nor the image half is privileged, and both arrive
through a registry.

**A capability registers itself; a renderer is asked for by name.**
markdown.nvim hands over a function and is never named here. images.nvim,
pdfport.nvim and gopath.nvim are `pcall(require, …)`-ed by name from inside
the previews, because the hover has to negotiate geometry and timing with
them rather than just call them — which also means their names appear in code
they did not run. Both mechanisms, and which one owns which symptom, are laid
out in [INTEGRATIONS.md](INTEGRATIONS.md).

## Who contributes what

| Plugin | Contributes | Without it |
| --- | --- | --- |
| **markdown.nvim** | Finding a link / `<figure>` in a line; `#heading` section previews | Only bare paths start a hover; a `file.md#frag` shows the file's first lines instead of that section |
| **images.nvim** | Draws the picture into the float (OSC 1337) | An image target shows format, dimensions and size as text |
| **pdfport.nvim** | Rasterizes page 1 of a PDF; converts an office document to a PDF so it can be shown at all (opt-in) | A PDF shows its size and why it could not be rendered; a `.docx` shows what it is |
| **gopath.nvim** | Resolves truncated paths (`...nvim/init.lua:42`) and `:line:col` suffixes | Ordinary relative and absolute paths still resolve; truncated ones do not |

Every one of them is optional, and **none of them is required for the hover
to work**. With none installed you still get: file heads, directory listings,
image and PDF metadata, a badge for anything that has no text in it, the
"this target does not exist" answer, and — once `:Lib hover web on` — URL
details. Install one and that row upgrades from a description to the thing
itself.

The long version — every entry point, what a planned reposcope.nvim hover
would look like, and a table reading each symptom back to the plugin that
owns it — is [INTEGRATIONS.md](INTEGRATIONS.md).

If *nothing* could produce a hover — no source registered and
`bare_paths = false` — `attach()` installs no autocmd at all rather than one
that wakes on every `CursorHold` to find it has nothing to say.

## Turning it on

Nothing here installs autocmds by itself — a library that started previewing
things the moment it was on the runtimepath would be overstepping. One call
switches it on globally:

```lua
require("lib.nvim.hover").enable()
```

It installs the `FileType` trigger, attaches to buffers that are already
open, and is idempotent (call it from two plugins and you still get one
autocmd).

**Put it somewhere that is not lazy-loaded.** markdown.nvim calls it too, but
that plugin is normally `ft`-lazy on markdown — so in a session that never
opens a `.md` file, nothing would ever turn the hover on, and paths in a
`.txt` or a code comment would silently do nothing. The natural home is your
`lib.nvim` spec:

```lua
{
  "StefanBartl/lib.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("lib.nvim.hover").enable()
  end,
}
```

`enable(opts)` also accepts the config table below, so you can turn it on and
configure it in one call.

`lazy = false` here is not a hover requirement — it is what
[installation.md](../../../../docs/installation.md) already recommends for
lib.nvim generally, since a config that uses `lib.*` in its own modules
bootstraps the library before `lazy.setup()` anyway and the spec then only
keeps it updatable. If your lib.nvim is lazy-loaded on first `require`,
`enable()` needs a home that actually runs at startup instead.

## Waving one hover away

Sometimes the float is over the thing you are trying to read, and you have to
stay on the path. `q` or `<Esc>` takes it away and *keeps* it away for as
long as the cursor stays on that target:

| Key | Does |
| --- | --- |
| `q` or `<Esc>` | dismiss this hover; re-arms by itself at the next target |

**Closing alone would not do**, which is why this is a dismissal and not a
close. `CursorHold` fires again after any keystroke followed by `updatetime`
of quiet — cursor movement or not — so a key bound to `hide()` makes the
float vanish and then brings it straight back, while you are still standing
where you wanted it gone.

The dismissal ends by itself: the next target the cursor resolves, another
path or none at all, clears it. Nothing has to be remembered and undone, and
coming back to the same path hovers normally again. That is the whole
difference between this and the session switch below — this one is "not now",
that one is "not for a while".

Like the scroll keys they are bound globally only while a hover is on screen,
and handed back the moment it closes; a key that was already mapped is
*restored*, not deleted. Unlike the scroll keys they are bound for **every**
hover, because anything can be waved away — including a picture, which has
nothing to scroll. The price is that `q` records no macro for as long as one
float is up, and none after it.

Other keys, or none at all:

```lua
require("lib.nvim.hover").setup({
  dismiss_keys = { "<C-c>" },   -- a string or a list; replaces the default
  -- dismiss_keys = {},         -- bind nothing, and call hover.dismiss() yourself
})
```

`hover.dismiss()` is public and returns `false` when no hover was open, so it
is safe to bind unconditionally.

## Turning it off

For the rest of the session, from wherever you are:

| Command | Does |
| --- | --- |
| `:Lib hover toggle` | off if it is on, on if it is off |
| `:Lib hover off` / `:Lib hover on` | say which |
| `:Lib hover web on` / `off` / `toggle` | whether links hover at all — see [Links](#links-to-the-web) |
| `:Lib hover web fetch on` / `off` / `toggle` | whether a hovered link is fetched for its status code and title |
| `:Lib hover office on` / `off` / `toggle` | whether a `.docx` is rendered through a PDF or only described |

A command and not a key, because lib.nvim claims no keymaps on its
dependents' behalf — `lib.nvim_usrcmds` says exactly that — and a switch you
throw a few times a week does not need to be one keystroke away. The
dismissal above is the one that does.

Each toggle is announced, because "off" is otherwise invisible: nothing on
screen tells a switched-off hover apart from a line that simply has no target
on it, and a switch whose state you cannot see gets reported as a broken
feature a week later. `hover.is_enabled()` answers the same question for a
statusline, and `hover.toggle(true|false|nil)` is the API under the command.

`:Lib hover on` also re-runs `enable()`, so it works from a session where
nothing had switched the hover on at all — and so that buffers you opened
while it was off get their autocmds when you turn it back on, instead of
staying quietly dead.

The state lives in `vim.g.lib_nvim_hover_disable`, which is also where you
say it from a plugin spec, before anything loads — one setting rather than
two that can disagree:

```lua
{
  "StefanBartl/lib.nvim",
  init = function()
    vim.g.lib_nvim_hover_disable = true
  end,
}
```

That outranks anything a plugin configures — a host enabling its hover cannot
override you switching the feature off.

Per-option control goes through the host plugin's own config (markdown.nvim
exposes it as `hover = { … }`), or directly:

```lua
require("lib.nvim.hover").setup({
  bare_paths = false,   -- links only; no hovering of plain-text paths
  delay_ms = 400,
  max_lines = 30,
  url = { fetch = true },
})
```

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master switch. |
| `trigger` | `{ "CursorHold" }` | `"CursorHold"` follows `'updatetime'`. `"mouse"` also needs `:set mousemoveevent`, which is never set for you. |
| `delay_ms` | `250` | Debounce before the float opens. |
| `placeholder_grace_ms` | `250` | How long an async preview may take before a "rendering…" placeholder is allowed to interrupt. |
| `max_lines` | `20` | Preview line cap, and the float's max height. |
| `max_width` | `80` | Float width cap, in columns. |
| `border` | `"rounded"` | `nvim_open_win` border. |
| `inline_images` | `true` | Draw pictures / PDF pages into the float when a provider can. |
| `bare_paths` | `true` | Also hover paths written without link syntax. |
| `scroll_keys.down` | `{ "<M-PageDown>", "<C-Down>" }` | Keys that scroll a scrollable preview forward. |
| `scroll_keys.up` | `{ "<M-PageUp>", "<C-Up>" }` | …and back. |
| `dismiss_keys` | `{ "q", "<Esc>" }` | Keys that dismiss the hover on screen until the cursor reaches another target. |
| `url.hover` | `false` | Whether a link hovers at all. Off deliberately — see [Links](#links-to-the-web). |
| `url.fetch` | `false` | Whether the page is fetched for its status code, title and description. Implies `url.hover`. Off deliberately: a hover that silently fetches discloses every link you brush past to its host. |
| `url.timeout_ms` | `2000` | |
| `office.convert` | `false` | Whether a `.docx`/`.xlsx`/`.pptx`/… is converted to a PDF and shown as a page, instead of described. Off deliberately: it costs a LibreOffice start per document. |
| `office.timeout_ms` | `60000` | LibreOffice's first start is slow, and a timeout that fires on it looks like a broken feature. |

## Scrolling a preview

A file's head and a PDF's first page are often not the part you want.
While a scrollable hover is open:

| Key | Does |
| --- | --- |
| `<M-PageDown>` or `<C-Down>` | next screenful of lines, or next PDF page |
| `<M-PageUp>` or `<C-Up>` | back |

Both pairs are bound, because a key that is not on the keyboard cannot be
pressed: laptop and 60% layouts often reach PageUp/PageDown only through an
Fn chord, and nothing at runtime can tell whether *this* keyboard has them.
The arrows are on every keyboard there is. Ctrl rather than Alt on them,
because `<M-Up>`/`<M-Down>` are a widespread "move this line" binding.

The float stays a **preview**: not focusable, not editable, nothing to
select or yank. The keys are bound globally while such a hover is on screen
and removed the moment it closes — so they keep whatever meaning they have
elsewhere the rest of the time. A key that was already mapped is *restored*,
not deleted, when the hover goes away.

They are bound **only when there is something to scroll**. An image, or a
file that already fits in the float, leaves them alone entirely.

Different keys, without touching the API:

```lua
require("lib.nvim.hover").setup({
  scroll_keys = { down = "<C-n>", up = "<C-p>" },   -- a string or a list
})
```

A configured list *replaces* the default rather than extending it, so
`{ down = { "<C-n>" } }` binds `<C-n>` and nothing else. An empty list
(`{ down = {}, up = {} }`) binds nothing at all — the way to keep the hover
and do the scrolling from your own mappings.

Scrolling does not re-resolve the cursor: the hover keeps showing what it
was showing, even if the cursor has since moved off the link. The title
shows where you are — `notes.md  ↓20` for text, `p3` for a PDF (page 1 stays untitled, like
any image preview).

PDF paging renders each page on demand through `pdfport.render_page`, so
there is a short delay per page, and pages are cached per file *and* page.
The document's page count is not known in advance; paging simply stops at
the last page and stays there.

Or call the API from your own mapping, which works whether or not a hover
happens to be open:

```lua
vim.keymap.set("n", "<C-d>", function() require("lib.nvim.hover").scroll(1) end)
vim.keymap.set("n", "<C-u>", function() require("lib.nvim.hover").scroll(-1) end)
```

`scroll(delta)` returns `false` when there is no open hover or nothing to
scroll, so it is safe to bind unconditionally.

## Bare paths

A path in prose, a code comment, or a `:messages` dump is a target too:

```
./assets/diagram.png                → the picture
../docs/BINDINGS.md                 → its first lines, markdown-highlighted
...AppData/Local/nvim/init.lua:42   → the file, found despite the truncation
```

Two rules keep this from firing constantly:

- **It must look like a path** — a separator, an extension, or a `...`
  truncation, *and* at least one alphanumeric character somewhere. `helper` is
  a word; `helper.lua` is a path; `/` and `--%` are punctuation out of a
  table.
- **A missing path is reported only when it cannot have been anything else.**
  That one gets a red ✗; everything else stays silent.

Silent is the default because prose is full of things that resolve to
nothing and were never a path: `vim.api` and `string.format` (a bare
`name.ext` is how every Lua module is spelled), but equally `and/or`, a table
header `Actual/Insgesamt`, a ratio `60% / 27%`, a word given a trailing slash
(`sortiert/`). A separator on its own does not settle it. Something prose
does not write has to be there too:

| Evidence | Example |
| --- | --- |
| a truncation | `...nvim/init.lua`, `…/lua/config` |
| an explicit relative prefix | `./docs/a`, `../docs/a`, `~/notes` |
| a drive or UNC prefix | `C:\Users\x`, `\\server\share` |
| a component carrying an extension | `docs/gone.md` |
| three or more components | `lua/lib/nvim/hover` |
| two components under an absolute root | `/etc/hosts` |

None of this touches a target that **exists** — `docs/` and `and/or` both
hover normally the moment something of that name is on disk. The rules only
decide whether *absence* is worth asserting.

## Links to the web

Off by default. Not because a link preview is a bad idea — it is one of the
better ones here — but because **documentation is made of links**. Turn it on
permanently and reading a README becomes a slideshow: every second cursor
rest opens a float, and the float lands over the paragraph being read.

So it is a switch you throw when links are what you are looking at:

| Command | What you get |
| --- | --- |
| `:Lib hover web on` | the URL taken apart: host, path, decoded query. Nothing leaves the machine. |
| `:Lib hover web fetch on` | that, plus what the server answers. Implies `web on`. |
| `:Lib hover web off` | back to silence on links |

With fetching on, the **status line comes first**, because "is this link still
alive" is the question a link hover is actually asked:

```
┌ page ─────────────────────────────────────┐
│ HTTP 500 Internal Server Error            │
│ Example Domain                            │
│ text/html · 1.2 KB                        │
│                                           │
│ example.com                               │
│ /broken                                   │
└───────────────────────────────────────────┘
```

A 4xx or 5xx is marked through `LibHoverError` (linked to `DiagnosticError`),
so a dead link is recognizable before the number is read. "No answer at all" —
DNS failure, refused connection, timeout — is a different float from "the
server said 500", because they are different problems and you are about to act
on one of them.

Fetching is **off on top of the hover switch** for a reason the volume
argument does not cover: it is a disclosure. Every link the cursor rests on
becomes a request from this machine to that host, and a document with fifty
links becomes a request storm while scrolling. `web on` alone never touches
the network.

Results are cached for the session. A server that has since recovered keeps
showing its old status until the cache is dropped — `:Lib hover web off` and
`on` again does that, as does any of these switches.

**Links are found in every filetype**, not only in markdown. markdown.nvim's
link scanner covers `[text](url)`, autolinks and bare URLs inside a markdown
buffer; `bare_url.lua` covers a URL in a Lua comment, a `.txt`, a commit
message or a `:messages` dump. Both are gated by the same switch, so there is
one setting and not two that can disagree.

What counts as a URL is decided by shape, on the line — deliberately not
through `<cfile>`, which stops at whatever `'isfname'` excludes and used to
cut off `?query=` and `#fragment`:

| Text | Found |
| --- | --- |
| `see https://neovim.io/doc?a=b#c now` | the whole URL, query and fragment included |
| `(https://example.com), and…` | without the wrapping paren or the comma |
| `https://en.wikipedia.org/wiki/Vim_(text_editor)` | *with* its own bracket — it opened that one itself |
| `http:\\example.com` | yes, repaired to `http://` — a Windows keyboard produces this constantly |
| `www.example.com` | yes, read as `https://` |
| `local p = "C:\\Users\\me"` | no. A one-letter scheme is a drive letter, so schemes must be at least two characters |

`show({ force = true })` ignores the switch: an explicit request for the link
under the cursor is not the volume problem the switch exists to solve.

## Files with no text in them

Hovering a `.docx` used to open a float holding the first twenty "lines" of a
ZIP container — mojibake, with the document's name in the border, which reads
as a preview rather than as garbage. Every binary format did it, because
reading lines is what a file preview does and a binary file contains newline
bytes.

Now a file whose bytes are not text gets a badge saying so:

```
┌ archive.zip ──────────┐
│ ◆ ZIP archive         │
│ ZIP · 4.1 MB          │
└───────────────────────┘
```

**The test is the bytes, not a list of extensions.** A NUL in the first 4 KB,
or too many other control characters, and there is nothing to read — which
covers the formats nobody thought to list, including whatever is invented next
week. `lib.nvim.hover.formats` is consulted only for a better *word* than
"binary file" once the decision is already made, and it knows the office
formats, archives, executables, media, fonts and databases.

The badge is `LibHoverInfo` (→ `DiagnosticHint`), not the red of a broken
link. Nothing is wrong with the file; it simply has no text in it.

### Office documents can do better than a badge

`.docx`, `.xlsx`, `.pptx`, `.odt` and the legacy `.doc`/`.xls`/`.ppt` are the
one group with a second answer available: LibreOffice converts them to a PDF,
and a PDF is something this hover already shows as a picture.

```
:Lib hover office on
```

From then on an office document hovers as its **first page, rendered** — and
`<M-PageDown>` / `<C-Down>` page through it exactly like a PDF, because by
that point it *is* one.

Opt-in, because the first conversion of each document starts LibreOffice:
seconds, not milliseconds. That is also why the float says `converting to
PDF…` while it runs (after `placeholder_grace_ms`, so a fast one shows nothing
but the finished page), why a second hover on the same document is instant —
the converted PDF is kept, keyed by file *and* mtime — and why only one
conversion per document ever runs at a time, however often `CursorHold` fires
while LibreOffice starts.

Needs [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) and
`soffice` on `PATH`. Without either, the badge says which one is missing
rather than silently doing nothing:

```
┌ report.docx ───────────────────────────────┐
│ ◆ Word document                            │
│ DOCX · 24.1 KB                             │
│ (LibreOffice not on PATH — no page preview)│
└────────────────────────────────────────────┘
```

Converted PDFs live in `stdpath("cache")/lib.nvim/hover-office` and are
deleted when Neovim exits — the same bargain the rasterized PDF pages make.

## Contributing from a plugin

```lua
require("lib.nvim.hover.registry").register("your.nvim", {
  -- "what is under the cursor?" Return a raw target string, or nil.
  -- Tried in registration order, before the built-in bare-path source.
  sources = {
    function(bufnr, row, col)
      return find_target(bufnr, row, col)  -- , { kind = "yours" }
    end,
  },
  -- "how do I preview a target of this type?" Keyed by the type `classify`
  -- produced; returning nil declines and the built-in preview runs.
  previews = {
    anchor = function(target, opts, bufnr) return section_of(target, bufnr) end,
  },
})
```

Re-registering under the same name **replaces** that plugin's contribution,
so a `setup()` that runs twice does not leave two copies of your source firing
on every hover. A source that throws is skipped and the next one still runs.

Target types a preview can claim: `image`, `pdf`, `office`, `markdown`,
`file`, `directory`, `url`, `anchor`, `missing`.

## Two things that must not be changed casually

Both were bugs, both took a long time to find, and both are easy to
reintroduce with a change that looks obviously correct.

### The float is positioned `relative = "editor"`, not `"cursor"`

Even though "one line below the cursor" is exactly what is wanted.

`nvim_win_get_position` reports a **wrong column** for a cursor-relative
float when the editor window does not start at column 0 — it adds the
window's origin to a cursor position that already contains it. Measured with
a 26-column file tree: a float whose frame is drawn at column ~59 reports
**83**. Neovim draws it correctly; only the self-report is wrong.

That is fatal here, because this float's geometry *is* the drawing box handed
to the terminal for an image. Everything downstream computes a correct offset
from a wrong origin, and the picture lands beside its own frame by the
sidebar's width.

So `float.open` takes the cursor's true grid position from `screenpos()` and
opens an editor-relative float, which reports back exactly what it was given.
**Reverting that to `relative = "cursor"` brings the bug straight back**, and
it only shows with a sidebar open.

### The image is fitted to the drawing box, not to the frame

`canvas_cells` subtracts `draw_inset` before asking `fit_cells`, then adds it
back for the frame. That looks like an off-by-two and is not.

`images.anchor` keeps `draw_inset` cells free on every side, so a float sized
to fit the image exactly is drawn into a box two cells smaller per axis. Two
cells off 20 rows is a bigger relative change than two off 77 columns, so the
ratio moves — and `preserveAspectRatio=1` letterboxes the difference and
centres it. Measured: ~2.7 cells of empty space on the left for a 1200x675
image in a 77x20 frame, which reads as "the image is shifted right".

### If a placement problem appears again

`images.nvim` ships the measurements as `:Image debug` (`report`, `columns`,
`float`); the failure modes are written up in that plugin. Two traps, both of
which cost days:

- **A consistency check passing proves nothing about the origin.** Sent
  coordinates matching the reported float position held throughout both bugs
  above. Compare the report against reality — `:Image debug float` draws a
  marker at the reported corner for exactly that.
- **A generated test card cannot reveal an aspect-ratio problem**, because
  `images.testcard` builds it to whatever box it is handed. Reproduce with a
  real image; a probe that also passes `inset = 0` bypasses the second bug by
  construction.

## Modules

| Module | Job |
| --- | --- |
| `lib.nvim.hover` | Orchestration: debounce, LRU cache, async generation counter, `attach`/`show`/`hide`/`scroll`/`dismiss`/`toggle` |
| `lib.nvim.hover.registry` | Plugin sources and previews |
| `lib.nvim.hover.classify` | Target string → typed target. Pure, no I/O beyond one `fs_stat` |
| `lib.nvim.hover.formats` | What an extension names, and whether it is convertible. Read by `classify` and by the badge |
| `lib.nvim.hover.bare_path` | Paths with no link syntax; asks gopath.nvim when present |
| `lib.nvim.hover.bare_url` | URLs with no link syntax, in any filetype |
| `lib.nvim.hover.float` | The window |
| `lib.nvim.hover.preview.text` | File heads, directory listings, the missing marker |
| `lib.nvim.hover.preview.binary` | Is this text at all, and what to say when it is not |
| `lib.nvim.hover.preview.office` | Office documents: the badge, or the converted PDF's page |
| `lib.nvim.hover.preview.url` | URL details, optional fetch |
| `lib.nvim.hover.preview.media` | Images and PDF pages, via whatever provider is installed |
