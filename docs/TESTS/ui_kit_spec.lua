-- docs/TESTS/ui_kit_spec.lua — lib.nvim.ui.kit
-- Phase 1 (theme, surface, note), Phase 2 (toast, input, prompt),
-- Phase 3 (layout + picker, native chooser + hover_select shim, interactive picker),
-- Phase 4 (button-confirm), Phase 5 (viewer: read-only info panel),
-- Phase 6 (form: sequential multi-field prompt),
-- Phase 7 (live_input: debounced on_change as you type).

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local theme = kit.theme

  -- --------------------------------------------------------------- theme
  -- preset by name
  local double = theme.resolve("double")
  eq(double.border, "double", "preset name resolves border")

  -- default when nil
  local def = theme.resolve(nil)
  eq(def.border, "rounded", "nil resolves to default preset (rounded)")

  -- ascii preset flag
  eq(theme.resolve("ascii").ascii_border, true, "ascii preset sets ascii_border")

  -- presets differ beyond the border: distinct highlight link targets
  eq(
    theme.resolve("minimal").hl.selection,
    "Visual",
    "minimal preset has a distinct selection link"
  )
  eq(theme.resolve("double").hl.accent, "WarningMsg", "double preset has a distinct accent link")
  eq(theme.resolve("rounded").hl.normal, "NormalFloat", "rounded (default) keeps the base palette")

  -- partial override merges over the active default
  local custom = theme.resolve({ hl = { accent = "WarningMsg" } })
  eq(custom.border, "rounded", "override keeps default preset's border")
  eq(custom.hl.accent, "WarningMsg", "override replaces one hl key")
  eq(custom.hl.normal, "NormalFloat", "override leaves other hl keys intact")

  -- unknown preset name falls back to default
  eq(theme.resolve("does-not-exist").border, "rounded", "unknown preset -> default")

  -- setup registers a user preset and can switch the default
  kit.setup({ presets = { spec_preset = { border = "single" } } })
  eq(theme.resolve("spec_preset").border, "single", "user preset registered")
  ok(vim.tbl_contains(theme.presets(), "spec_preset"), "preset listed")

  -- --------------------------------------------------------------- surface
  local s = assert(
    kit.surface.open({ lines = { "hello", "world" }, theme = "double", title = "T" }),
    "surface.open returns a handle"
  )
  ok(s:is_valid(), "surface window is valid")
  eq(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false)[1], "hello", "surface content set")

  -- winhighlight wired to the Kit* groups
  local winhl = vim.api.nvim_get_option_value("winhighlight", { win = s.winid })
  ok(winhl:find("NormalFloat:KitNormal", 1, true), "winhighlight maps NormalFloat->KitNormal")

  -- Kit* highlight groups were materialized
  ok(vim.fn.hlexists("KitNormal") == 1, "KitNormal highlight group defined")
  ok(vim.fn.hlexists("KitBorder") == 1, "KitBorder highlight group defined")

  -- set_lines respects the modifiable lock
  s:set_lines({ "changed" })
  eq(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false)[1], "changed", "set_lines updates content")

  -- on_close fires exactly once
  local closes = 0
  s:on_close(function()
    closes = closes + 1
  end)
  s:close()
  ok(not s:is_valid(), "surface closed")
  eq(closes, 1, "on_close fired once")
  s:close() -- idempotent
  eq(closes, 1, "on_close not fired again on second close")

  -- --------------------------------------------------------------- note
  local n = assert(kit.note({ title = "Saved", message = "wrote 3 files" }), "note opens")
  ok(n:is_valid(), "note float is valid")
  eq(vim.api.nvim_buf_get_lines(n.bufnr, 0, -1, false)[1], "wrote 3 files", "note shows message")
  n:close()

  -- note accepts a multiline (array) message
  local n2 = assert(kit.note({ message = { "a", "b", "c" } }), "note (array) opens")
  eq(#vim.api.nvim_buf_get_lines(n2.bufnr, 0, -1, false), 3, "note renders array message lines")
  n2:close()

  -- -------------------------------------------------------------- viewer
  local v = assert(kit.viewer({ title = "Info", lines = { "line 1", "line 2" } }), "viewer opens")
  ok(v:is_valid(), "viewer float is valid")
  eq(#vim.api.nvim_buf_get_lines(v.bufnr, 0, -1, false), 2, "viewer shows every line")
  eq(
    vim.api.nvim_get_option_value("modifiable", { buf = v.bufnr }),
    false,
    "viewer buffer is read-only"
  )
  v:close()

  -- viewer accepts `message` as an alias for `lines` (single string, split on \n)
  local v2 = assert(kit.viewer({ message = "a\nb\nc" }), "viewer (message alias) opens")
  eq(
    #vim.api.nvim_buf_get_lines(v2.bufnr, 0, -1, false),
    3,
    "viewer splits a string message on newlines"
  )
  v2:close()

  -- viewer closes itself the moment focus moves elsewhere (unlike note)
  local v3 = assert(kit.viewer({ message = "dismiss me" }), "viewer opens for focus-loss test")
  ok(v3:is_valid(), "viewer valid before losing focus")
  vim.cmd("new")
  vim.wait(50)
  ok(not v3:is_valid(), "viewer auto-closes on WinLeave")
  vim.cmd("only")

  -- close_on_focus_lost = false opts out of that behavior
  local v4 = assert(
    kit.viewer({ message = "stay open", close_on_focus_lost = false }),
    "viewer opens with close_on_focus_lost disabled"
  )
  vim.cmd("new")
  vim.wait(50)
  ok(v4:is_valid(), "viewer stays open when close_on_focus_lost = false")
  v4:close()
  vim.cmd("only")

  -- --------------------------------------------------------------- toast
  local toast_mod = require("lib.nvim.ui.kit.toast")
  toast_mod.clear()
  local t1 = assert(kit.toast({ message = "first", timeout = 0 }), "toast opens")
  ok(t1:is_valid(), "toast float valid")
  eq(toast_mod.active(), 1, "one toast active")
  local t2 = assert(kit.toast({ message = "second", timeout = 0 }), "second toast opens")
  eq(toast_mod.active(), 2, "two toasts stack")
  -- stacked below the first (higher row)
  local r1 = vim.api.nvim_win_get_config(t1.winid).row
  local r2 = vim.api.nvim_win_get_config(t2.winid).row
  ok(tonumber(tostring(r2)) > tonumber(tostring(r1)), "second toast sits below the first")
  toast_mod.clear()
  eq(toast_mod.active(), 0, "clear removes all toasts")

  -- --------------------------------------------------------------- input
  local inp = assert(kit.input({ prompt = "Name", default = "sb" }), "input opens")
  ok(inp:is_valid(), "input float valid")
  eq(vim.api.nvim_buf_get_lines(inp.bufnr, 0, 1, false)[1], "sb", "input seeded with default")
  vim.cmd("stopinsert")
  inp:close()

  -- --------------------------------------------------------------- live_input
  -- `TextChangedI`/`TextChanged` don't fire for API-driven buffer edits in
  -- this headless runner (no real insert-mode session), so tests fire them
  -- explicitly via nvim_exec_autocmds after editing the buffer -- exactly
  -- the event live_input's own debounce timer listens for.
  local li_changes = {}
  local li = assert(
    kit.live_input({
      prompt = "Search",
      debounce = 20,
      on_change = function(q)
        table.insert(li_changes, q)
      end,
    }),
    "live_input opens"
  )
  ok(li:is_valid(), "live_input float valid")
  vim.api.nvim_buf_set_lines(li.bufnr, 0, 1, false, { "h" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = li.bufnr })
  vim.wait(60)
  vim.api.nvim_buf_set_lines(li.bufnr, 0, 1, false, { "he" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = li.bufnr })
  vim.wait(60)
  eq(table.concat(li_changes, ","), "h,he", "on_change fires once per debounce window, in order")
  li:close()

  -- rapid edits within one debounce window coalesce into a single on_change
  -- call carrying only the final value.
  local li_coalesced = {}
  local li2 = assert(
    kit.live_input({
      debounce = 50,
      on_change = function(q)
        table.insert(li_coalesced, q)
      end,
    }),
    "live_input (coalescing) opens"
  )
  vim.api.nvim_buf_set_lines(li2.bufnr, 0, 1, false, { "h" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = li2.bufnr })
  vim.api.nvim_buf_set_lines(li2.bufnr, 0, 1, false, { "he" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = li2.bufnr })
  vim.api.nvim_buf_set_lines(li2.bufnr, 0, 1, false, { "hel" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = li2.bufnr })
  vim.wait(120)
  eq(#li_coalesced, 1, "rapid edits within the debounce window fire on_change only once")
  eq(li_coalesced[1], "hel", "the coalesced on_change carries the final value")
  li2:close()

  -- row/col are forwarded to the surface (anchoring next to a host window,
  -- e.g. filetree.nvim's live_search bar at the bottom of the tree window),
  -- overriding the default editor-centered placement.
  local li_pos = assert(
    kit.live_input({
      relative = "editor",
      row = 3,
      col = 5,
      on_change = function() end,
    }),
    "live_input (row/col) opens"
  )
  local win_cfg = vim.api.nvim_win_get_config(li_pos.winid)
  eq(win_cfg.row, 3, "row is forwarded to the surface")
  eq(win_cfg.col, 5, "col is forwarded to the surface")
  li_pos:close()

  -- <CR> submits the current query and closes
  local li_submitted
  kit.live_input({
    default = "seed",
    on_change = function() end,
    on_submit = function(q)
      li_submitted = q
    end,
  })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  eq(li_submitted, "seed", "<CR> submits the current query")

  -- <Esc> cancels without submitting
  local li_cancelled, li_wrongly_submitted
  local li3 = assert(
    kit.live_input({
      on_change = function() end,
      on_submit = function()
        li_wrongly_submitted = true
      end,
      on_cancel = function()
        li_cancelled = true
      end,
    }),
    "live_input (cancel) opens"
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  ok(li_cancelled, "<Esc> fires on_cancel")
  ok(not li_wrongly_submitted, "<Esc> never fires on_submit")
  ok(not li3:is_valid(), "<Esc> closes the float")

  -- routed via kit.popup({ type = "live_input" })
  local li_popup_changes = {}
  local li4 = assert(
    kit.popup({
      type = "live_input",
      debounce = 20,
      on_change = function(q)
        table.insert(li_popup_changes, q)
      end,
    }),
    'kit.popup({ type = "live_input" }) opens'
  )
  vim.api.nvim_buf_set_lines(li4.bufnr, 0, 1, false, { "x" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = li4.bufnr })
  vim.wait(60)
  eq(li_popup_changes[1], "x", 'kit.popup({ type = "live_input" }) routes to live_input')
  li4:close()

  -- --------------------------------------------------------------- form
  -- Buffer edits + <CR>/<Esc> feedkeys stand in for typing: this headless
  -- runner never actually enters insert mode (no UI attached to redraw into
  -- it), but the input component binds <CR>/<Esc> in both "i" and "n" modes,
  -- so driving it from Normal mode exercises the same finish() path.
  local function submit_field(text)
    vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, 1, false, { text })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  end
  local function skip_field()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end

  -- full submit: both fields typed, on_submit gets a keyed table
  local form_values
  local form_surf = assert(
    kit.form({
      fields = {
        { name = "a", label = "A", default = "defA" },
        { name = "b", label = "B", default = "defB" },
      },
      on_submit = function(values)
        form_values = values
      end,
    }),
    "form opens (returns the first field's surface)"
  )
  ok(form_surf:is_valid(), "form's first field is a real surface")
  eq(
    vim.api.nvim_buf_get_lines(form_surf.bufnr, 0, 1, false)[1],
    "defA",
    "first field seeded with its default"
  )
  submit_field("hello")
  submit_field("world")
  eq(form_values.a, "hello", "form collects the first field under its name")
  eq(form_values.b, "world", "form collects the second field under its name")

  -- optional fields: <Esc> skips (keeps the default) and the form continues
  local skip_values
  kit.form({
    fields = {
      { name = "a", label = "A", default = "" },
      { name = "b", label = "B", default = "keepme" },
    },
    on_submit = function(values)
      skip_values = values
    end,
  })
  skip_field() -- skip "a"
  skip_field() -- skip "b" -> keeps default
  eq(skip_values.a, "", "skipping an optional field with no default -> empty string")
  eq(skip_values.b, "keepme", "skipping an optional field keeps its default")

  -- required field: <Esc> aborts the whole form, on_cancel fires, no on_submit
  local aborted, abort_submitted
  kit.form({
    fields = {
      { name = "a", label = "A", default = "defA" },
      { name = "b", label = "B", default = "defB", required = true },
    },
    on_submit = function()
      abort_submitted = true
    end,
    on_cancel = function()
      aborted = true
    end,
  })
  submit_field("first ok") -- advance past the optional field
  skip_field() -- <Esc> on the required field -> abort
  ok(aborted, "on_cancel fires when <Esc> hits a required field")
  ok(not abort_submitted, "on_submit never fires once the form was aborted")

  -- routed via kit.popup({ type = "form" })
  local popup_values
  kit.popup({
    type = "form",
    fields = { { name = "only", label = "Only", default = "x" } },
    on_submit = function(values)
      popup_values = values
    end,
  })
  submit_field("via-popup")
  eq(popup_values.only, "via-popup", 'kit.popup({ type = "form" }) routes to the form component')

  -- --------------------------------------------------------------- sync (vim.wait bridge)
  -- Headless nvim's `:startinsert` doesn't actually put the fake UI into
  -- Insert mode the way a real terminal would, so typed-text feedkeys are
  -- unreliable here (same reason live_input's own tests above edit the
  -- buffer directly rather than "typing"). Set the float's buffer content
  -- directly, then feed just <CR>/<Esc> — both are mapped in "i"+"n" mode,
  -- so which mode nvim thinks it's in doesn't matter.
  local function submit_current_float(text)
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { text })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  end
  local function cancel_current_float()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end

  do
    -- <CR> submits -> kit.sync returns the value synchronously, no callback needed.
    vim.defer_fn(function()
      submit_current_float("hi")
    end, 10)
    local result, cancelled, timed_out = kit.sync(kit.input, { default = "" }, 2000)
    eq(result, "hi", "kit.sync returns kit.input's submitted value synchronously")
    ok(not cancelled, "kit.sync: not cancelled on submit")
    ok(not timed_out, "kit.sync: not timed out on submit")
  end

  do
    -- <Esc> -> cancelled=true, result=nil.
    vim.defer_fn(function()
      cancel_current_float()
    end, 10)
    local result, cancelled = kit.sync(kit.input, {}, 2000)
    eq(result, nil, "kit.sync: result is nil on cancel")
    ok(cancelled, "kit.sync: cancelled=true on <Esc>")
  end

  do
    -- Nothing resolves it -> times out (short custom timeout so the spec stays fast).
    local result, cancelled, timed_out = kit.sync(kit.input, {}, 30)
    eq(result, nil, "kit.sync: result is nil on timeout")
    ok(not cancelled, "kit.sync: cancelled stays false on timeout")
    ok(timed_out, "kit.sync: timed_out=true when the timeout elapses with no resolution")
    -- The float never got submitted/cancelled — close it so it doesn't leak into later specs.
    pcall(vim.cmd, "stopinsert")
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end

  do
    -- Works with kit.form too — buffer_ctx.nvim's motivating use case (§13a):
    -- a multi-field prompt whose caller wants a plain return value, not a callback.
    -- Both fields' floats open synchronously within this one deferred callback
    -- (the second field's kit.input opens inside the first field's on_submit).
    vim.defer_fn(function()
      submit_current_float("a")
      submit_current_float("b")
    end, 10)
    local values = kit.sync(kit.form, {
      fields = {
        { name = "one", label = "One" },
        { name = "two", label = "Two" },
      },
    }, 2000)
    eq(values.one, "a", "kit.sync + kit.form: first field captured")
    eq(values.two, "b", "kit.sync + kit.form: second field captured")
  end

  -- --------------------------------------------------------------- chooser (native select)
  local chooser = require("lib.nvim.ui.kit.chooser")

  -- single select: submit fires on_select(item, idx) and closes
  local picked_item, picked_idx
  kit.select({
    selection = { "alpha", "beta", "gamma" },
    on_select = function(it, i)
      picked_item, picked_idx = it, i
    end,
  })
  ok(chooser.is_open(), "chooser opened")
  chooser.move(1) -- alpha -> beta
  eq(chooser.current_index(), 2, "move advances selection")
  chooser.submit()
  eq(picked_item, "beta", "single-select returned the highlighted item")
  eq(picked_idx, 2, "single-select returned its index")
  ok(not chooser.is_open(), "chooser closed after submit")

  -- move wraps around
  kit.select({ selection = { "a", "b" }, on_select = function() end })
  chooser.move(-1) -- from line 1 wraps to line 2
  eq(chooser.current_index(), 2, "move(-1) wraps to the last row")
  chooser.close()

  -- multi-select: toggle marks then submit returns (items[], indices[])
  local multi_items, multi_idx
  kit.select({
    selection = { "one", "two", "three" },
    multi = true,
    on_select = function(items, idxs)
      multi_items, multi_idx = items, idxs
    end,
  })
  chooser.toggle() -- mark line 1
  chooser.move(2) -- to line 3
  chooser.toggle() -- mark line 3
  chooser.submit()
  eq(table.concat(multi_items, ","), "one,three", "multi-select returned marked items in order")
  eq(table.concat(multi_idx, ","), "1,3", "multi-select returned marked indices")

  -- theme selection highlight is wired
  ok(vim.fn.hlexists("KitSelection") == 1, "KitSelection group defined for the chooser")

  -- --------------------------------------------------------------- layout (pure)
  local geo = kit.layout.compute(kit.layout.templates.picker.spec)
  ok(geo.slots.prompt ~= nil, "picker layout has a prompt slot")
  ok(geo.slots.results ~= nil, "picker layout has a results slot")
  ok(geo.slots.preview ~= nil, "picker layout has a preview slot")

  -- prompt spans the full outer width; results+preview are narrower halves
  ok(geo.slots.prompt.width >= geo.slots.results.width, "prompt wider than results")
  ok(geo.slots.results.width < geo.slots.preview.width, "results (0.4) narrower than preview (0.6)")

  -- prompt sits above the results/preview row
  ok(geo.slots.prompt.row < geo.slots.results.row, "prompt above results")
  eq(geo.slots.results.row, geo.slots.preview.row, "results and preview share a row")

  -- gap = 0, border = 1 -> preview.col == results.col + results.width + 2
  eq(
    geo.slots.preview.col,
    geo.slots.results.col + geo.slots.results.width + 2,
    "results and preview align edge-to-edge (shared border, no gap)"
  )

  -- --------------------------------------------------------------- layout (mount)
  local group =
    assert(kit.layout.template("picker", { theme = "double" }), "picker template mounts")
  ok(group.slots.prompt:is_valid(), "prompt slot surface valid")
  ok(group.slots.results:is_valid(), "results slot surface valid")
  ok(group.slots.preview:is_valid(), "preview slot surface valid")
  -- closing the group closes every slot
  group.close()
  ok(not group.slots.results:is_valid(), "group.close() closed the results slot")
  ok(not group.slots.preview:is_valid(), "group.close() closed the preview slot")

  -- unknown template returns nil without throwing
  eq(kit.layout.template("nope"), nil, "unknown template returns nil")

  -- --------------------------------------------------------------- picker (interactive)
  local submit_idx, submit_text
  local p = assert(
    kit.picker({
      on_submit = function(i, t)
        submit_idx, submit_text = i, t
      end,
    }),
    "picker opens"
  )
  ok(p.slots.prompt:is_valid(), "picker prompt slot valid")
  ok(p.slots.results:is_valid(), "picker results slot valid")
  ok(p.slots.preview:is_valid(), "picker preview slot valid")

  -- caller fills the results slot (as on_change would), selection resets to top
  p.set_results({ "match-1", "match-2", "match-3" })
  p.move(1) -- to match-2
  p.submit()
  eq(submit_idx, 2, "picker submit reports the highlighted index")
  eq(submit_text, "match-2", "picker submit reports the highlighted line text")
  vim.cmd("stopinsert")

  -- plain mode falls back to a bare template mount
  local plain = assert(kit.picker({ prompt = "plain" }), "plain picker mounts")
  ok(plain.slots.prompt:is_valid(), "plain picker has slots")
  plain.close()
  vim.cmd("stopinsert")

  -- --------------------------------------------------------------- confirm (buttons)
  local confirm = require("lib.nvim.ui.kit.confirm")

  -- default Yes/No -> boolean; focus starts on Yes
  local yn
  local cs = assert(
    kit.confirm({
      question = "Delete 3 files?",
      on_answer = function(a)
        yn = a
      end,
    }),
    "confirm opens"
  )
  ok(cs:is_valid(), "confirm float valid")
  eq(confirm.current_focus(), 1, "focus starts on the first button")
  confirm.confirm() -- Yes
  eq(yn, true, "default confirm: Yes -> true")

  -- move to No, confirm -> false
  kit.confirm({
    question = "Sure?",
    on_answer = function(a)
      yn = a
    end,
  })
  confirm.move(1) -- Yes -> No
  eq(confirm.current_focus(), 2, "move advances focus")
  confirm.confirm()
  eq(yn, false, "default confirm: No -> false")

  -- move wraps around
  kit.confirm({ question = "Wrap?", on_answer = function() end })
  confirm.move(-1) -- from Yes wraps to No
  eq(confirm.current_focus(), 2, "move(-1) wraps to the last button")
  confirm.close()

  -- custom choices -> chosen string
  local choice
  kit.confirm({
    question = "Pick",
    choices = { "Keep", "Discard", "Cancel" },
    on_answer = function(c)
      choice = c
    end,
  })
  confirm.move(1) -- Keep -> Discard
  confirm.confirm()
  eq(choice, "Discard", "custom confirm returns the chosen label")

  -- cancel: default -> false, custom -> nil
  kit.confirm({
    question = "X",
    on_answer = function(a)
      yn = a
    end,
  })
  confirm.cancel()
  eq(yn, false, "cancel on default confirm -> false")

  local custom_cancel = "sentinel"
  kit.confirm({
    question = "Y",
    choices = { "A", "B" },
    on_answer = function(a)
      custom_cancel = a
    end,
  })
  confirm.cancel()
  eq(custom_cancel, nil, "cancel on custom confirm -> nil")

  -- routed via prompt(answer_type = "confirm", layout = "buttons")
  kit.prompt({
    question = "Route?",
    answer_type = "confirm",
    layout = "buttons",
    on_answer = function() end,
  })
  ok(confirm.is_open(), "prompt layout=buttons opens the button-confirm")
  confirm.close()

  -- focused button carries the selection highlight
  ok(vim.fn.hlexists("KitSelection") == 1, "KitSelection group defined for confirm focus")

  -- --------------------------------------------------------------- menu
  local ran
  local ms = assert(
    kit.menu({
      title = "Actions",
      items = {
        {
          label = "Rename",
          action = function()
            ran = "rename"
          end,
        },
        {
          label = "Delete",
          action = function()
            ran = "delete"
          end,
        },
      },
    }),
    "menu opens"
  )
  ok(ms:is_valid(), "menu float valid")
  eq(vim.api.nvim_buf_get_lines(ms.bufnr, 0, 1, false)[1], "Rename", "menu shows the item labels")
  -- pick the second item -> runs its action
  chooser.move(1)
  chooser.submit()
  eq(ran, "delete", "menu runs the picked item's action")

  -- --------------------------------------------------------------- progress (passthrough)
  local ph = kit.progress({ text = "working", style = "notify" })
  ok(
    type(ph) == "table" and type(ph.finish) == "function",
    "kit.progress returns a lib.nvim.progress handle"
  )
  ph:finish() -- stays silent (never became visible)

  -- --------------------------------------------------------------- preview playground
  local P = require("lib.nvim.ui.kit.preview")
  local cfg_buf, prev_buf = kit.preview()
  ok(
    vim.api.nvim_buf_is_valid(cfg_buf) and vim.api.nvim_buf_is_valid(prev_buf),
    "preview opens a config + preview buffer"
  )
  local rendered = table.concat(vim.api.nvim_buf_get_lines(prev_buf, 0, -1, false), "\n")
  ok(rendered:find("border=rounded", 1, true), "preview renders the default (rounded) theme")

  -- editing the config re-renders live
  vim.api.nvim_buf_set_lines(cfg_buf, 0, -1, false, { 'return "double"' })
  P.render(cfg_buf, prev_buf)
  local rendered2 = table.concat(vim.api.nvim_buf_get_lines(prev_buf, 0, -1, false), "\n")
  ok(rendered2:find("border=double", 1, true), "editing the config restyles the preview")

  -- a broken config shows an error instead of throwing
  vim.api.nvim_buf_set_lines(cfg_buf, 0, -1, false, { "return { border =" })
  P.render(cfg_buf, prev_buf)
  local rendered3 = table.concat(vim.api.nvim_buf_get_lines(prev_buf, 0, -1, false), "\n")
  ok(rendered3:find("config error", 1, true), "a broken config shows an error, no throw")
  pcall(vim.cmd, "tabclose")

  -- popup dispatch: unknown types return nil without throwing
  eq(kit.popup({ type = "does-not-exist" }), nil, "unknown type returns nil (no throw)")
end
