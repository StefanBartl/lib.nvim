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
  -- Two pairs, because a key that is not on the keyboard cannot be pressed:
  -- laptop and 60% layouts often reach PageUp/PageDown only through an Fn
  -- chord, and nothing at runtime can tell us whether this keyboard has
  -- them. The arrows are on every keyboard there is; both pairs are bound,
  -- and either one scrolls. Ctrl rather than Alt on the arrows: <M-Up> and
  -- <M-Down> are a common "move this line" binding, and the borrowing is
  -- only supposed to last as long as the float.
  scroll_keys = {
    down = { "<M-PageDown>", "<C-Down>" },
    up = { "<M-PageUp>", "<C-Up>" },
  },
  -- `q` and `<Esc>` are what a reader reaches for, and neither can reach the
  -- float itself: it is `focusable = false`, so it never holds a mapping and
  -- never receives a keystroke. They are borrowed globally for as long as a
  -- hover is on screen, exactly like the scroll keys, and handed back the
  -- moment it closes -- which costs `q` its macro recording for the lifetime
  -- of one float and nothing beyond it.
  dismiss_keys = { "q", "<Esc>" },
}

--- Configure the hover. Merged over the current values, so a host can set
--- only what it cares about, and calling it twice does not reset the rest.
---@param opts Lib.HoverConfig|nil
---@return Lib.HoverConfig
function M.setup(opts)
  if type(opts) == "table" then
    _config = vim.tbl_deep_extend("force", _config, opts)
    -- `tbl_deep_extend` merges lists by index, so `{ down = { "<C-n>" } }`
    -- would leave the default's second key sitting at index 2 and bind both.
    -- A configured key list replaces the default outright.
    if type(opts.scroll_keys) == "table" then
      for _, dir in ipairs({ "down", "up" }) do
        if opts.scroll_keys[dir] ~= nil then
          _config.scroll_keys[dir] = opts.scroll_keys[dir]
        end
      end
    end
    -- The same trap one level shallower: `{ "<C-c>" }` deep-extended over
    -- `{ "q", "<Esc>" }` leaves `<Esc>` sitting at index 2 and still bound.
    if opts.dismiss_keys ~= nil then
      _config.dismiss_keys = opts.dismiss_keys
    end
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

---@internal
--- Identity of a target for a *dismissal* -- "is this still the same thing
--- the reader waved away?"
---
--- Deliberately not `cache_key`: that carries the file's mtime, so saving the
--- file you are standing in would end the dismissal and pop the float back.
--- Deliberately not the line either -- a dismissed hover has to survive its
--- path sliding down the buffer as you edit above it, which is precisely the
--- situation the dismissal exists for.
---@param target Lib.Hover.Target
---@return string
local function identity(target)
  return table.concat({ target.type, target.raw, target.path or "", target.anchor or "" }, "|")
end

---@type string|nil Identity of a target dismissed by `M.dismiss`, until the cursor leaves it.
local _suppressed = nil

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

--- What the currently open hover is showing, so it can be re-rendered at a
--- different position without re-resolving the cursor. Cleared on close.
---@type { target: Lib.Hover.Target, bufnr: integer, offset: integer, page: integer, keys: Lib.Hover.BoundKey[] }|nil
local _open = nil

---@internal
--- Drop every keymap this module installed globally for the hover on screen,
--- and put back whatever each of them shadowed.
---
--- Global rather than buffer-local because the float is `focusable = false`
--- and can never receive a mapping of its own — and buffer-local on the
--- *document* would leak into buffers that have no hover open. They exist
--- only while a hover is on screen, and `float`'s close hook is what takes
--- them away again.
---
--- Restoring rather than deleting is not a nicety: `<C-Up>` and `q` are keys
--- a user may well have mapped, and a hover that borrows one for a single
--- float must hand it back.
---@return nil
local function unbind_keys()
  if not (_open and _open.keys) then
    return
  end
  for _, k in ipairs(_open.keys) do
    pcall(vim.keymap.del, "n", k.lhs)
    if k.saved then
      pcall(vim.fn.mapset, "n", false, k.saved)
    end
  end
  _open.keys = nil
end

---@internal
--- Normalize one configured key list. A bare string is a single key; a
--- missing entry is no key at all, which is how a host turns one direction
--- (or both) off.
---@param v string|string[]|nil
---@return string[]
local function keylist(v)
  if type(v) == "string" then
    return { v }
  elseif type(v) == "table" then
    return v
  end
  return {}
end

---@internal
--- Bind the keys the hover on screen borrows: the dismiss keys always, the
--- scroll keys only when there is something to scroll.
---
--- The asymmetry is the point. Every hover can be waved away, so `q` and
--- `<Esc>` are bound for all of them. Scrolling an image or a file that
--- already fits is meaningless, so those keys are left alone entirely and
--- keep whatever they mean elsewhere.
---@param content Lib.Hover.Content
---@param rerender fun(delta: integer)
---@return nil
local function bind_keys(content, rerender)
  unbind_keys()
  if not _open then
    return
  end

  local c = cfg()
  local keys = {}
  local seen = {}
  ---@param lhs any
  ---@param rhs fun()
  ---@param desc string
  local function borrow(lhs, rhs, desc)
    -- The same key listed twice — both scroll directions, or a dismiss key
    -- that is also a scroll key — would, on unbind, restore one of our own
    -- mappings as if it had been the user's, and then it would outlive the
    -- float forever.
    if type(lhs) ~= "string" or lhs == "" or seen[lhs] then
      return
    end
    seen[lhs] = true
    local raw = vim.fn.maparg(lhs, "n", false, true)
    -- A separate local, not an overwrite of `raw`: `maparg`'s dict form is
    -- typed as a table, and nilling that same variable is a type change
    -- rather than a narrowing.
    ---@type table|nil
    local saved = (type(raw) == "table" and raw.lhs ~= nil) and raw or nil
    local ok = pcall(vim.keymap.set, "n", lhs, rhs, { desc = desc, nowait = true, silent = true })
    if ok then
      keys[#keys + 1] = { lhs = lhs, saved = saved }
    end
  end

  -- Dismiss first, so a key configured for both wins as a dismissal: the one
  -- that always works beats the one that only sometimes applies.
  for _, lhs in ipairs(keylist(c.dismiss_keys)) do
    borrow(lhs, function()
      M.dismiss()
    end, "lib.nvim.hover: dismiss this hover")
  end

  local s = content and content.scroll
  -- Nothing below and nothing above: not scrollable in either direction.
  local at_start = s and (s.offset or 0) == 0 and (s.page or 1) == 1
  if s and (s.more or not at_start) then
    local sk = type(c.scroll_keys) == "table" and c.scroll_keys or {}
    for _, lhs in ipairs(keylist(sk.down)) do
      borrow(lhs, function()
        rerender(1)
      end, "lib.nvim.hover: scroll preview down")
    end
    for _, lhs in ipairs(keylist(sk.up)) do
      borrow(lhs, function()
        rerender(-1)
      end, "lib.nvim.hover: scroll preview up")
    end
  end

  _open.keys = keys
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
    -- The most common exit by far, since moving the cursor off a link comes
    -- back through here. `hide` rather than `float.close`, for the two things
    -- it does besides closing: hand back the borrowed keys, and bump the
    -- generation. Without the bump a PDF still rasterizing for the link that
    -- was just left would land afterwards, match the unchanged generation and
    -- open a float over a line the reader has moved past.
    M.hide()
    -- The cursor is on nothing at all, so it has left whatever was dismissed:
    -- going back to that target should show it again.
    _suppressed = nil
    return false
  end

  local source = api.nvim_buf_get_name(bufnr)
  local target = classify.classify(link.target, source ~= "" and source or nil)

  if _suppressed then
    if opts.force or _suppressed ~= identity(target) then
      -- Either the cursor reached a different target, or a caller asked for
      -- this one outright. Both end the dismissal.
      _suppressed = nil
    else
      -- Still standing on the thing that was waved away. Nothing to close —
      -- `dismiss` already did that — and nothing to open.
      return false
    end
  end

  _generation = _generation + 1
  local generation = _generation

  unbind_keys()
  _open = { target = target, bufnr = bufnr, offset = 0, page = 1 }

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
      -- The float dismisses itself on the next cursor move, through an
      -- autocmd this module never hears about. Without a hook there, the
      -- keys it borrowed would stay bound until the next `CursorHold` — up
      -- to `updatetime` in which `q` records no macro and `<Esc>` does
      -- nothing, long after the float they belonged to is gone.
      on_close = unbind_keys,
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

    bind_keys(content, M.scroll)
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

--- Scroll the open hover's content by `delta` steps.
---
--- A page for a PDF, a screenful of lines for a file. Re-renders the same
--- target at a new position; it does **not** re-resolve the cursor, so the
--- hover keeps showing what it was showing even if the cursor has since moved
--- off the link.
---
--- Bound to `scroll_keys` while a scrollable hover is open (see
--- `bind_keys`), and public so a host can offer its own keys. Deliberately
--- no image case: there is nothing to scroll in a picture.
---@param delta integer positive scrolls forward, negative back
---@return boolean scrolled
function M.scroll(delta)
  -- Also the safety net for a mapping that outlived its float by any route
  -- the explicit teardowns do not cover: it takes itself away rather than
  -- silently swallowing the key from then on.
  if not (_open and float.win()) then
    unbind_keys()
    _open = nil
    return false
  end
  local target = _open.target
  local c = cfg()

  local preview_opts = {
    max_lines = c.max_lines or 20,
    max_width = c.max_width or 80,
    inline_images = c.inline_images,
    url_fetch = c.url and c.url.fetch == true,
    url_timeout_ms = c.url and c.url.timeout_ms or 2000,
  }

  if target.type == "pdf" then
    local next_page = math.max(1, (_open.page or 1) + delta)
    if next_page == _open.page then
      return false
    end
    _open.page = next_page
    preview_opts.page = next_page
  else
    local step = c.max_lines or 20
    local next_offset = math.max(0, (_open.offset or 0) + delta * step)
    if next_offset == _open.offset then
      return false
    end
    _open.offset = next_offset
    preview_opts.offset = next_offset
  end

  -- Bypass the cache: it is keyed by target identity, not by position, so a
  -- cached entry would answer with the page the hover already shows.
  _generation = _generation + 1
  local generation = _generation

  build(target, _open.bufnr, preview_opts, function(content)
    if generation ~= _generation or not content or content.pending then
      return
    end
    -- Paged past the last PDF page: step back and leave what is on screen.
    if content.scroll and content.scroll.past_end then
      _open.page = math.max(1, (_open.page or 1) - delta)
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
      -- The float dismisses itself on the next cursor move, through an
      -- autocmd this module never hears about. Without a hook there, the
      -- keys it borrowed would stay bound until the next `CursorHold` — up
      -- to `updatetime` in which `q` records no macro and `<Esc>` does
      -- nothing, long after the float they belonged to is gone.
      on_close = unbind_keys,
    })
    if content.image_path then
      local win = float.win()
      if win then
        local on_close = require("lib.nvim.hover.preview.media").draw_into(content.image_path, win)
        if on_close then
          float.set_on_close(on_close)
        end
      end
    end
    bind_keys(content, M.scroll)
  end)

  return true
end

--- Close any open hover.
---
--- Bumps the generation counter as well: a PDF page still rasterizing when
--- this is called would otherwise land afterwards and open a float for a
--- hover that has already been closed.
function M.hide()
  unbind_keys()
  _open = nil
  _generation = _generation + 1
  float.close()
end

--- Close the hover on screen and keep it closed for as long as the cursor
--- stays on the same target.
---
--- **Why closing alone is not enough.** `CursorHold` fires again after any
--- keystroke followed by `updatetime` of quiet — cursor movement or not. A
--- key bound to `hide()` would make the float disappear and then bring it
--- straight back, while the reader is still standing on the path they wanted
--- out of the way.
---
--- The suppression ends by itself: the next target the cursor resolves —
--- another path, or none at all — clears it. That is the whole difference
--- between this and `toggle(false)`, and why both exist. This one is for
--- "not now, I am reading this line"; the toggle is for "not for a while",
--- and only the toggle has to be remembered and undone.
---@return boolean dismissed false when no hover was open
function M.dismiss()
  if not _open then
    return false
  end
  _suppressed = identity(_open.target)
  M.hide()
  return true
end

--- Whether a hover would open at all right now.
---
--- Reads the same effective config the trigger does, so it accounts for both
--- the `vim.g` kill switch and whatever a host configured.
---@return boolean
function M.is_enabled()
  return cfg().enabled ~= false
end

--- Turn the hover off for the rest of the session, or back on.
---
--- The state lives in `vim.g.lib_nvim_hover_disable` — the switch this module
--- already documents — so toggling at runtime and setting it in a plugin spec
--- are one setting rather than two that can disagree.
---
--- Two things this has to do beyond flipping the flag:
---
---  * **Re-`enable()` on the way back on.** `attach()` installs nothing while
---    the hover is off, so every buffer opened during that time has no
---    autocmd of its own. Flipping the flag alone would leave those buffers
---    silently dead, which reads as "the toggle only half works". `enable()`
---    is idempotent and re-attaches every loaded buffer.
---  * **Outrank a host's `enabled = false`.** That was a default; a user
---    asking for the hover at runtime is not. Without this the command would
---    do nothing at all in exactly the configuration where someone is most
---    likely to reach for it.
---@param on? boolean explicit state; omitted flips the current one
---@return boolean on the state now in effect
function M.toggle(on)
  if on == nil then
    on = not M.is_enabled()
  end

  -- A dismissal is scoped to "the target the cursor is on right now", and
  -- throwing the session switch is not that. Left standing, it would survive
  -- an off/on cycle as invisible state and make the hover look like it came
  -- back only half on.
  _suppressed = nil

  if on then
    vim.g.lib_nvim_hover_disable = false
    _config.enabled = true
    M.enable()
  else
    vim.g.lib_nvim_hover_disable = true
    M.hide()
  end

  -- Announced, because "off" is invisible: nothing on screen tells a hover
  -- that is switched off apart from a line that simply has no target on it,
  -- and a switch whose state cannot be seen gets reported as a broken
  -- feature days later.
  require("lib.nvim.notify").create("[lib.nvim.hover]").info(on and "hover on" or "hover off")

  return on
end

--- Composer routes for `:Lib hover …`, in the shape
--- `lib.nvim.bindings.usercmd.composer` expects. Wired up by
--- `lib.nvim_usrcmds`, next to `:Lib deps …`.
---
--- A command and not a keymap: `lib.nvim_usrcmds` states that a library other
--- plugins depend on has no business claiming a key on their behalf, and a
--- session-wide switch is not something that needs to be one keystroke away
--- anyway. The per-hover dismissal is the one that does, and it has its keys
--- only for as long as there is a float to dismiss.
---@return table[]
function M.routes()
  return {
    {
      path = { "hover", "toggle" },
      desc = "Turn the path/link hover off for this session, or back on",
      run = function()
        M.toggle()
      end,
    },
    {
      path = { "hover", "on" },
      desc = "Turn the path/link hover on",
      run = function()
        M.toggle(true)
      end,
    },
    {
      path = { "hover", "off" },
      desc = "Turn the path/link hover off",
      run = function()
        M.toggle(false)
      end,
    },
  }
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

--- Switch the hover on globally: install the `FileType` autocmd that attaches
--- it to every buffer matching `filetypes`, and attach it to the buffers that
--- are already open.
---
--- **Why the library installs its own trigger.** The framework lives here,
--- but for a while the only thing that turned it on was `markdown.nvim`'s
--- `FileType` autocmd — and that plugin is lazy-loaded on markdown filetypes.
--- Open a `.txt` in a fresh session and markdown.nvim never loads, so nothing
--- ever attached: the hover worked in other filetypes only after some markdown
--- file had been opened first, which reads as "it randomly doesn't work".
--- A feature that is explicitly not about markdown cannot have its trigger
--- gated on a markdown plugin loading.
---
--- Callable from anywhere: a plugin's `config`, or a user's own `init` for
--- `lib.nvim` itself. Idempotent — the augroup is cleared on each call, so
--- calling it from two plugins leaves one autocmd, not two.
---
--- Already-open buffers are attached directly, because `FileType` has long
--- since fired for them and would otherwise leave the very buffer the user is
--- sitting in without a hover until they reopen it.
---@param opts Lib.HoverConfig|nil merged via `M.setup` before attaching
---@return nil
function M.enable(opts)
  if type(opts) == "table" then
    M.setup(opts)
  end

  local c = cfg()
  if c.enabled == false then
    return
  end

  local group = autocmd.group("LibNvimHoverEnable", true)
  autocmd.create("FileType", function(ev)
    M.attach(ev.buf)
  end, {
    group = group,
    pattern = c.filetypes or "*",
    desc = "[lib.nvim.hover] attach the path/link hover to this buffer",
  })

  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      pcall(M.attach, buf)
    end
  end
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
