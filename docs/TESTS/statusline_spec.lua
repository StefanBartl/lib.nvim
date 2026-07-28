-- docs/TESTS/statusline_spec.lua — lib.nvim.ui.statusline: mode resolution,
-- both drawing strategies, escaping, and detach/restore.

local statusline = require("lib.nvim.ui.statusline")

---Read a window's local &statusline.
---@param win integer
---@return string
local function stl(win)
  return vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" })
end

---Floating windows currently open in the tabpage.
---@return integer[]
local function floats()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      out[#out + 1] = win
    end
  end
  return out
end

return function(H)
  local original_laststatus = vim.o.laststatus

  -- ── Mode resolution ────────────────────────────────────────────────────────
  do
    vim.o.laststatus = 2
    H.eq(statusline.is_global(), false, "laststatus 2 has per-window statuslines")
    H.eq(statusline.resolve_mode("auto"), "statusline", "auto resolves to statusline")

    vim.o.laststatus = 3
    H.eq(statusline.is_global(), true, "laststatus 3 is global")
    H.eq(statusline.resolve_mode("auto"), "float", "auto falls back to float")
    H.eq(statusline.resolve_mode(nil), "float", "nil behaves like auto")

    -- An explicit mode is never overridden by laststatus.
    H.eq(statusline.resolve_mode("statusline"), "statusline", "explicit statusline wins")
    vim.o.laststatus = 2
    H.eq(statusline.resolve_mode("float"), "float", "explicit float wins")
  end

  -- ── statusline strategy ────────────────────────────────────────────────────
  do
    vim.o.laststatus = 2
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_option_value("statusline", "PREVIOUS", { win = win, scope = "local" })

    local badge, err = statusline.attach(win)
    H.ok(badge, "attach succeeded: " .. tostring(err))
    H.eq(badge.mode(), "statusline", "auto picked the statusline strategy")

    badge.set("LOCK", "DiagnosticWarn")
    H.eq(badge.text(), "LOCK", "text is reported back")
    H.eq(stl(win), "%#DiagnosticWarn#LOCK%*", "badge rendered with its highlight")

    badge.set("LOCK", nil)
    H.eq(stl(win), "%#DiagnosticWarn#LOCK%*", "omitted hl keeps the previous one")

    -- Percent signs are data, not statusline items.
    badge.set("50%", "Comment")
    H.eq(stl(win), "%#Comment#50%%%*", "percent signs are escaped")

    badge.set("R", "Comment")
    local saved = stl(win)
    badge.clear()
    H.eq(stl(win), "PREVIOUS", "clear falls back to the previous statusline")
    H.ok(saved:find("R", 1, true), "sanity: badge had been rendered")

    badge.set("AGAIN", "Comment")
    badge.detach()
    H.eq(stl(win), "PREVIOUS", "detach restores the previous statusline")

    -- Detached segments are inert, not errors.
    badge.set("IGNORED", "Comment")
    H.eq(stl(win), "PREVIOUS", "a detached badge no longer draws")

    vim.api.nvim_set_option_value("statusline", "", { win = win, scope = "local" })
  end

  -- ── Alignment ──────────────────────────────────────────────────────────────
  do
    local win = vim.api.nvim_get_current_win()
    local right = statusline.attach(win, { mode = "statusline", align = "right" })
    right.set("R", "Comment")
    H.eq(stl(win), "%=%#Comment#R%*", "right alignment emits a leading %=")
    right.detach()

    local center = statusline.attach(win, { mode = "statusline", align = "center" })
    center.set("C", "Comment")
    H.eq(stl(win), "%=%#Comment#C%*%=", "center alignment brackets with %=")
    center.detach()
  end

  -- ── float strategy ─────────────────────────────────────────────────────────
  do
    local win = vim.api.nvim_get_current_win()
    local before = #floats()

    local badge = statusline.attach(win, { mode = "float" })
    H.eq(badge.mode(), "float", "explicit float strategy")
    H.eq(#floats(), before, "no float opened before the first set")

    badge.set("PROJECT", "DiagnosticInfo")
    local open = floats()
    H.eq(#open, before + 1, "set opens exactly one float")

    local buf = vim.api.nvim_win_get_buf(open[#open])
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.eq(#lines, 1, "badge is one line")
    H.ok(lines[1]:match("^PROJECT"), "badge text is left-aligned plain text")
    H.eq(vim.bo[buf].modifiable, false, "badge buffer is not modifiable")

    -- The float sits on the target window's last row.
    local pos = vim.api.nvim_win_get_position(win)
    local config = vim.api.nvim_win_get_config(open[#open])
    H.eq(config.row, pos[1] + vim.api.nvim_win_get_height(win) - 1, "float sits on the last row")
    H.eq(config.col, pos[2], "float starts at the window's left edge")
    H.eq(config.focusable, false, "float is not focusable")

    badge.clear()
    H.eq(#floats(), before, "clear closes the float")

    badge.set("BACK", "DiagnosticInfo")
    H.eq(#floats(), before + 1, "set reopens it")
    badge.detach()
    H.eq(#floats(), before, "detach closes the float")
  end

  -- ── float strategy: top anchor ─────────────────────────────────────────────
  do
    local win = vim.api.nvim_get_current_win()
    local before = #floats()

    local top = statusline.attach(win, { mode = "float", anchor = "top" })
    top.set("CRUMBS", "Comment")
    local open = floats()
    H.eq(#open, before + 1, "anchor=top opens exactly one float")

    local pos = vim.api.nvim_win_get_position(win)
    local config = vim.api.nvim_win_get_config(open[#open])
    H.eq(config.row, pos[1], "anchor=top sits on the first row")

    top.detach()
    H.eq(#floats(), before, "detach closes the top-anchored float")

    -- Default is unchanged: omitting anchor still means the last row.
    local bottom = statusline.attach(win, { mode = "float" })
    bottom.set("STATUS", "Comment")
    local bottom_config = vim.api.nvim_win_get_config(floats()[#floats()])
    H.eq(
      bottom_config.row,
      pos[1] + vim.api.nvim_win_get_height(win) - 1,
      "omitted anchor still defaults to the last row"
    )
    bottom.detach()
  end

  -- ── Invalid window ─────────────────────────────────────────────────────────
  do
    local seg, err = statusline.attach(999999)
    H.eq(seg, nil, "attaching to a dead window fails")
    H.ok(err and err:match("invalid window"), "invalid window is reported")
  end

  vim.o.laststatus = original_laststatus
end
