-- TESTS/progress_float_style_spec.lua — lib.nvim.progress.styles.float:
-- regression coverage for the col/width ceiling mismatch also fixed in the
-- sibling kit style (see progress_kit_style_spec.lua). `col` is computed
-- from `width` to keep the float right-anchored, so it has to agree with
-- whatever width make_scratch actually opens the window with.

return function(H)
  local float_style = require("lib.nvim.progress.styles.float")

  do
    local orig_columns = vim.o.columns
    vim.o.columns = 30 -- narrow enough that the 40-cell width must clamp

    local state = float_style.start(
      { title = "[p] ", text = "", current = nil, total = nil },
      {},
      function() end
    )
    H.ok(state.winid ~= nil, "float style: start() opens a window on a narrow editor")

    local max_w = math.max(1, vim.o.columns - 4)
    local actual_width = vim.api.nvim_win_get_width(state.winid)
    H.eq(
      actual_width,
      max_w,
      "float style: the requested 40-cell width clamps to the editor's own ceiling"
    )

    local cfg = vim.api.nvim_win_get_config(state.winid)
    H.eq(
      cfg.col,
      math.max(0, vim.o.columns - actual_width - 2),
      "float style: col is computed from the SAME (clamped) width the window actually opened with"
    )

    vim.api.nvim_win_close(state.winid, true)
    vim.o.columns = orig_columns
  end

  -- The <Esc> cancel prompt names the operation by its title; a blank or missing title
  -- falls back to "This operation" instead of asking " is still running" (a nil title never gets
  -- this far: render_line concatenates it when the style starts).
  do
    local function esc_callback(bufnr)
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if map.lhs == "<Esc>" then
          return map.callback
        end
      end
    end
    local function prompt_for(title)
      local seen
      local dialog = require("lib.nvim.ui.dialog")
      local orig_yesno = dialog.yesno
      dialog.yesno = function(msg, _, cb)
        seen = msg
        cb(false)
      end
      local state = float_style.start(
        { title = title, text = "", current = nil, total = nil },
        {},
        function() end
      )
      local ok, err = pcall(esc_callback(state.bufnr))
      dialog.yesno = orig_yesno
      pcall(vim.api.nvim_win_close, state.winid, true)
      H.ok(ok, "float style: the <Esc> handler runs (" .. tostring(err) .. ")")
      return seen
    end
    H.eq(
      prompt_for("[p] building  "),
      "[p] building is still running. Abort it?",
      "float style: a title is named, trailing blanks dropped"
    )
    H.eq(
      prompt_for("   "),
      "This operation is still running. Abort it?",
      "float style: a blank title falls back to 'This operation'"
    )
    H.eq(
      prompt_for(""),
      "This operation is still running. Abort it?",
      "float style: an empty title falls back to 'This operation'"
    )

    -- the answer decides: yes aborts exactly once (the label and the colour come with the question),
    -- no leaves the operation alone
    local dialog = require("lib.nvim.ui.dialog")
    local orig_yesno = dialog.yesno
    local function answer_with(yes)
      local cancels, asked = 0, nil
      dialog.yesno = function(_, label, cb, opts)
        asked = { label = label, kind = opts and opts.kind }
        cb(yes)
      end
      local state = float_style.start(
        { title = "[p] ", text = "", current = nil, total = nil },
        {},
        function()
          cancels = cancels + 1
        end
      )
      local ok = pcall(esc_callback(state.bufnr))
      dialog.yesno = orig_yesno
      pcall(vim.api.nvim_win_close, state.winid, true)
      H.ok(ok, "float style: the <Esc> handler runs")
      return cancels, asked
    end
    local cancels, asked = answer_with(true)
    H.eq(cancels, 1, "float style: yes asks to cancel exactly once")
    H.eq(asked.label, "abort", "float style: the yes answer reads 'Yes, abort'")
    H.eq(asked.kind, "danger", "float style: ...in the danger colour")
    H.eq((answer_with(false)), 0, "float style: no cancels nothing")
  end

  -- An answer that comes after the operation has ended has nothing left to stop: the question is no
  -- longer modal, so the operation can finish while it is open.
  do
    local progress = require("lib.nvim.progress")
    local h = progress.create({ style = "echo", delay_ms = 0 })
    local stopped = 0
    h:on_cancel(function()
      stopped = stopped + 1
    end)
    h:finish()
    h:request_cancel()
    H.eq(stopped, 0, "progress: a cancel requested after finish() calls no on_cancel callback")
    H.eq(
      h.cancelled,
      false,
      "progress: ...and does not turn a finished operation into a cancelled one"
    )

    local h2 = progress.create({ style = "echo", delay_ms = 0 })
    h2:on_cancel(function()
      stopped = stopped + 1
    end)
    h2:request_cancel()
    h2:request_cancel()
    H.eq(stopped, 1, "progress: a running operation is cancelled once, however often it is asked")
  end
end
