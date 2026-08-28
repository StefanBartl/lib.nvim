---@module 'lib.nvim.hover'
---@brief Hover preview for whatever path the cursor is resting on.
---@description
--- The cursor rests on something that points at a file ⇒ a small float shows
--- what it points at, whatever that is: an image, a PDF page, a markdown
--- file's section, a plain file's head, a directory listing, an in-page
--- anchor, a URL — or, when the target does not exist, *that*, which is often
--- the most useful answer of all.
---
--- **Why this is a library and not a plugin feature.** It began inside
--- `markdown.nvim`, where the only thing that could start a hover was
--- markdown link syntax. Almost none of it turned out to be about markdown:
--- classification, the float, file/directory/URL previews, the debounce, the
--- cache and the bare-path detection are all just "a path is a path". What
--- genuinely needs markdown — reading a `#heading` out of a document, and
--- finding a link or `<figure>` in a line — is roughly a tenth of the code,
--- and it now arrives through `lib.nvim.hover.registry` from the plugin that
--- owns markdown. The same door is how `images.nvim` draws the pictures and
--- `pdfport.nvim` rasterizes PDF pages: this module knows none of them by
--- name, they register into it.
---
--- Classification is `lib.nvim.hover.classify`, presentation
--- `lib.nvim.hover.float`, per-type content `lib.nvim.hover.preview.*`, and
--- "what is under the cursor with no link syntax at all"
--- `lib.nvim.hover.bare_path`.
---
--- Asynchronous previews (PDF rasterization, URL fetch) are guarded by a
--- generation counter: if the cursor moves on before the result lands, the
--- result is dropped rather than opening a float for a target the user has
--- already left.

local M = {}

local api = vim.api

local autocmd = require("lib.nvim.bindings.autocmd")
local classify = require("lib.nvim.hover.classify")
local float = require("lib.nvim.hover.float")

---@type integer Bumped on every request; stale async results compare against it.
local _generation = 0
---@type Lib.Debounce.Handle|nil
local _debounced = nil
---@type table|nil LRU cache of built content, keyed by target identity.
local _cache = nil

--- Defaults. A host plugin overrides them through `M.setup`; nothing here
--- reads another plugin's configuration, which is what let this module move
--- out of `markdown.nvim` without carrying it along.
---@type Lib.HoverConfig
local _config = {
  enabled = true,
  trigger = { "CursorHold" },
  delay_ms = 250,
  placeholder_grace_ms = 250,
  max_lines = 20,
  max_width = 80,
  border = "rounded",
  inline_images = true,
  bare_paths = true,
  url = { fetch = false, timeout_ms = 2000 },
}

--- Configure the hover. Merged over the current values, so a host can set
--- only what it cares about, and calling it twice does not reset the rest.
---@param opts Lib.HoverConfig|nil
---@return Lib.HoverConfig
function M.setup(opts)
  if type(opts) == "table" then
    _config = vim.tbl_deep_extend("force", _config, opts)
  end
  return _config
end

---@internal
--- The effective config, with the global kill switch folded in.
---
--- `vim.g.lib_nvim_hover_disable` exists because lib.nvim has no `setup()` of
--- its own — it is a lazily indexed namespace — so a user who wants no hover
--- at all has nowhere to say so except a `vim.g` flag set from their plugin
--- spec's `init`. It outranks whatever any plugin passed to `M.setup`: a
--- host enabling its hover must not override the user switching the feature
--- off globally. Same convention as `vim.g.lib_nvim_deps_disable_first_run`.
---@return Lib.HoverConfig
local function cfg()
  if vim.g.lib_nvim_hover_disable then
    -- A copy, so the stored config survives the flag being toggled back off
    -- at runtime rather than being permanently overwritten with `false`.
    return vim.tbl_extend("force", _config, { enabled = false })
  end
  return _config
end

---@internal
---@return table
local function cache()
  if _cache then
    return _cache
  end
  local ok, lru = pcall(require, "lib.lua.memo.lru")
  if ok and lru and lru.new then
    _cache = lru.new(64)
  else
    -- Plain table fallback: unbounded, but a hover cache holds short strings
    -- and the module still works without lib.lua.memo.
    local store = {}
    _cache = {
      get = function(_, key)
        return store[key]
      end,
      put = function(_, key, value)
        store[key] = value
      end,
    }
  end
  return _cache
end

---@internal
--- Identity of a target for caching. Includes mtime so an edited file is
--- re-read rather than served stale.
---@param target Lib.Hover.Target
---@return string
local function cache_key(target)
  local mtime = ""
  if target.path then
    local uv = vim.uv or vim.loop
    local stat = uv.fs_stat(target.path)
    if stat and stat.mtime then
      mtime = tostring(stat.mtime.sec)
    end
  end
  return table.concat(
    { target.type, target.raw, target.path or "", target.anchor or "", mtime },
    "|"
  )
end

--- The target under the cursor in `bufnr`, or nil.
---
--- Registered sources first, in registration order — `markdown.nvim`
--- contributes link scanning and `<figure>` resolution there — then the
--- built-in bare-path source. That order matters: on `[a](./b.png)` both
--- would answer, and the link is the more specific reading of the same text.
---
--- This does *not* fall back to "the only target on the line": a hover must
--- describe what the cursor is actually on, or it pops up while the cursor
--- sits in unrelated text.
---@param bufnr? integer
---@return Lib.Hover.Source|nil
function M.target_under_cursor(bufnr)
  -- `0` means "current buffer" by Neovim convention but is truthy in Lua, so
  -- `bufnr or ...` would leave it as 0 and the window/buffer check below would
  -- then compare a real handle against 0 and always bail out.
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= bufnr then
    return nil
  end

  local pos = api.nvim_win_get_cursor(win)
  local row, col = pos[1], pos[2]
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line then
    return nil
  end

  local target, extra = require("lib.nvim.hover.registry").source_at(bufnr, row, col)
  if target then
    local record = { target = target, lnum = row, col = col, col_end = col }
    for k, v in pairs(type(extra) == "table" and extra or {}) do
      record[k] = v
    end
    return record
  end

  -- Nothing claimed it: the text may be a path carrying no link syntax at all
  -- -- a path in prose, in a code comment, in a `:messages` dump. Same target
  -- shape, so everything downstream (classify/build/preview) is unchanged.
  if cfg().bare_paths == false then
    return nil
  end
  return require("lib.nvim.hover.bare_path").under_cursor(bufnr)
end

--- Backwards-compatible alias. The framework predates having sources other
--- than markdown links, and `markdown.hover.link_under_cursor` was public.
---@param bufnr? integer
---@return Lib.Hover.Source|nil
function M.link_under_cursor(bufnr)
  return M.target_under_cursor(bufnr)
end

---@internal
--- How long an async preview may take before it is allowed to interrupt the
--- reader with a placeholder. Below this, waiting quietly and showing only
--- the result reads as instant; above it, silence reads as breakage.
---
--- Configurable as `hover.placeholder_grace_ms`, because "instant" is a
--- property of the machine: on a fast one 250ms hides every placeholder that
--- would only have flickered, on a slow one it hides the reassurance that
--- something is happening at all.
---@return integer
local function placeholder_grace_ms()
  local n = cfg().placeholder_grace_ms
  return (type(n) == "number" and n >= 0) and n or 250
end

---@internal
--- Build the content for `target`, then hand it to `emit`. Synchronous
--- previewers call `emit` immediately; async ones later.
---@param target Lib.Hover.Target
---@param bufnr integer
---@param opts Lib.Hover.PreviewOpts
---@param emit fun(content: Lib.Hover.Content|nil)
local function build(target, bufnr, opts, emit)
  local text = require("lib.nvim.hover.preview.text")

  -- A registered preview claims its type outright. This is how anything
  -- needing knowledge the library does not have gets in: `markdown.nvim`
  -- registers `anchor` (and `markdown` targets carrying one), because
  -- resolving `#some-heading` means GFM slugging and heading parsing, which
  -- belong to the plugin that owns markdown, not here.
  local claimed = require("lib.nvim.hover.registry").preview_for(target.type)
  if claimed then
    -- A registered preview may decline (nil) -- an anchor that resolves to
    -- nothing, say -- and the built-in handling below is then still the
    -- better answer than an empty float.
    local ok, content = pcall(claimed, target, opts, bufnr)
    if ok and content then
      emit(content)
      return
    end
  end

  if target.type == "anchor" then
    -- No plugin claimed in-page anchors: nothing here can resolve a heading,
    -- so there is nothing honest to show.
    emit(nil)
  elseif target.type == "missing" then
    emit(text.missing(target))
  elseif target.type == "directory" then
    emit(text.directory(target, opts))
  elseif target.type == "markdown" or target.type == "file" then
    -- A `markdown` target with an unclaimed `#anchor` falls through to the
    -- plain file preview: the file still exists, only the fragment could not
    -- be resolved, and its first lines beat an error.
    emit(text.file(target, opts))
  elseif target.type == "image" then
    emit(require("lib.nvim.hover.preview.media").image(target, opts))
  elseif target.type == "pdf" then
    local media = require("lib.nvim.hover.preview.media")
    local generation = _generation
    local settled = false

    local provisional = media.pdf(target, opts, function(content)
      settled = true
      -- The cursor moved on while pdftoppm ran: the page is kept for the next
      -- hover (media owns it now), but nothing opens over the link the reader
      -- has already left.
      if generation ~= _generation then
        return
      end
      emit(content)
    end)

    if not provisional.pending then
      emit(provisional)
    else
      -- Hold the "rendering page 1…" float back. A render that beats the
      -- grace period shows the finished page and nothing else — no flash of
      -- a differently sized text float first. One that misses it has a real
      -- wait to explain, and then the float is worth its interruption.
      vim.defer_fn(function()
        if settled or generation ~= _generation then
          return
        end
        emit(provisional)
      end, placeholder_grace_ms())
    end
  elseif target.type == "url" then
    local url = require("lib.nvim.hover.preview.url")
    if opts.url_fetch then
      local generation = _generation
      url.fetch(target, opts, function(content)
        if generation ~= _generation then
          return
        end
        vim.schedule(function()
          if generation == _generation then
            emit(content)
          end
        end)
      end)
    else
      emit(url.offline(target))
    end
  else
    emit(nil)
  end
end

--- Show the hover for the link under the cursor. No-op when there is none.
---@param opts? { force?: boolean } `force` ignores the enabled flag.
---@return boolean shown
function M.show(opts)
  opts = opts or {}
  local c = cfg()
  if not opts.force and c.enabled == false then
    return false
  end

  local bufnr = api.nvim_get_current_buf()
  local link = M.link_under_cursor(bufnr)
  if not link then
    float.close()
    return false
  end

  _generation = _generation + 1
  local generation = _generation

  local source = api.nvim_buf_get_name(bufnr)
  local target = classify.classify(link.target, source ~= "" and source or nil)

  local preview_opts = {
    max_lines = c.max_lines or 20,
    max_width = c.max_width or 80,
    inline_images = c.inline_images,
    url_fetch = c.url and c.url.fetch == true,
    url_timeout_ms = c.url and c.url.timeout_ms or 2000,
  }

  local key = cache_key(target)
  local cached = cache():get(key)

  local function present(content)
    if generation ~= _generation then
      return
    end
    if not content then
      return
    end
    float.open(content.lines, {
      title = content.title,
      filetype = content.filetype,
      canvas = content.canvas,
      highlight = content.highlight,
      max_width = c.max_width or 80,
      max_height = c.max_lines or 20,
      border = c.border,
    })
    -- An image target draws over the float it just opened.
    if content.image_path then
      local win = float.win()
      if win then
        local on_close = require("lib.nvim.hover.preview.media").draw_into(content.image_path, win)
        if on_close then
          float.set_on_close(on_close)
        end
      end
    end
  end

  if cached and not cached.pending then
    present(cached)
    return true
  end

  build(target, bufnr, preview_opts, function(content)
    if content and not content.pending then
      cache():put(key, content)
    end
    present(content)
  end)

  return true
end

--- Close any open hover.
function M.hide()
  float.close()
end
--- Debounced entry point used by the CursorHold/mouse autocmds.
function M.trigger()
  local c = cfg()
  if c.enabled == false then
    return
  end

  if not _debounced then
    local ok, debounce = pcall(require, "lib.nvim.debounce")
    if ok and debounce and debounce.new then
      _debounced = debounce.new(function()
        M.show()
      end, c.delay_ms or 250)
    else
      -- Without lib.nvim.debounce, run undebounced rather than not at all.
      _debounced = {
        call = function()
          M.show()
        end,
        cancel = function() end,
      }
    end
  end
  _debounced.call()
end

--- Whether anything installed could actually produce a hover.
---
--- lib.nvim is a dependency of plugins, so it is routinely present with none
--- of them: a user who installs only `lib.nvim`, or who has markdown.nvim
--- without images.nvim, must not pay for autocmds that can never show
--- anything. Two ways to be useful, and at least one has to hold:
---
---  * a registered source (markdown.nvim's link scanner), or
---  * bare-path detection, which needs nothing installed at all.
---
--- Previews are deliberately *not* checked. Every target type has a built-in
--- answer here — a file gets its first lines, a directory its entries, an
--- image without any drawing provider still gets its dimensions and size from
--- `preview.media`'s metadata path. Missing images.nvim or pdfport degrades a
--- picture to a description; it never makes the hover useless.
---@return boolean
local function anything_to_show()
  if cfg().bare_paths ~= false then
    return true
  end
  return require("lib.nvim.hover.registry").has_sources()
end

--- Install the hover autocmds for `bufnr`.
---
--- Hosts typically attach on every filetype (a path is not a markdown
--- phenomenon), so the buffers that must be excluded are excluded here rather
--- than by pattern: a picker, a file tree, a terminal or a dashboard has no
--- document to hover in, and a float opening over one is always wrong.
--- `buftype ~= ""` catches all of them in one check, which a filetype
--- blocklist could never keep up with.
---@param bufnr integer
function M.attach(bufnr)
  local c = cfg()
  if c.enabled == false then
    return
  end
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= "" then
    return
  end
  -- Nothing registered and bare paths off: no autocmd, rather than one that
  -- wakes on every CursorHold to find there is nothing it can answer with.
  if not anything_to_show() then
    return
  end

  local group = autocmd.group("LibNvimHover" .. bufnr, true)
  local triggers = c.trigger or { "CursorHold" }

  if vim.tbl_contains(triggers, "CursorHold") then
    autocmd.create("CursorHold", function()
      M.trigger()
    end, {
      group = group,
      buffer = bufnr,
      desc = "[lib.nvim.hover] show the link under the cursor on CursorHold",
    })
  end

  if vim.tbl_contains(triggers, "mouse") then
    -- Mouse hovering needs `mousemoveevent`; it is a global user setting and
    -- is deliberately NOT set here (see README) -- without it this autocmd
    -- simply never fires.
    autocmd.create("CursorMoved", function()
      M.trigger()
    end, {
      group = group,
      buffer = bufnr,
      desc = "[lib.nvim.hover] show the link under the mouse (needs 'mousemoveevent')",
    })
  end

  autocmd.create({ "BufLeave", "InsertEnter" }, function()
    M.hide()
  end, {
    group = group,
    buffer = bufnr,
    desc = "[lib.nvim.hover] hide when leaving the buffer or entering insert",
  })
end

return M
