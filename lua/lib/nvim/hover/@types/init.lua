---@meta
---@module 'lib.nvim.hover.@types'
---@brief Type contracts for the hover framework.
---@description
--- Moved here with the framework itself (previously `Mkdn.Hover.*` inside
--- markdown.nvim). The `Lib.Hover.Source` shape is deliberately loose: a
--- registered source returns a raw target string and the framework builds the
--- record, so a plugin never has to construct one field-by-field.

---@alias Lib.HoverTrigger
---| '"CursorHold"' # Follows 'updatetime'.
---| '"mouse"'      # Needs `:set mousemoveevent`; never set on the user's behalf.

---@class Lib.HoverConfig
---@field enabled? boolean # Master switch. Default true.
---@field trigger? Lib.HoverTrigger[] # What opens a hover. Default `{ "CursorHold" }`.
---@field delay_ms? integer # Debounce before the float opens. Default 250.
---@field placeholder_grace_ms? integer # How long an async preview may take before a "rendering…" placeholder is shown. Default 250.
---@field max_lines? integer # Preview line cap (also the float's max height). Default 20.
---@field max_width? integer # Float width cap, in display columns. Default 80.
---@field border? string|string[] # `nvim_open_win` border. Default "rounded".
---@field inline_images? boolean # Draw images / rasterized PDF pages into the float when a provider can. Default true.
---@field bare_paths? boolean # Also hover a path written without link syntax. Default true. See `lib.nvim.hover.bare_path`.
---@field filetypes? string|string[] # Which buffers a host attaches the hover to. Interpreted by the host, not here.
---@field scroll_keys? Lib.Hover.ScrollKeys # Which keys scroll a scrollable preview.
---@field dismiss_keys? string|string[] # Which keys wave the hover on screen away. Default `{ "q", "<Esc>" }`; a configured list replaces the default, and an empty one binds nothing.
---@field url? Lib.HoverUrlConfig

--- Keys bound globally while a scrollable hover is on screen, and unbound
--- (restoring whatever they shadowed) the moment it closes. Each direction
--- takes a single key or a list; a configured list replaces the default
--- rather than extending it, and an empty list binds nothing.
---@class Lib.Hover.ScrollKeys
---@field down? string|string[] # Default `{ "<M-PageDown>", "<C-Down>" }` — the second pair for keyboards with no PageUp/PageDown.
---@field up? string|string[] # Default `{ "<M-PageUp>", "<C-Up>" }`.

--- One key `lib.nvim.hover` currently holds, with the mapping it displaced.
--- Covers both the scroll keys and the dismiss keys: they are borrowed and
--- returned by the same mechanism, and differ only in when they are bound.
---@class Lib.Hover.BoundKey
---@field lhs string
---@field saved? table # `maparg(..., true)` dict of the mapping that was there, restored on unbind.

---@class Lib.HoverUrlConfig
---@field fetch? boolean # Fetch the page for its title/description. Default false: a hover that silently fetches discloses every link brushed past.
---@field timeout_ms? integer # Default 2000.

--- What a target turned out to be (`lib.nvim.hover.classify`).
---@class Lib.Hover.Target
---@field type "image"|"pdf"|"markdown"|"file"|"directory"|"url"|"anchor"|"missing"
---@field raw string # The target exactly as written.
---@field path? string # Absolute, normalized path for local targets.
---@field anchor? string # Fragment after `#`, without the `#`.
---@field url? string # Normalized URL for `type == "url"`.
---@field ext? string # Lowercased extension, when there is one.
---@field size? integer # Byte size, for local files.
---@field reason? string # Why it is `missing`.

--- What a source reported under the cursor.
--- Pixel dimensions of an image. Structurally identical to images.nvim's
--- `Images.Scale.Dims`, declared here because images.nvim is a soft
--- dependency (`pcall(require, ...)`) and its types are not on this
--- workspace's library path.
---@class Lib.Hover.Preview.Dims
---@field width integer
---@field height integer

---@class Lib.Hover.Source
---@field target string # Raw target string, handed to `classify`.
---@field lnum integer # 1-based line it was found on.
---@field col integer # 0-based start column.
---@field col_end integer # 0-based end column.
---@field kind? string # Free-form label from the source ("mdlink", "bare_path", …).

--- Options threaded from the config into the previewers.
---@class Lib.Hover.PreviewOpts
---@field max_lines integer
---@field max_width? integer # Needed by the image previewer, which sizes the float itself rather than letting it be measured from text.
---@field inline_images? boolean
---@field url_fetch? boolean
---@field url_timeout_ms? integer
---@field offset? integer # Text previews: lines to skip. Set by `lib.nvim.hover.scroll`.
---@field page? integer # PDF previews: 1-based page to render. Set by `lib.nvim.hover.scroll`.

---@class Lib.Hover.Content
---@field lines string[]
---@field filetype? string # Set only where a filetype is known, never guessed.
---@field title? string # Rendered in the float border.
---@field image_path? string # Draw this image into the float, if a provider can.
---@field canvas? Lib.Hover.Canvas # Size the float to this instead of to `lines`, and show no text or title: the float is a frame for the picture, not a caption for it.
---@field highlight? string # Highlight group applied to the first line (the `missing` preview's ✗ marker).
---@field scroll? Lib.Hover.Scroll # Present when the preview has more to show; drives the `scroll_keys`.
---@field pending? boolean # Provisional; an async result replaces it (and it is not cached).

--- Where a scrollable preview currently is, and whether more follows.
--- Absent means "not scrollable" — an image, or a file that fits — and the
--- scroll keys are then not bound at all.
---@class Lib.Hover.Scroll
---@field offset? integer # Lines skipped, for text previews.
---@field page? integer # 1-based page, for PDF previews.
---@field step integer # How much one scroll step advances.
---@field more boolean # Whether anything follows the current position.
---@field past_end? boolean # The requested position does not exist (paged past the last PDF page).

--- Exact float size in cells, for a preview that is a picture rather than text.
---@class Lib.Hover.Canvas
---@field cols integer
---@field rows integer

--- Geometry/appearance for `lib.nvim.hover.float.open`.
---@class Lib.Hover.FloatOpts
---@field title? string
---@field filetype? string
---@field max_width? integer
---@field max_height? integer
---@field canvas? Lib.Hover.Canvas # Blank float of this exact size; `lines`, `title` and `filetype` are ignored.
---@field border? string|string[]
---@field focusable? boolean
---@field highlight? string # Highlight group for the first line; `LibHoverMissing` (→ `DiagnosticError`) is defined on demand.
---@field on_close? fun()

return {}
