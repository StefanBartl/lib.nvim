---@module 'lib.nvim.ui.kit.input'
--- Input component: a single-line themed prompt (a `vim.ui.input` replacement).
--- Opens focused in insert mode; `<CR>` submits the line, `<Esc>` cancels.
---
--- `opts.secret = true` masks the displayed content character-by-character
--- via `conceal` (each char replaced with `opts.mask`, default `"*"`) — a
--- `vim.fn.inputsecret` replacement. The mask is re-derived from the actual
--- buffer content on every edit (paste, backspace, mid-line insert all just
--- work, no keystroke-diffing needed) rather than tracked in a shadow
--- variable, so submission still reads the real text straight off the
--- buffer. This only hides the on-screen rendering, matching a terminal
--- password prompt's own echo-suppression rather than the visible-input
--- default; buffer-local `undolevels = -1` additionally keeps the plaintext
--- out of the undo tree. It was never written to disk in the first place —
--- every kit scratch buffer already has `swapfile = false` (make_scratch),
--- and the buffer is wiped when the float closes (`bufhidden = "wipe"`).
---
--- `opts.completion = "file"` (or any other `getcompletion()` type: "dir",
--- "shellcmd", "buffer", ...) is a `completion = "file"` cmdline-input
--- replacement: `<Tab>` completes the last whitespace-delimited fragment
--- before the cursor via `vim.fn.getcompletion()` and opens Neovim's native
--- completion popup (`vim.fn.complete()`) — real ins-completion, so `<C-n>`/
--- `<C-p>` cycle it same as anywhere else. While the popup is open, `<Tab>`/
--- `<S-Tab>` advance/retreat the selection instead of re-triggering, and
--- `<CR>` accepts the highlighted candidate instead of submitting the whole
--- prompt (a second `<CR>` submits, exactly like confirming a shell
--- completion then pressing enter again). A fragment that holds a backtick is
--- never completed: `getcompletion()` would run the span between backticks
--- through the shell, and a pasted line is not to be trusted with that.
---
--- `opts.on_back` makes the prompt one step of a larger flow (`kit.form` with
--- `back = true`): `<BS>` on an EMPTY line, `<S-Tab>` and `<C-p>` close the
--- prompt and call `on_back(line)` -- the line as it stood, so the caller can
--- keep a half-typed answer -- instead of `on_submit`/`on_cancel`. A press of
--- those keys while a completion popup is open still belongs to the popup,
--- and without `on_back` none of the three is touched. A `<BS>` that follows
--- another one of the same prompt by less than 300 ms is a held key repeating,
--- not a new press, and never goes back (see `BS_RUN_MS`): holding it down
--- empties the field and stops there instead of deleting the answers before it.
---
--- `opts.buttons` adds a clickable row of `[ Label ]` buttons under the field
--- (`{ { id = "back"|"skip"|"submit", label = "..." }, ... }`; `submit` is
--- `<CR>`, `skip` is `<Esc>`, `back` is the `on_back` keys, and a `back` button
--- is dropped when there is no `on_back`). `<Down>` (and `<Tab>`, unless
--- `completion` owns it) moves the focus from the field onto the row, starting
--- on the `submit` button; there `h`/`l`/arrows/`<Tab>`/`<S-Tab>` move it,
--- `<CR>` presses the focused button, `<Esc>` still cancels and `<Up>`/`k`/`i`/
--- `a` return to the field. A left click on a button focuses *and* presses it
--- in one action, exactly as in `kit.confirm`. The row's layout, focus
--- highlight and hit-test are `lib.nvim.ui.kit.buttons`, shared with `kit.confirm`.
--- The row is line 2 of the buffer, so it is kept honest: it is laid out again,
--- shifted, when a long answer scrolls the window sideways (every line goes
--- with it), and a paste or `<C-j>` that splits the field into several lines
--- is joined back into one with a space, the row put back under it.

local surface = require("lib.nvim.ui.kit.surface")
local buttons = require("lib.nvim.ui.kit.buttons")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local api = vim.api
local autocmd = require("lib.nvim.bindings.autocmd")
local fn = vim.fn
local uv = vim.uv or vim.loop

local M = {}

--- A `<BS>` on an empty field that follows another `<BS>` of the same field
--- within this many milliseconds is a held key repeating, not a new press (a
--- terminal cannot tell the two apart): it does not go back. A repeat runs at
--- ~30 Hz; a deliberate second press after emptying a field takes longer.
local BS_RUN_MS = 300

--- Extmark namespace of the focus highlight on the button row.
local BTN_NS = api.nvim_create_namespace("lib_kit_input_buttons")

--- How many windows to be typed into have ever been opened: this prompt, and
--- whatever else calls `M.mark_opened` (a sheet, a picker, a live_input, a compare).
--- `finish` compares it before and after the callbacks it runs to tell whether one
--- of them opened the next prompt of a chain.
---@type integer
local opened = 0

--- A component that has just opened a window to type into, and asks for Insert mode
--- with `:startinsert`, says so here. A prompt that closes while a callback opens
--- one of these must not stop Insert mode: `:startinsert` is ignored while the
--- closing prompt's own Insert mode is still on, and the new window would stand in
--- Normal mode, where the first thing typed is a command.
function M.mark_opened()
  opened = opened + 1
end

--- The number `M.mark_opened` has counted so far: read it before something that may
--- open such a window and compare after.
---@return integer
function M.opened_count()
  return opened
end

--- The ids `opts.buttons` understands.
---@type table<string, true>
local BUTTON_IDS = { back = true, skip = true, submit = true }

---@internal
--- Hand `keys` back to Neovim un-remapped and AHEAD of whatever is still
--- queued, for a mapping that only wants to intercept some presses of a key
--- (`<BS>` on an empty line, `<S-Tab>` with no popup open). Appending them
--- instead would reorder a pasted or fast-typed run.
---@param keys string
local function pass_through(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "ni", false)
end

---@internal
--- Split `opts.buttons` into parallel id/label lists. Unknown ids, labels that
--- are not strings and a `back` button without an `on_back` to call are
--- dropped: a button that can do nothing is worse than no button.
---@param opts table
---@return string[] ids
---@return string[] labels
local function resolve_buttons(opts)
  local ids, labels = {}, {}
  if type(opts.buttons) ~= "table" then
    return ids, labels
  end
  for _, b in ipairs(opts.buttons) do
    if
      type(b) == "table"
      and BUTTON_IDS[b.id]
      and type(b.label) == "string"
      and (b.id ~= "back" or type(opts.on_back) == "function")
    then
      ids[#ids + 1] = b.id
      labels[#labels + 1] = b.label
    end
  end
  return ids, labels
end

---@internal
---Conceal every character of buffer row `row` (0-based) with `mask`, on top of
---whatever `ns` already holds. Shared with `lib.nvim.ui.kit.sheet`, whose secret fields
---are rows of one buffer.
---@param bufnr integer
---@param ns integer
---@param row integer
---@param mask string
local function conceal_line(bufnr, ns, row, mask)
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local nchars = vim.fn.strchars(line)
  for i = 0, nchars - 1 do
    local s = vim.fn.byteidx(line, i)
    local e = vim.fn.byteidx(line, i + 1)
    pcall(api.nvim_buf_set_extmark, bufnr, ns, row, s, { end_col = e, conceal = mask })
  end
end

---@internal
---Re-conceal every character of the input's single line with `mask`.
---@param bufnr integer
---@param ns integer
---@param mask string
local function apply_mask(bufnr, ns, mask)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  conceal_line(bufnr, ns, 0, mask)
end

---@internal
---Complete the fragment before the cursor via `vim.fn.getcompletion()` and
---open the native completion popup at the right start column. The line is the
---one the cursor is on: the prompt's own single line here, a field's row for
---`lib.nvim.ui.kit.sheet`, which shares this.
---@param bufnr integer
---@param winid integer
---@param completion string  # a `getcompletion()` type, e.g. "file", "dir"
local function trigger_completion(bufnr, winid, completion)
  local cursor = api.nvim_win_get_cursor(winid)
  local line = api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
  local col = cursor[2]
  local prefix = line:sub(1, col)
  -- Scanned from the end: `match("%S*$")` retries the rest of a long word from
  -- every start byte, which is quadratic for one pasted line without spaces.
  local frag = prefix:reverse():match("^%S*"):reverse()
  -- getcompletion() hands a backtick span in its argument to 'shell' (the
  -- "file", "dir", "shellcmd" and "file_in_path" types), and the fragment is text
  -- from wherever the user pasted it: never pass one on (SEC-34). A backtick
  -- belongs to no sensible file-name fragment anyway.
  if frag:find("`", 1, true) then
    return
  end
  local ok, matches = pcall(fn.getcompletion, frag, completion)
  if not ok or not matches or #matches == 0 then
    return
  end
  -- getcompletion() returns full replacement strings (e.g. "/etc/passwd" for
  -- fragment "/etc/pas"), so complete()'s start column is where `frag` began.
  pcall(fn.complete, col - #frag + 1, matches)
end

--- Open a single-line input.
---@param opts table  # { title|prompt, default, theme, width, relative, on_submit, on_cancel, expand_env, secret, mask, completion, on_back, buttons }
--- `expand_env = true` runs the submitted line through `lib.nvim.cross.fs.expand_path`
--- (`~`, `$VAR`, `${VAR}`, `%VAR%`) before it reaches `on_submit` — opt-in, for
--- callers that know they're prompting for a path.
--- `on_back` / `buttons`: see the module doc — opt-in, nothing changes without them.
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}

  local title = opts.title or opts.prompt
  -- A float's title is drawn within its content width; a title longer than
  -- the default 40 cols gets silently truncated by Neovim (with a leading
  -- ellipsis) instead of wrapping, so widen the box to fit it.
  local title_width = title and vim.fn.strdisplaywidth(title) or 0

  local btn_ids, btn_labels = resolve_buttons(opts)
  local has_buttons = #btn_ids > 0
  local can_back = type(opts.on_back) == "function"

  local width = opts.width or math.max(40, title_width)
  if has_buttons and width >= 1 then
    -- A row clipped by the border has buttons the mouse cannot hit. (A
    -- fraction of the editor, `width < 1`, is left to make_scratch.)
    width = math.max(width, buttons.row_width(btn_labels) + 2)
  end

  local surf = surface.open({
    lines = has_buttons and { opts.default or "", "" } or { opts.default or "" },
    theme = opts.theme,
    title = title,
    width = width,
    height = has_buttons and 2 or 1,
    relative = opts.relative or "cursor",
    enter = true,
    modifiable = true,
    wo = opts.secret and { conceallevel = 2, concealcursor = "nvic" } or nil,
    bo = opts.secret and { undolevels = -1 } or nil,
  })
  if not surf then
    return nil
  end

  M.mark_opened()
  local bufnr = surf.bufnr
  local done = false

  ---@return string
  local function get_line()
    -- The buffer can be gone while the window lives on (a forced swap of the buffer
    -- shown in it): `finish` must still run, through `surf:on_close`, or no callback fires.
    if not api.nvim_buf_is_valid(bufnr) then
      return ""
    end
    return api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
  end

  -- The button row, when there is one: line 2 of the buffer. `btn_focus` is the
  -- 1-based button the focus is on, nil while it is in the field (line 1).
  local btn_focus = nil
  local ranges = {}
  local row_text = "" -- what line 2 holds right now
  local row_scroll = 0 -- the window's `leftcol` that `row_text` was laid out for
  local default_btn = 1 -- where <Down>/<Tab> land: the button <CR> would press anyway
  for i, id in ipairs(btn_ids) do
    if id == "submit" then
      default_btn = i
    end
  end

  if opts.secret then
    local ns = api.nvim_create_namespace("lib_kit_input_secret_" .. bufnr)
    local mask = opts.mask or "*"
    apply_mask(bufnr, ns, mask)
    autocmd.create({ "TextChangedI", "TextChanged" }, function()
      apply_mask(bufnr, ns, mask)
    end, {
      group = autocmd.group("lib_kit_input", true),
      buffer = bufnr,
      desc = "lib.nvim.ui.kit.input: re-mask secret input",
    })
  end

  --- `action`: `true` submits (<CR>), `false` cancels (<Esc>), `"back"` steps
  --- back (`on_back`).
  ---@param action boolean|"back"
  local function finish(action)
    if done then
      return
    end
    done = true
    local line = get_line()
    local opened_before = opened
    surf:close()
    local ok, err = pcall(function()
      if action == "back" then
        if opts.on_back then
          opts.on_back(line)
        end
      elseif action then
        if opts.expand_env then
          line = expand_path(line)
        end
        if opts.on_submit then
          opts.on_submit(line)
        end
      elseif opts.on_cancel then
        opts.on_cancel()
      end
    end)
    -- Leave insert mode now that the prompt is gone (a lingering mode state
    -- otherwise) -- unless a callback opened the next prompt of a chain (a
    -- form's next field, or the one before it; a sheet, a picker, a live_input:
    -- anything that counts itself with `mark_opened`). That prompt is waiting for
    -- Insert mode, and `:startinsert` is ignored while this one's is still on:
    -- stopping here as well would strand it in Normal mode, where the first
    -- thing typed is a command.
    if opened == opened_before then
      pcall(function()
        vim.cmd("stopinsert")
      end)
    end
    if not ok then
      error(err, 0)
    end
  end

  --- Press button `i`: each one is one of the keys that already do it.
  ---@param i integer
  local function press(i)
    local id = btn_ids[i]
    if id == "back" then
      finish("back")
    elseif id == "skip" then
      finish(false)
    else
      finish(true)
    end
  end

  local function paint()
    buttons.paint(bufnr, BTN_NS, ranges, btn_focus)
  end

  --- Put the cursor on the focused button. Leaving insert mode (which is what
  --- a `<Down>` from the field is about to do) steps the cursor one column
  --- left, so aim one column right of the box's start to land on it.
  local function park_cursor()
    local r = ranges[btn_focus]
    if r then
      local from_insert = api.nvim_get_mode().mode:sub(1, 1) == "i"
      pcall(api.nvim_win_set_cursor, surf.winid, { 2, r.start_col + (from_insert and 1 or 0) })
    end
  end

  --- Run `write` with the buffer writable and no undo recorded for it: the row
  --- is not the user's to edit (the buffer is locked while the buttons have the
  --- focus), and `u` in the field must never reach it.
  ---@param write fun()
  local function write_silently(write)
    local modifiable = vim.bo[bufnr].modifiable
    local undolevels = vim.bo[bufnr].undolevels
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].undolevels = -1
    local ok, err = pcall(write)
    vim.bo[bufnr].undolevels = undolevels
    vim.bo[bufnr].modifiable = modifiable
    if not ok then
      error(err, 0)
    end
  end

  --- Lay the button row out, again when the window has scrolled sideways. A
  --- long answer scrolls the whole window, every line with it, so a row laid out
  --- for column 0 would end up off screen: it is padded by the same amount
  --- instead, which keeps it where it was drawn. The click ranges are byte
  --- columns of the line -- what `getmousepos()` reports, scrolled or not -- so
  --- they move with the padding.
  ---@param force? boolean  # lay out even when the scroll is the one the row was drawn for
  local function layout_row(force)
    local scroll = api.nvim_win_call(surf.winid, function()
      return fn.winsaveview().leftcol
    end)
    if scroll == row_scroll and not force then
      return
    end
    row_scroll = scroll
    -- Laid out after the window exists, so the row is centered in the width the
    -- float actually got (make_scratch clamps it to the editor).
    local text, laid = buttons.layout(btn_labels, api.nvim_win_get_width(surf.winid), 1)
    if scroll > 0 then
      text = string.rep(" ", scroll) .. text
      for _, r in ipairs(laid) do
        r.start_col = r.start_col + scroll
        r.end_col = r.end_col + scroll
      end
    end
    ranges = laid
    row_text = text
    write_silently(function()
      api.nvim_buf_set_lines(bufnr, 1, 2, false, { text })
    end)
    paint()
    if btn_focus then
      park_cursor()
    end
  end

  --- The field is one line and the row sits right under it. A paste with a
  --- newline in it (a clipboard that ends in one is the usual case) or a `<C-j>`
  --- splits the field and pushes the row out of the two lines the window shows:
  --- join what was typed back into one line and put the row under it again.
  local function keep_layout()
    if btn_focus then
      return -- the buffer is locked: nothing can have been typed
    end
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #lines == 2 and lines[2] == row_text then
      return
    end
    if lines[#lines] == row_text then
      lines[#lines] = nil
    end
    local parts = {}
    for _, l in ipairs(lines) do
      if l ~= "" then
        parts[#parts + 1] = l
      end
    end
    local field = table.concat(parts, " ")
    write_silently(function()
      api.nvim_buf_set_lines(bufnr, 0, -1, false, { field, row_text })
    end)
    pcall(api.nvim_win_set_cursor, surf.winid, { 1, #field })
  end

  if has_buttons then
    layout_row(true)
  end

  local focus_field
  local function move_focus(delta)
    if not btn_focus then
      return
    end
    btn_focus = buttons.wrap(btn_focus, delta, #btn_ids)
    paint()
    park_cursor()
  end

  -- Normal-mode keys that only mean something while the focus is on the row.
  -- Bound on entering it and removed on leaving it, so the field keeps every
  -- native key (`h`, `i`, ...) the rest of the time. Keys the field also
  -- binds (<Tab>, <S-Tab>, <Down>, <CR>, <Esc>) are static and check
  -- `btn_focus` themselves instead.
  local button_keys = {
    {
      { "l", "<Right>" },
      function()
        move_focus(1)
      end,
    },
    {
      { "h", "<Left>" },
      function()
        move_focus(-1)
      end,
    },
    {
      { "<Up>", "k", "i", "a", "I", "A" },
      function()
        focus_field()
      end,
    },
  }

  ---@param bind boolean
  local function set_button_keys(bind)
    for _, entry in ipairs(button_keys) do
      for _, lhs in ipairs(entry[1]) do
        if bind then
          vim.keymap.set("n", lhs, entry[2], { buffer = bufnr, nowait = true })
        else
          pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
        end
      end
    end
  end

  --- Move the focus from the field onto the button row (on `submit` unless
  --- told otherwise). The buffer is locked while it is there, so no stray
  --- edit key can touch the labels.
  ---@param index? integer
  local function focus_buttons(index)
    if not has_buttons or btn_focus then
      return
    end
    btn_focus = index or default_btn
    pcall(function()
      vim.cmd("stopinsert")
    end)
    vim.bo[bufnr].modifiable = false
    set_button_keys(true)
    paint()
    park_cursor()
  end

  --- Move the focus from the button row back into the field, in insert mode
  --- at byte column `col` (the end of the line when nil or past it). With the
  --- focus already in the field it only places the cursor.
  ---@param col? integer
  function focus_field(col)
    local line = get_line()
    if not btn_focus then
      if col then
        pcall(api.nvim_win_set_cursor, surf.winid, { 1, math.min(col, #line) })
      end
      return
    end
    btn_focus = nil
    set_button_keys(false)
    paint()
    vim.bo[bufnr].modifiable = true
    if col and col < #line then
      pcall(api.nvim_win_set_cursor, surf.winid, { 1, col })
      vim.cmd("startinsert")
    else
      pcall(api.nvim_win_set_cursor, surf.winid, { 1, #line })
      vim.cmd("startinsert!")
    end
  end

  --- A left click: on a button it focuses *and* presses it (as in
  --- `kit.confirm`); elsewhere in this float it puts the cursor on the field's
  --- text; anywhere else it is the click it would have been without this
  --- mapping. Hit-tested from `getmousepos()` rather than from where the
  --- cursor ended up, which is not something Neovim promises for a mapped
  --- `<LeftMouse>`.
  local function on_click()
    local i, pos = buttons.hit(ranges, surf.winid)
    if i then
      btn_focus = i
      paint()
      press(i)
    elseif not pos then
      pass_through("<LeftMouse>")
    elseif pos.line == 1 then
      focus_field(pos.column - 1)
    end
  end

  if opts.completion then
    -- <Tab>/<S-Tab> drive the native pum once it's open (advance/retreat);
    -- otherwise <Tab> triggers completion and <S-Tab> is a no-op literal tab.
    -- <Tab> is NOT an <expr> mapping: `complete()` raises E565 under the textlock
    -- one holds, and `trigger_completion`'s pcall swallowed it, so <Tab> did nothing.
    vim.keymap.set("i", "<Tab>", function()
      if fn.pumvisible() == 1 then
        pass_through("<C-n>")
      else
        trigger_completion(bufnr, surf.winid, opts.completion)
      end
    end, { buffer = bufnr, nowait = true })
    vim.keymap.set("i", "<S-Tab>", function()
      if fn.pumvisible() == 1 then
        return api.nvim_replace_termcodes("<C-p>", true, false, true)
      end
      return ""
    end, { buffer = bufnr, nowait = true, expr = true })
  end

  local key_opts = { buffer = bufnr, nowait = true }

  if can_back then
    -- Going back must not eat text: <BS> is only "back" once there is nothing
    -- left for it to delete, and a popup that is open keeps <C-p>. A key held
    -- down repeats faster than anyone presses it again: the repeat that finds
    -- the field emptied by the run before it is swallowed (and counts as part
    -- of the run), or one held <BS> would walk back through every earlier
    -- field and delete each answer in turn.
    local last_bs ---@type number|nil  # ms clock of the previous <BS> of this field
    vim.keymap.set({ "i", "n" }, "<BS>", function()
      if btn_focus then
        return
      end
      local now = uv.hrtime() / 1e6
      local in_run = last_bs ~= nil and now - last_bs < BS_RUN_MS
      last_bs = now
      if get_line() ~= "" then
        pass_through("<BS>")
      elseif not in_run then
        finish("back")
      end
    end, key_opts)
    vim.keymap.set({ "i", "n" }, "<C-p>", function()
      if btn_focus then
        return
      end
      if fn.pumvisible() == 1 then
        pass_through("<C-p>")
      else
        finish("back")
      end
    end, key_opts)
  end

  if can_back or has_buttons then
    -- Replaces the completion block's <S-Tab> above: same popup behaviour,
    -- plus what it does with the popup closed.
    vim.keymap.set({ "i", "n" }, "<S-Tab>", function()
      if btn_focus then
        move_focus(-1)
      elseif fn.pumvisible() == 1 then
        pass_through("<C-p>")
      elseif can_back then
        finish("back")
      end
    end, key_opts)
  end

  if has_buttons then
    if not opts.completion then
      vim.keymap.set("i", "<Tab>", function()
        focus_buttons()
      end, key_opts)
    end
    vim.keymap.set("n", "<Tab>", function()
      if btn_focus then
        move_focus(1)
      else
        focus_buttons()
      end
    end, key_opts)
    vim.keymap.set({ "i", "n" }, "<Down>", function()
      if btn_focus then
        return
      end
      if fn.pumvisible() == 1 then
        pass_through("<Down>")
      else
        focus_buttons()
      end
    end, key_opts)
    vim.keymap.set({ "i", "n" }, "<LeftMouse>", on_click, key_opts)

    -- The two lines are two places for the cursor, not one text: keep it on
    -- the field (or on the focused button) whatever tried to move it (`j`,
    -- `<C-o>G`, ...), so an edit can never land on the labels. The same hook
    -- keeps the row under the field when the text around it changed shape
    -- (a paste) and in view when the window scrolled (a long answer).
    autocmd.create(
      { "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "TextChangedP" },
      function()
        if not surf:is_valid() then
          return
        end
        keep_layout()
        layout_row()
        local row = api.nvim_win_get_cursor(surf.winid)[1]
        if btn_focus then
          if row ~= 2 then
            park_cursor()
          end
        elseif row ~= 1 then
          pcall(api.nvim_win_set_cursor, surf.winid, { 1, #get_line() })
        end
      end,
      {
        buffer = bufnr,
        record = false,
        desc = "lib.nvim.ui.kit.input: keep the field one line, the row under it and in view",
      }
    )
  end

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    -- Accept the highlighted completion candidate instead of submitting the
    -- whole prompt; a second <CR> (pum now closed) submits as usual. This
    -- must NOT be an <expr> mapping: finish() closes the window, and Neovim
    -- silently blocks window/buffer changes while an <expr> mapping is
    -- still being evaluated (textlock) -- feeding <C-y> for real instead of
    -- returning it keeps that whole call chain outside of textlock.
    if opts.completion and fn.pumvisible() == 1 then
      api.nvim_feedkeys(api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
      return
    end
    -- With the focus on the button row, <CR> presses the focused button.
    if btn_focus then
      press(btn_focus)
      return
    end
    finish(true)
  end, { buffer = bufnr, nowait = true })
  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    finish(false)
  end, { buffer = bufnr, nowait = true })
  surf:on_close(function()
    finish(false)
  end)

  -- Place the cursor at end of the default text and enter insert mode.
  if surf:is_valid() then
    api.nvim_win_set_cursor(surf.winid, { 1, #(opts.default or "") })
    vim.cmd("startinsert!")
  end

  return surf
end

--- The two helpers `lib.nvim.ui.kit.sheet` shares (its fields are rows of one buffer, so
--- it cannot reuse the single-line prompt itself).
M.conceal_line = conceal_line
M.complete = trigger_completion

return M
