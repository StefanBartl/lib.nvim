---@module 'lib.nvim.ui.kit'
--- Themed, composable UI toolkit for lib.nvim.
---
--- Phase 1 surface: a theme/preset engine, a single-float `surface` primitive,
--- and the `note` component. `setup()` registers user presets and picks the
--- active default.
---
---   local kit = require("lib.nvim.ui.kit")
---   kit.popup({ type = "note", title = "Saved", message = "Wrote 3 files" })
---   local surf = kit.surface.open({ lines = { "hi" }, theme = "double" })

require("lib.nvim.ui.kit.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit]")

--- The component `name` (loaded on the first use: requiring the kit costs a table, not twenty modules).
---@param name string
---@return table
local function component(name)
  return require("lib.nvim.ui.kit." .. name)
end

local M = {}

--- Register user presets / set the active default preset.
---@param opts? Lib.UI.Kit.SetupOpts
function M.setup(opts)
  component("theme").setup(opts)
  -- Requiring the kit registers nothing (LUA-92); `:KitPreview` appears once
  -- the host calls `setup()` (here) or opens the playground via `preview()`.
  pcall(component("preview").ensure_command)
end

--- Open the live theme playground (config buffer + live-updating gallery).
---@return integer config_buf, integer preview_buf
function M.preview()
  return component("preview").open()
end

--- Open a note popup (title + message).
---@param opts Lib.UI.Kit.NoteOpts
---@return Lib.UI.Kit.Surface|nil
function M.note(opts)
  return component("note").open(opts)
end

--- Open a read-only info panel (auto-sized, q/<Esc> closes, closes on focus loss).
---@param opts Lib.UI.Kit.ViewerOpts
---@return Lib.UI.Kit.Surface|nil
function M.viewer(opts)
  return component("viewer").open(opts)
end

--- Open a scrollable, time-ordered, paginated, collapsible entry list popup
--- -- <C-j>/<C-k> load older/newer, <C-l>/<C-h>/<C-e> collapse mode, `?` a
--- cheatsheet. Knows nothing about where entries come from (plain tables in,
--- callbacks for more/live updates) -- see lib.nvim.ui.kit.message_log's module doc.
---@param opts Lib.UI.Kit.MessageLog.Opts
---@return Lib.UI.Kit.MessageLog.Handle|nil
function M.message_log(opts)
  return component("message_log").open(opts)
end

--- Show an ephemeral corner toast.
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.toast(opts)
  return component("toast").open(opts)
end

--- Open a single-line input. `opts.secret = true` masks it as you type (a
--- `vim.fn.inputsecret` replacement); `opts.completion = "file"` (or any
--- other `getcompletion()` type) wires `<Tab>` up to the native completion
--- popup (a `vim.fn.input`-with-`completion="file"` replacement) — see
--- lib.nvim.ui.kit.input.
---@param opts Lib.UI.Kit.InputOpts
---@return Lib.UI.Kit.Surface|nil
function M.input(opts)
  return component("input").open(opts)
end

--- Open a sequential multi-field form (chained `kit.input` prompts, one
--- keyed result table). See lib.nvim.ui.kit.form for the field contract.
---@param opts Lib.UI.Kit.FormOpts
---@return Lib.UI.Kit.Surface|nil
function M.form(opts)
  return component("form").open(opts)
end

--- Open ONE float with every field of a form at once (one labelled row each,
--- inline validation, a Submit/Cancel button row). The keyed result of
--- `on_submit` is `kit.form`'s. See lib.nvim.ui.kit.sheet for the field contract.
---@param opts Lib.UI.Kit.SheetOpts
---@return Lib.UI.Kit.Sheet|nil
function M.sheet(opts)
  return component("sheet").open(opts)
end

--- Open a live-incremental input: like `kit.input`, but also debounces
--- keystrokes into `opts.on_change(query)` as the user types.
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.live_input(opts)
  return component("live_input").open(opts)
end

--- Open a native themed list chooser (single/multi-select).
---@param opts table
function M.select(opts)
  return component("select").open(opts)
end

--- Ask a question (confirm / text).
---@param opts table
function M.prompt(opts)
  return component("prompt").open(opts)
end

--- Open an interactive picker (prompt drives the results/preview slots).
---@param opts table
---@return table|nil
function M.picker(opts)
  return component("picker").open(opts)
end

--- Open a promptless, stacked list+preview for a short list (a handful of
--- items) that doesn't need fuzzy search -- preview on top, results below,
--- both full width. See lib.nvim.ui.kit.shortlist for the `render(item, surface)`
--- contract (shared with `kit.compare`) and for the preview pane's keys
--- (`<C-f>`/`<C-p>` scroll it, `<Tab>` hops into it, `<CR>` there submits at the
--- cursor line via `on_preview_submit`, `q`/`<Esc>` close; `preview_keys`,
--- `close_on_leave` and `hints` switch parts of that off).
---@param opts table
---@return table|nil
function M.shortlist(opts)
  return component("shortlist").open(opts)
end

--- Pick two items out of one picker and view them side by side (a text diff
--- viewer, images.nvim's image comparison, …). See lib.nvim.ui.kit.compare
--- for the three-state flow (SEARCH → MARKED → COMPARE) and the `render`
--- contract.
---@param opts Lib.UI.Kit.CompareOpts
---@return Lib.UI.Kit.CompareHandle|nil
function M.compare(opts)
  return component("compare").open(opts)
end

--- Open a button-confirm dialog (horizontal buttons, h/l to move, <CR> confirm).
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.confirm(opts)
  return component("confirm").open(opts)
end

--- Yes/no question that waits for an open dialog instead of replacing it, and
--- answers `false` ("no") whenever it cannot get a real answer; falls back to
--- `vim.ui.select` when the float cannot open. See `lib.nvim.ui.kit.confirm.ask`.
---@param opts { question: string, on_answer: fun(yes: boolean), abandoned?: (fun(): boolean), theme?: any, title?: string, max_wait_ms?: integer }
function M.ask(opts)
  return component("confirm").ask(opts)
end

--- Ask what to do about a path that does not exist: Create (the file or directory with every
--- missing parent, via `lib.nvim.fs.create_entry`, then open it), Open in filetree (only when
--- filetree.nvim is loaded and set up, or `opts.filetree` is a function) or Cancel. `opts.on_done`
--- gets one result table. See `lib.nvim.ui.kit.create_on_missing`.
---@param opts Lib.UI.Kit.CreateOnMissingOpts
---@return Lib.UI.Kit.Surface|nil
function M.create_on_missing(opts)
  return component("create_on_missing").open(opts)
end

--- Open a cursor-anchored action menu (label → callback).
---@param opts table
---@return Lib.UI.Kit.Surface|nil
function M.menu(opts)
  return component("menu").open(opts)
end

--- Progress indicator. Thin passthrough to the dedicated `lib.nvim.progress`
--- module (styles: fidget / float / notify / statusline); not reimplemented
--- here. Returns its handle (`:update` / `:finish` / `:cancel`).
---@param opts table
---@return table
function M.progress(opts)
  return require("lib.nvim.progress").create(opts)
end

--- Set the dialog hook: a function `(kind, opts) -> handled, value` that is offered every modal dialog
--- (`confirm`, `ask`, `input`, `select`, `form`, `sheet`) before it opens, and may answer it without a
--- window (`nil` removes it). For tests; see `lib.nvim.ui.kit.hook`.
---@param fn Lib.UI.Kit.DialogHook|nil
function M.set_dialog_hook(fn)
  require("lib.nvim.ui.kit.hook").set(fn)
end

--- The dialog hook that is set, if any.
---@return Lib.UI.Kit.DialogHook|nil
function M.get_dialog_hook()
  return require("lib.nvim.ui.kit.hook").get()
end

--- Component dispatch table.
local COMPONENTS = {
  note = function(opts)
    return component("note").open(opts)
  end,
  viewer = function(opts)
    return component("viewer").open(opts)
  end,
  message_log = function(opts)
    return component("message_log").open(opts)
  end,
  toast = function(opts)
    return component("toast").open(opts)
  end,
  input = function(opts)
    return component("input").open(opts)
  end,
  live_input = function(opts)
    return component("live_input").open(opts)
  end,
  form = function(opts)
    return component("form").open(opts)
  end,
  sheet = function(opts)
    return component("sheet").open(opts)
  end,
  select = function(opts)
    return component("select").open(opts)
  end,
  prompt = function(opts)
    return component("prompt").open(opts)
  end,
  picker = function(opts)
    return component("picker").open(opts)
  end,
  confirm = function(opts)
    return component("confirm").open(opts)
  end,
  menu = function(opts)
    return component("menu").open(opts)
  end,
  compare = function(opts)
    return component("compare").open(opts)
  end,
  shortlist = function(opts)
    return component("shortlist").open(opts)
  end,
  progress = function(opts)
    return require("lib.nvim.progress").create(opts)
  end,
}

--- Friendly front door: dispatch on `opts.type` (default "note"). Supported
--- types: note, viewer, message_log, toast, input, live_input, form, sheet,
--- select, prompt, picker, confirm, menu, compare, shortlist, progress.
---@param opts table
---@return any
function M.popup(opts)
  opts = opts or {}
  local t = opts.type or "note"

  local handler = COMPONENTS[t]
  if handler then
    return handler(opts)
  end

  notify.error(("unknown popup type %q"):format(tostring(t)))
  return nil
end

--- Module fields, loaded on the first access (and then kept on `M`):
---   * `theme`, `surface`, `layout`, `chip` -- the building blocks
---   * `chooser` -- the native chooser `kit.select` delegates to, exposed directly for a consumer building a
---     persistent multi-action list on top of a picker (extra keymaps that read the highlighted item without
---     submitting/closing). `kit.select` covers the common case; reach for this only when you need
---     `current_item()`/`current_index()`/`move()` outside of `on_select`. Single active instance, same as
---     `kit.select` itself (they share one chooser).
---   * `keys` -- winbar legend and cheatsheet for keys a view binds itself (also outside `kit.viewer`, e.g. two
---     plain splits): `legend`, `cheatsheet_lines`, `cheatsheet`. Only this copy of the kit has it
---     (see `viewer_keys.lua`).
---   * `async` -- linear code over the callback components, without blocking: `kit.async.run(function() ... end)`,
---     then `kit.async.confirm/ask/input/form/select` inside it. See `lib.nvim.ui.kit.async`.
---   * `history` -- a back/forward trail of positions with a `CLEAR` sentinel for patches (pure data, no UI):
---     `kit.history.new({ state = st, keys = { ... } })`, then `:go`/`:back`/`:forward`. See `lib.nvim.ui.kit.history`.
---@type table<string, string>
local LAZY_FIELDS = {
  theme = "theme",
  surface = "surface",
  layout = "layout",
  chip = "chip",
  chooser = "chooser",
  keys = "viewer_keys",
  async = "async",
  history = "history",
}

setmetatable(M, {
  __index = function(t, key)
    local name = LAZY_FIELDS[key]
    if not name then
      return nil
    end
    local mod = component(name)
    rawset(t, key, mod)
    return mod
  end,
})

---@type Lib.UI.Kit
return M
