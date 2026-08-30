# How the hover is wired to the rest of the ecosystem

[`lib.nvim.hover`](README.md) draws one float and knows almost nothing. Nearly
everything interesting in it — reading a markdown link, resolving a truncated
path, turning a `.png` into pixels, turning page 3 of a PDF into a `.png` — is
somebody else's job, done by a sibling plugin that may or may not be
installed.

This file is the map: **who reaches whom, through which door, and what
degrades when a plugin is absent.** It exists because "the hover is broken" is
almost never a statement about the hover — it is a statement about one of five
plugins, and the first useful question is which one.

## The two doors

There are exactly two ways a plugin and the hover reach each other, and they
are not interchangeable.

**Door 1 — the registry (inbound).** The plugin calls
`lib.nvim.hover.registry.register(name, contribution)` and hands over a
*source* ("what is under the cursor?") or a *preview* ("how do I render a
target of this type?"). lib.nvim never says the plugin's name. Adding a sixth
contributor requires no change here at all.

**Door 2 — a named soft dependency (outbound).** lib.nvim itself calls
`pcall(require, "images.info")`, `pcall(require, "pdfport")`,
`pcall(require, "gopath.resolve")` — by name, from inside its own preview
code, guarded so a missing plugin is a `nil` rather than an error.

Door 1 is the better shape; door 2 is the honest one. A *capability* can be
registered: "here is a function that previews an anchor" says everything the
framework needs to know. A *renderer* cannot, because the hover has to
negotiate with it — measure a picture, subtract the drawing inset, hand back a
geometry, defer a draw by one tick, clear the terminal on close. That is a
conversation with one specific API, not a callback, and pretending otherwise
would put an images.nvim-shaped interface into a library that would then have
exactly one implementor. So the registry carries what generalises, and the
rest is a `pcall` with a fallback underneath it.

Practical consequence, and the reason this file exists: **a plugin can be
listed as a contributor and still not be the cause of a bug you are looking
at.** Door 2 plugins are named inside lib.nvim's own source, so their names
turn up in comments, module docs and stack traces belonging to code they never
ran.

## Who is wired to what

| Plugin | Door | Contributes | Without it |
| --- | --- | --- | --- |
| [markdown.nvim](https://github.com/StefanBartl/markdown.nvim) | registry | link / `<figure>` scanning; `#heading` section previews | only bare paths start a hover; `file.md#frag` shows the file's head, not that section |
| [gopath.nvim](https://github.com/StefanBartl/gopath.nvim) | named | resolving truncated paths and `:line:col` suffixes | ordinary relative and absolute paths still resolve; truncated ones do not |
| [images.nvim](https://github.com/StefanBartl/images.nvim) | named | drawing the picture into the float (OSC 1337) | an image target shows format, dimensions and size as text |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | named | rasterizing a PDF page to PNG | a PDF shows its size and why it could not be rendered |
| [reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim) | — | *planned* — see below | no repository hover |

All of them are optional and **none is required**. With none installed the
hover still gives file heads, directory listings, URL details, image and PDF
metadata, and the "this target does not exist" answer.

## markdown.nvim — the only registry contributor today

Registered from `markdown/hover/init.lua` under the name `"markdown.nvim"`:

| Kind | Key | Implementation |
| --- | --- | --- |
| source | — | `markdown.core.link_scan.from_line` — a link whose span contains the cursor |
| source | — | `markdown.core.html_links.figure_at` — the enclosing `<figure>`, so a `<figcaption>` hovers like the picture it captions |
| preview | `anchor` | `markdown.hover.section.anchor` — an in-page `#heading`, read out of the hovered buffer |
| preview | `markdown` | `markdown.hover.section.file_anchor` — `file.md#heading`; returns `nil` when there is no fragment, and the library's own file preview runs instead |

markdown.nvim also calls `require("lib.nvim.hover").enable()` from
`markdown/bindings/autocmds.lua`. That is a convenience, not the intended
switch: markdown.nvim is normally `ft`-lazy, so in a session that never opens
a `.md` file nothing would ever turn the hover on, and a path in a `.txt` or a
code comment would silently do nothing. Call `enable()` from a spec that is
not lazy-loaded — see [README.md](README.md#turning-it-on).

Registration is keyed by plugin name, so a second `setup()` replaces this
contribution rather than stacking a second link scanner onto every hover.

## gopath.nvim — resolving the paths `<cfile>` cannot

One call, from [`bare_path.lua`](bare_path.lua):

```lua
require("gopath.resolve").resolve_at_cursor()  --> { kind, path, exists, … }
```

It is tried **before** `<cfile>`, because it handles what `<cfile>` cannot: a
truncated path (`...nvim/init.lua`, `…/lua/config/init.lua`), a `:line:col`
suffix, a path findable only through `&path` / `rtp` / a tail search. That is
precisely the "a path in `:messages` should hover too" case, and it is
gopath's whole subject matter.

Two things the hover does with the answer, both worth knowing when a result
surprises you:

- **A `kind == "url"` result is declined.** gopath opens URLs in a browser;
  the hover has its own URL preview, reached through the link path.
- **`exists` must be true.** A gopath result for something not on disk is
  discarded, and the decision about whether the absence is worth reporting is
  taken afterwards, by the hover's own rules — *not* by gopath.

That second point is the one that misleads. A false "✗ no such file" float
looks like a resolver bug and is not: gopath declined, `<cfile>` declined, and
what put the float on screen was the hover deciding for itself that the text
was unambiguously a path. Those rules live in `bare_path.lua`
(`is_unambiguous_path`) and are documented under
[Bare paths](README.md#bare-paths). Read them before opening a gopath issue.

## images.nvim — the picture, and the geometry around it

Two entry points, one of them indirect:

```lua
require("lib.nvim.image_preview").detect()  --> "images.nvim" | "snacks" | "image.nvim" | nil
```

`lib.nvim.image_preview` is the provider-agnostic layer. It prefers
images.nvim when several are installed, because snacks.nvim and image.nvim
both speak only the Kitty graphics protocol while images.nvim draws via
OSC 1337.

`lib.nvim.hover.preview.media` then talks to images.nvim directly, and only to
images.nvim, because it is the only one that can draw into an arbitrary
existing window:

| Call | For |
| --- | --- |
| `images.info.collect` | pixel size, as a fallback where the header parser cannot read the format (WebP, SVG) |
| `images.scale.fit_cells` | letterboxing the image into the float — the same function `images.zen` and `images.redact` size their windows with |
| `images.config` | the `draw_inset` the anchor keeps free on every side |
| `images.anchor` | the draw itself, deferred by one tick |
| `images.browse.draw_in_window` | fallback for an images.nvim without `images.anchor` |
| `images.terminal.clear` | clearing the drawing when the float closes |

Two invariants here are load-bearing, and both have been bugs already: the
editor-relative float, and the inset subtraction. They are written up in
[README.md](README.md#two-things-that-must-not-be-changed-casually), and
images.nvim ships the measurements as `:Image debug`. Read both before
touching placement.

## pdfport.nvim — a page at a time

```lua
require("pdfport").render_page(path, page, opts, callback)
```

Asynchronous: it shells out to `pdftoppm`. The hover caches per file *and* per
page, and the document's page count is never known in advance — paging forward
simply stops at the last page, which is how the count is discovered. If a
render takes longer than `placeholder_grace_ms` the float shows "rendering…";
below that it waits quietly, because a placeholder that only flickers is worse
than none.

Without pdfport a `.pdf` target still hovers — as its size, plus the reason
there is no page.

## reposcope.nvim — planned

[reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim) searches,
previews and clones repositories from GitHub / GitLab / Codeberg, and already
keeps every README it has fetched in a RAM + on-disk cache
(`reposcope.cache.readme_cache`, keyed `owner/repo`). Everything a hover would
need is therefore already local: the natural feature is resting the cursor on
`owner/repo` — in a repo list, a plugin spec, a lockfile, a note — and getting
that README's head in the float.

**Not wired today.** No reposcope module calls into `lib.nvim.hover`, and the
hover names no reposcope module. When it is built it belongs on door 1, and
needs no change to lib.nvim:

```lua
require("lib.nvim.hover.registry").register("reposcope.nvim", {
  sources = {
    -- `owner/repo` under the cursor, once it is a repo reposcope knows.
    function(bufnr, row, col) return repo_slug_at(bufnr, row, col) end,
  },
  previews = {
    -- Answer from the README cache; return nil to decline, and whatever the
    -- built-in preview for that type is runs instead.
    markdown = function(target, opts) return readme_head(target, opts) end,
  },
})
```

Two things to settle first, and they are why this is not done yet:

- **A slug is not a path.** `owner/repo` is two components with no extension
  and no root, which the bare-path rules deliberately treat as prose (`and/or`
  is spelled identically). A reposcope source therefore has to run *before*
  the bare-path source — registration order already guarantees that — and must
  answer only for slugs it can confirm against its own cache, never for
  arbitrary text.
- **There is no `repository` target type.** Either reposcope resolves the slug
  to the cached README's path on disk and rides the existing `markdown`
  preview, or `classify` grows a type. The first needs no library change at
  all, and is the one to try.

## Reading a symptom back to its owner

| Symptom | Owner |
| --- | --- |
| a red ✗ on text that was never a path | `bare_path.is_unambiguous_path` — **lib.nvim**, not gopath |
| a truncated path (`...nvim/init.lua`) does not resolve | gopath.nvim missing, or declining |
| `file.md#heading` shows the file's head instead of the section | markdown.nvim missing |
| a link does not hover, but the bare path in it does | markdown.nvim's source is not registered — usually `setup()` never ran |
| an image shows as text | no provider installed, or one that is not images.nvim on a terminal without Kitty graphics |
| the picture lands beside its own frame | placement — see the two invariants in [README.md](README.md#two-things-that-must-not-be-changed-casually) |
| a PDF shows its size but no page | pdfport.nvim missing, or `pdftoppm` not on `PATH` |
| nothing hovers anywhere | `enable()` never ran from a non-lazy spec, or `vim.g.lib_nvim_hover_disable` is set |

## Direction of dependency

lib.nvim depends on none of them. Each plugin depends on lib.nvim, and every
crossing is `pcall`-guarded in both directions: a missing plugin degrades one
row of the table above, and a *broken* one is contained — a registry source
that throws is skipped, and the next source still runs.

Installing lib.nvim alone gives you a working hover. Installing one of the
five upgrades exactly one row from a description into the thing itself.
