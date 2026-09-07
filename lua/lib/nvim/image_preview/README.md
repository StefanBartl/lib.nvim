# `lib.nvim.image_preview`

In-Neovim image preview via [images.nvim](https://github.com/StefanBartl/images.nvim),
[snacks.nvim](https://github.com/folke/snacks.nvim) (`Snacks.image`), or
[image.nvim](https://github.com/3rd/image.nvim) — all three are soft
dependencies, auto-detected. With none installed, `preview()` fails cleanly
so a caller can fall back to shelling out to the system image viewer instead.

```lua
local image_preview = require("lib.nvim.image_preview")

if image_preview.available() then
  local ok, err = image_preview.preview("/path/to/pic.png")
  if not ok then
    vim.notify(err, vim.log.levels.WARN)
  end
end
```

## Why images.nvim is preferred when several are installed

`snacks.nvim` and `image.nvim` both speak only the Kitty graphics protocol,
which native Windows Neovim in WezTerm never draws when it comes from Neovim
itself (see images.nvim's README, "Why not snacks.image or image.nvim") — so
on that setup both are silently non-functional. `images.nvim` draws via OSC
1337 instead, which does work there. `detect()` therefore checks
`images.nvim` first, falling back to `snacks` then `image.nvim` on setups
where those work fine (Kitty-capable terminals).

## API

```lua
image_preview.detect()      --> "images.nvim" | "snacks" | "image.nvim" | nil
image_preview.available()   --> boolean, i.e. detect() ~= nil
image_preview.preview(path) --> ok: boolean, err: string|nil
```

`preview(path)` opens a centered floating window (80% of the editor, clamped
to stay usable on very small/large editors) and renders `path` into it using
whichever provider `detect()` found. `q`/`<Esc>` (buffer-local, normal mode)
and any other way of closing the window (`:q`, `<C-w>c`, ...) both tear the
placement down cleanly — each provider needs different cleanup:

- **images.nvim** — no buffer hook; draws directly into the float's window
  via `images.browse.draw_in_window` (the same call images.nvim's own
  `:Image pickers` use), cleared via `images.terminal.clear()` on close.
- **snacks.nvim** — `Snacks.image` hooks buffer loading for image files, so
  the float only has to `:edit` the path; nothing to place or clean up by
  hand.
- **image.nvim** — no buffer hook either; an image object is built from the
  file with `image.from_file` and rendered into the float's window
  explicitly, cleared via `img:clear()` on close.

Every failure path (missing provider, a provider erroring on `path`) closes
whatever window/buffer it already created and returns `false, err` rather
than leaving a half-open float behind.
