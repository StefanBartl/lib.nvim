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
--- completion then pressing enter again).

local surface = require("lib.nvim.ui.kit.surface")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local api = vim.api
local autocmd = require("lib.nvim.bindings.autocmd")
local fn = vim.fn

local M = {}

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
  local line = api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
  local nchars = vim.fn.strchars(line)
  for i = 0, nchars - 1 do
    local s = vim.fn.byteidx(line, i)
    local e = vim.fn.byteidx(line, i + 1)
    pcall(api.nvim_buf_set_extmark, bufnr, ns, 0, s, { end_col = e, conceal = mask })
  end
end

---@internal
---Complete the fragment before the cursor via `vim.fn.getcompletion()` and
---open the native completion popup at the right start column.
---@param bufnr integer
---@param winid integer
---@param completion string  # a `getcompletion()` type, e.g. "file", "dir"
local function trigger_completion(bufnr, winid, completion)
  local line = api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
  local col = api.nvim_win_get_cursor(winid)[2]
  local prefix = line:sub(1, col)
  local frag = prefix:match("%S*$") or ""
  local ok, matches = pcall(fn.getcompletion, frag, completion)
  if not ok or not matches or #matches == 0 then
    return
  end
  -- getcompletion() returns full replacement strings (e.g. "/etc/passwd" for
  -- fragment "/etc/pas"), so complete()'s start column is where `frag` began.
  pcall(fn.complete, col - #frag + 1, matches)
end

--- Open a single-line input.
---@param opts table  # { title|prompt, default, theme, width, relative, on_submit, on_cancel, expand_env, secret, mask, completion }
--- `expand_env = true` runs the submitted line through `lib.nvim.cross.fs.expand_path`
--- (`~`, `$VAR`, `${VAR}`, `%VAR%`) before it reaches `on_submit` — opt-in, for
--- callers that know they're prompting for a path.
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}

  local title = opts.title or opts.prompt
  -- A float's title is drawn within its content width; a title longer than
  -- the default 40 cols gets silently truncated by Neovim (with a leading
  -- ellipsis) instead of wrapping, so widen the box to fit it.
  local title_width = title and vim.fn.strdisplaywidth(title) or 0

  local surf = surface.open({
    lines = { opts.default or "" },
    theme = opts.theme,
    title = title,
    width = opts.width or math.max(40, title_width),
    height = 1,
    relative = opts.relative or "cursor",
    enter = true,
    modifiable = true,
    wo = opts.secret and { conceallevel = 2, concealcursor = "nvic" } or nil,
    bo = opts.secret and { undolevels = -1 } or nil,
  })
  if not surf then
    return nil
  end

  local bufnr = surf.bufnr
  local done = false

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

  local function finish(submit)
    if done then
      return
    end
    done = true
    local line = api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
    -- Leave insert mode before closing to avoid a lingering mode state.
    pcall(vim.cmd, "stopinsert")
    surf:close()
    if submit then
      if opts.expand_env then
        line = expand_path(line)
      end
      if opts.on_submit then
        opts.on_submit(line)
      end
    elseif opts.on_cancel then
      opts.on_cancel()
    end
  end

  if opts.completion then
    -- <Tab>/<S-Tab> drive the native pum once it's open (advance/retreat);
    -- otherwise <Tab> triggers completion and <S-Tab> is a no-op literal tab.
    vim.keymap.set("i", "<Tab>", function()
      if fn.pumvisible() == 1 then
        return api.nvim_replace_termcodes("<C-n>", true, false, true)
      end
      trigger_completion(bufnr, surf.winid, opts.completion)
      return ""
    end, { buffer = bufnr, nowait = true, expr = true })
    vim.keymap.set("i", "<S-Tab>", function()
      if fn.pumvisible() == 1 then
        return api.nvim_replace_termcodes("<C-p>", true, false, true)
      end
      return ""
    end, { buffer = bufnr, nowait = true, expr = true })
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

return M
