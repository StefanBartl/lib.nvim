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
  local vw = assert(kit.viewer({ title = "Info", lines = { "line 1", "line 2" } }), "viewer opens")
  ok(vw:is_valid(), "viewer float is valid")
  eq(#vim.api.nvim_buf_get_lines(vw.bufnr, 0, -1, false), 2, "viewer shows every line")
  eq(
    vim.api.nvim_get_option_value("modifiable", { buf = vw.bufnr }),
    false,
    "viewer buffer is read-only"
  )
  vw:close()

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

  -- input(secret = true): masked entry (vim.fn.inputsecret replacement)
  local sec_submitted
  local sec = assert(
    kit.input({
      prompt = "Password",
      secret = true,
      on_submit = function(v)
        sec_submitted = v
      end,
    }),
    "secret input opens"
  )
  eq(
    vim.api.nvim_get_option_value("conceallevel", { win = sec.winid }),
    2,
    "secret input sets conceallevel=2"
  )
  ok(
    vim.api.nvim_get_option_value("concealcursor", { win = sec.winid }):find("i") ~= nil,
    "secret input's concealcursor covers insert mode"
  )
  eq(
    vim.api.nvim_get_option_value("undolevels", { buf = sec.bufnr }),
    -1,
    "secret input disables undo on its buffer"
  )
  vim.api.nvim_buf_set_lines(sec.bufnr, 0, 1, false, { "hunter2" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = sec.bufnr })
  eq(
    vim.api.nvim_buf_get_lines(sec.bufnr, 0, 1, false)[1],
    "hunter2",
    "secret input's real buffer content is untouched -- only the rendering is masked"
  )
  local sec_ns = vim.api.nvim_get_namespaces()["lib_kit_input_secret_" .. sec.bufnr]
  local sec_marks = vim.api.nvim_buf_get_extmarks(sec.bufnr, sec_ns, 0, -1, { details = true })
  eq(#sec_marks, 7, "one conceal extmark per character of the typed secret")
  for _, m in ipairs(sec_marks) do
    eq(m[4].conceal, "*", "each character is concealed behind the default mask")
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  eq(sec_submitted, "hunter2", "on_submit still receives the real (unmasked) text")

  -- custom mask character
  local mask_surf = assert(
    kit.input({ secret = true, mask = "•", on_submit = function() end }),
    "secret input with custom mask opens"
  )
  vim.api.nvim_buf_set_lines(mask_surf.bufnr, 0, 1, false, { "ab" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = mask_surf.bufnr })
  local mask_ns = vim.api.nvim_get_namespaces()["lib_kit_input_secret_" .. mask_surf.bufnr]
  local mask_marks =
    vim.api.nvim_buf_get_extmarks(mask_surf.bufnr, mask_ns, 0, -1, { details = true })
  eq(mask_marks[1][4].conceal, "•", "opts.mask overrides the default '*' placeholder")
  mask_surf:close()

  -- plain (non-secret) input never sets conceallevel
  local plain_sec = assert(kit.input({ prompt = "x" }), "plain input opens")
  eq(
    vim.api.nvim_get_option_value("conceallevel", { win = plain_sec.winid }),
    0,
    "a plain input leaves conceallevel untouched"
  )
  vim.cmd("stopinsert")
  plain_sec:close()

  -- input(completion = "file"): file-path completion (vim.fn.inputsecret's
  -- cousin, `completion = "file"` on the old vim.fn.input). `vim.fn.complete()`
  -- itself only works in real Insert mode, which this headless -l runner
  -- never actually enters (confirmed: even after startinsert!/feedkeys("A"),
  -- `vim.api.nvim_get_mode().mode` stays "n" -- there's no live redraw loop
  -- to carry the mode transition through), so the pum-interaction half of
  -- this feature isn't exercisable here. What IS tested: the buffer-local
  -- <Tab>/<S-Tab> mappings only exist when opts.completion is set, and the
  -- <CR>/<Esc> submit/cancel paths are unaffected by having it set.
  do
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for _, name in ipairs({ "file_alpha.txt", "file_beta.txt" }) do
      local f = io.open(dir .. "/" .. name, "w")
      f:write("")
      f:close()
    end

    -- getcompletion() expands its argument as a Vim path pattern, so the raw
    -- tempname() is unusable as a prefix on Windows for two reasons:
    --   * it comes back in 8.3 short form ("C:\Users\STEFAN~1\..."), and the
    --     "~" is taken as a home-directory reference mid-pattern;
    --   * "\" is the pattern escape character, so backslash separators eat the
    --     component that follows them.
    -- fs_realpath() gives the long name, and forward slashes are accepted as
    -- separators on both platforms -- on Linux/macOS both steps are no-ops.
    local comp_dir = (vim.uv or vim.loop).fs_realpath(dir) or dir
    comp_dir = comp_dir:gsub("\\", "/")

    -- getcompletion() itself (the piece trigger_completion drives) works
    -- headless -- no Insert mode needed for this call.
    local matches = vim.fn.getcompletion(comp_dir .. "/fi", "file")
    eq(#matches, 2, "getcompletion(file) finds both real files under the prefix")

    local comp =
      assert(kit.input({ prompt = "Path", completion = "file" }), "completion input opens")
    local tab_map = vim.fn.maparg("<Tab>", "i", false, true)
    eq(tab_map.buffer, 1, "opts.completion registers a buffer-local <Tab> mapping")
    local stab_map = vim.fn.maparg("<S-Tab>", "i", false, true)
    eq(stab_map.buffer, 1, "opts.completion registers a buffer-local <S-Tab> mapping")

    -- <CR>/<Esc> still submit/cancel normally (pum never opens here, so this
    -- exercises the same finish() path as plain kit.input).
    local comp_submitted
    kit.input({
      prompt = "Path",
      completion = "file",
      default = "seed",
      on_submit = function(v)
        comp_submitted = v
      end,
    })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    eq(comp_submitted, "seed", "<CR> still submits normally when completion is set (pum closed)")

    local plain_no_completion = assert(kit.input({ prompt = "x" }), "no-completion input opens")
    local plain_tab_map = vim.fn.maparg("<Tab>", "i", false, true)
    eq(plain_tab_map.buffer, 0, "a plain input registers no buffer-local <Tab> mapping")
    vim.cmd("stopinsert")
    plain_no_completion:close()
    comp:close()
  end

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

  -- initial_index: lands the cursor on a specific item at open time (e.g.
  -- restoring position across a close+reopen refresh), instead of item 1.
  kit.select({
    selection = { "a", "b", "c" },
    initial_index = 3,
    on_select = function() end,
  })
  eq(chooser.current_index(), 3, "initial_index lands the cursor on the requested item")
  chooser.close()

  -- out-of-range initial_index falls back to item 1 rather than erroring.
  kit.select({
    selection = { "a", "b" },
    initial_index = 99,
    on_select = function() end,
  })
  eq(chooser.current_index(), 1, "out-of-range initial_index falls back to item 1")
  chooser.close()

  -- kit.chooser is exposed directly, and current_item() reads the
  -- highlighted item's original value without submitting/closing -- for a
  -- consumer building extra actions on top of the picker (e.g.
  -- recommender.nvim's yank-without-closing).
  ok(kit.chooser ~= nil, "kit.chooser is exposed publicly")
  kit.select({ selection = { "x", "y" }, on_select = function() end })
  eq(kit.chooser.current_item(), "x", "current_item() reads the highlighted item")
  kit.chooser.move(1)
  eq(kit.chooser.current_item(), "y", "current_item() follows navigation")
  kit.chooser.close()
  eq(kit.chooser.current_item(), nil, "current_item() is nil once closed")

  -- --------------------------------------------------------------- chooser: rich items (§13b)
  -- Multi-line entries with per-span highlights (recommender.nvim's
  -- motivating use case: a 3-line suggestion with per-column highlight
  -- groups) mixed with a plain string, exercising navigation-by-item,
  -- click-anywhere-in-an-item resolution, and highlight placement.
  do
    local rich = {
      lines = { "-> my_chain (3 hits)", "  local alias = my_chain", "" },
      highlights = {
        { line = 0, col_start = 0, col_end = 2, hl_group = "Special" },
        { line = 1, hl_group = "Statement" }, -- col_end omitted -> whole line
      },
    }
    local plain = "plain item"

    local picked, picked_at
    local surf = kit.select({
      items = { rich, plain },
      on_select = function(it, i)
        picked, picked_at = it, i
      end,
    })
    ok(surf ~= nil, "chooser opens with a rich item mixed in")
    eq(
      vim.api.nvim_buf_line_count(surf.bufnr),
      4,
      "buffer has rich item's 3 lines + plain item's 1 line"
    )
    eq(chooser.current_index(), 1, "opens with logical item 1 (the rich item) current")

    -- Move the raw cursor to the rich item's 2nd line (not its anchor row) --
    -- current_index() must still resolve to item 1, the way a mouse click
    -- landing anywhere in a multi-line item should.
    vim.api.nvim_win_set_cursor(surf.winid, { 2, 0 })
    eq(chooser.current_index(), 1, "cursor on a non-anchor row still resolves to its item")

    chooser.move(1) -- item 1 (rich, 3 lines) -> item 2 (plain, 1 line)
    eq(chooser.current_index(), 2, "move(1) advances by logical item, not raw line")
    eq(vim.api.nvim_win_get_cursor(surf.winid)[1], 4, "cursor lands on item 2's buffer row (4)")

    chooser.move(-1) -- back to item 1
    eq(vim.api.nvim_win_get_cursor(surf.winid)[1], 1, "move(-1) lands back on item 1's anchor row")

    chooser.submit()
    eq(picked, rich, "submit() returns the original rich item table, not a stringified copy")
    eq(picked_at, 1, "submit() returns the logical item index")
  end

  do
    -- Highlight extmarks land on the right row/columns.
    local rich = {
      lines = { "abcdef" },
      highlights = { { line = 0, col_start = 1, col_end = 3, hl_group = "Special" } },
    }
    local surf = kit.select({ items = { rich }, on_select = function() end })
    local marks = vim.api.nvim_buf_get_extmarks(surf.bufnr, -1, 0, -1, { details = true })
    local found = false
    for _, m in ipairs(marks) do
      local row, col, details = m[2], m[3], m[4]
      if row == 0 and col == 1 and details.end_col == 3 and details.hl_group == "Special" then
        found = true
      end
    end
    ok(found, "rich item's highlight extmark placed at the declared row/col span")
    chooser.close()
  end

  do
    -- Multi-select marks a rich item's whole row span, not just its anchor row.
    local rich = { lines = { "line one", "line two" } }
    local chosen
    kit.select({
      items = { rich, "b" },
      multi = true,
      on_select = function(items)
        chosen = items
      end,
    })
    chooser.toggle() -- mark the rich item (currently item 1)
    chooser.submit()
    eq(#chosen, 1, "multi-select: one item marked")
    eq(chosen[1], rich, "multi-select: the marked rich item is returned whole")
  end

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

  -- --------------------------------------------------------------- compare
  -- `state`/`slots`/`move`/`mark`/`confirm` mirror `kit.picker`'s handle
  -- shape specifically so the SEARCH -> MARKED -> COMPARE flow is drivable
  -- headlessly, same as `picker (interactive)` above.
  local cmp_items = { "apple", "banana", "cherry", "date" }
  local cmp_renders = {}
  local cmp_clears = 0
  local cmp_close_calls, cmp_closed_a, cmp_closed_b = 0, nil, nil
  local cmp_on_compare_calls, cmp_on_compare_a, cmp_on_compare_b = 0, nil, nil
  -- Shared log across on_compare/render so "before either render" is a
  -- provable order, not just an isolated fact about on_compare's own call
  -- count — a caller like images.nvim relies on seeing it BEFORE render, not
  -- merely on it firing at some point.
  local cmp_order = {}

  local ch = assert(
    kit.compare({
      items = cmp_items,
      render = function(item, surf)
        table.insert(cmp_renders, item)
        table.insert(cmp_order, "render:" .. item)
        surf:set_lines({ "preview:" .. item })
      end,
      clear = function()
        cmp_clears = cmp_clears + 1
      end,
      on_close = function(a, b)
        cmp_close_calls = cmp_close_calls + 1
        cmp_closed_a, cmp_closed_b = a, b
      end,
      on_compare = function(a, b)
        cmp_on_compare_calls = cmp_on_compare_calls + 1
        cmp_on_compare_a, cmp_on_compare_b = a, b
        table.insert(cmp_order, "on_compare")
      end,
    }),
    "compare opens"
  )

  eq(ch.state(), "search", "compare starts in SEARCH")
  local search_slots = ch.slots()
  ok(search_slots.prompt:is_valid(), "search: prompt slot valid")
  ok(search_slots.results:is_valid(), "search: results slot valid")
  ok(search_slots.preview:is_valid(), "search: preview slot valid")
  eq(
    vim.api.nvim_buf_get_lines(search_slots.results.bufnr, 0, -1, false)[1],
    "apple",
    "results list shows format_item output (default: tostring)"
  )
  eq(
    vim.api.nvim_buf_get_lines(search_slots.preview.bufnr, 0, -1, false)[1],
    "preview:apple",
    "live preview renders the highlighted item"
  )
  eq(cmp_clears, 1, "clear() runs once for the initial mount")

  ch.move(1) -- apple -> banana
  eq(
    vim.api.nvim_buf_get_lines(ch.slots().preview.bufnr, 0, -1, false)[1],
    "preview:banana",
    "move() re-renders the live preview"
  )

  -- mark "banana" -> MARKED
  ch.mark()
  eq(ch.state(), "marked", "mark() enters MARKED")
  eq(cmp_clears, 2, "clear() runs again for the MARKED transition")
  local marked_slots = ch.slots()
  ok(marked_slots.marked:is_valid(), "marked: frozen slot valid")
  eq(
    vim.api.nvim_buf_get_lines(marked_slots.marked.bufnr, 0, -1, false)[1],
    "preview:banana",
    "frozen slot shows the marked item"
  )
  ok(marked_slots.results:is_valid(), "marked: results slot still there (still searchable)")
  ok(marked_slots.preview:is_valid(), "marked: live preview slot still there")
  eq(
    vim.api.nvim_buf_get_lines(marked_slots.preview.bufnr, 0, -1, false)[1],
    "preview:banana",
    "live preview keeps showing the selection as of the moment it was marked"
  )

  -- move to "cherry" and confirm the second pick -> COMPARE
  ch.move(1) -- banana -> cherry
  eq(
    vim.api.nvim_buf_get_lines(ch.slots().preview.bufnr, 0, -1, false)[1],
    "preview:cherry",
    "the live preview still follows the selection while MARKED"
  )
  ch.confirm()
  eq(ch.state(), "compare", "confirm() enters COMPARE")
  eq(cmp_clears, 3, "clear() runs again for the COMPARE transition")
  local cmp_slots = ch.slots()
  ok(cmp_slots.a:is_valid(), "compare: pane A valid")
  ok(cmp_slots.b:is_valid(), "compare: pane B valid")
  eq(cmp_slots.results, nil, "compare: results slot is gone")
  eq(cmp_slots.prompt, nil, "compare: prompt slot is gone")
  eq(
    vim.api.nvim_buf_get_lines(cmp_slots.a.bufnr, 0, -1, false)[1],
    "preview:banana",
    "pane A renders the marked item"
  )
  eq(
    vim.api.nvim_buf_get_lines(cmp_slots.b.bufnr, 0, -1, false)[1],
    "preview:cherry",
    "pane B renders the confirmed second item"
  )
  eq(cmp_on_compare_calls, 1, "on_compare fires exactly once")
  eq(cmp_on_compare_a, "banana", "on_compare gets the marked item as a")
  eq(cmp_on_compare_b, "cherry", "…and the confirmed second item as b")
  -- The last three log entries, not the whole log: SEARCH-state moves also
  -- rendered "apple"/"banana"/"cherry" for the live preview, so only the
  -- tail proves the COMPARE-state ordering, not just that the strings occur.
  local tail = { cmp_order[#cmp_order - 2], cmp_order[#cmp_order - 1], cmp_order[#cmp_order] }
  eq(
    table.concat(tail, ","),
    "on_compare,render:banana,render:cherry",
    "on_compare fires before either COMPARE-state render() call, with both panes still in a,b order"
  )

  ch.close()
  eq(cmp_clears, 4, "clear() runs once more on close")
  eq(cmp_close_calls, 1, "on_close fires exactly once")
  eq(cmp_closed_a, "banana", "on_close reports the marked item")
  eq(
    cmp_closed_b,
    "cherry",
    "…and the confirmed second item, even closed programmatically from COMPARE"
  )
  ok(not cmp_slots.a:is_valid(), "compare panes close")
  vim.cmd("stopinsert")

  -- default substring filter (no opts.query given) narrows the results list
  local ch2 = assert(
    kit.compare({
      items = { "red", "green", "blue" },
      render = function(item, surf)
        surf:set_lines({ item })
      end,
    }),
    "compare (filter) opens"
  )
  local prompt_buf = ch2.slots().prompt.bufnr
  vim.api.nvim_buf_set_lines(prompt_buf, 0, 1, false, { "bl" })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = prompt_buf })
  vim.wait(150)
  local results_lines = vim.api.nvim_buf_get_lines(ch2.slots().results.bufnr, 0, -1, false)
  eq(#results_lines, 1, "query narrows the results to matches")
  eq(results_lines[1], "blue", "…the one item containing the query")
  ch2.close()
  vim.cmd("stopinsert")

  -- an empty item list opens no UI and reports (nil, nil) synchronously
  local empty_called, empty_a, empty_b = false, nil, nil
  local empty_handle = kit.compare({
    items = {},
    render = function() end,
    on_close = function(a, b)
      empty_called, empty_a, empty_b = true, a, b
    end,
  })
  eq(empty_handle, nil, "compare with no items returns nil")
  ok(empty_called, "on_close still fires for an empty item list")
  eq(empty_a, nil, "…with a nil first pick")
  eq(empty_b, nil, "…and a nil second pick")

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
