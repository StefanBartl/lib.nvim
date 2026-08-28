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

**This module knows none of those plugins by name.** They register into it.

## Who contributes what

| Plugin | Contributes | Without it |
| --- | --- | --- |
| **markdown.nvim** | Finding a link / `<figure>` in a line; `#heading` section previews | Only bare paths start a hover; a `file.md#frag` shows the file's first lines instead of that section |
| **images.nvim** | Draws the picture into the float (OSC 1337) | An image target shows format, dimensions and size as text |
| **pdfport.nvim** | Rasterizes page 1 of a PDF | A PDF shows its size and why it could not be rendered |
| **gopath.nvim** | Resolves truncated paths (`...nvim/init.lua:42`) and `:line:col` suffixes | Ordinary relative and absolute paths still resolve; truncated ones do not |

Every one of them is optional, and **none of them is required for the hover
to work**. With none installed you still get: file heads, directory listings,
URL details, image and PDF metadata, and the "this target does not exist"
answer. Install one and that row upgrades from a description to the thing
itself.

If *nothing* could produce a hover — no source registered and
`bare_paths = false` — `attach()` installs no autocmd at all rather than one
that wakes on every `CursorHold` to find it has nothing to say.

## Turning it off

lib.nvim has no `setup()` of its own, so the global switch is a variable,
set from your plugin spec before anything loads:

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
| `url.fetch` | `false` | Off deliberately: a hover that silently fetches discloses every link you brush past to its host. |
| `url.timeout_ms` | `2000` | |

## Bare paths

A path in prose, a code comment, or a `:messages` dump is a target too:

```
./assets/diagram.png                → the picture
../ROADMAP/ROADMAP.md               → its first lines, markdown-highlighted
...AppData/Local/nvim/init.lua:42   → the file, found despite the truncation
```

Two rules keep this from firing constantly:

- **It must look like a path** — a separator, an extension, or a `...`
  truncation. `helper` is a word; `helper.lua` is a path.
- **A missing path is reported only when it cannot have been anything else** —
  it carries a separator (`docs/gone.md`) or a truncation. Those get a red ✗.
  A bare `name.ext` that resolves to nothing stays silent, because that is
  exactly how `vim.api`, `string.format` and every other identifier is
  spelled, and a ✗ on half the tokens in a Lua file is noise.

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

Target types a preview can claim: `image`, `pdf`, `markdown`, `file`,
`directory`, `url`, `anchor`, `missing`.

## Modules

| Module | Job |
| --- | --- |
| `lib.nvim.hover` | Orchestration: debounce, LRU cache, async generation counter, `attach`/`show`/`hide` |
| `lib.nvim.hover.registry` | Plugin sources and previews |
| `lib.nvim.hover.classify` | Target string → typed target. Pure, no I/O beyond one `fs_stat` |
| `lib.nvim.hover.bare_path` | Paths with no link syntax; asks gopath.nvim when present |
| `lib.nvim.hover.float` | The window |
| `lib.nvim.hover.preview.text` | File heads, directory listings, the missing marker |
| `lib.nvim.hover.preview.url` | URL details, optional fetch |
| `lib.nvim.hover.preview.media` | Images and PDF pages, via whatever provider is installed |
