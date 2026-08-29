---@module 'lib.nvim.deps.install'
--- Turn a parsed tool spec into an install plan, and — only on an explicit,
--- confirmed call — put the composed command in front of the user in a
--- terminal buffer.
---
--- `plan()` is pure: it probes PATH and the host's package manager, and
--- returns what *would* happen. Nothing about it touches the system.
---
--- `run()` is the one function in `lib.nvim.deps` that opens anything. Its
--- contract, which the rest of the module's safety argument rests on:
---
---   1. It is never called from `require` or a `setup()` — only from an
---      explicit user action (`:Lib deps install <plugin>`).
---   2. It asks for confirmation, showing the exact command(s) first.
---   3. It opens a terminal running the user's shell and *types* the command
---      into it **without a trailing newline**. The user presses Enter.
---      Nothing is executed by this library, so a `sudo` password prompt is
---      answered at a real terminal the user opened, not by Neovim.
---
--- Point 3 is why this doesn't use `jobstart`/`vim.system`: a backgrounded
--- privileged install with its prompt swallowed is precisely the failure mode
--- worth designing out.

local core = require("lib.nvim.core")
local pm = require("lib.nvim.deps.pm")

local M = {}

---Compute what installing `tools` would involve on this host: which are
---already present, which are missing, which of the missing ones this host's
---package manager has a package name for, and the command(s) that would
---install them.
---
---`opts.manager` overrides detection (mainly so this is testable without
---depending on what the test machine happens to have installed).
---@param tools Lib.Deps.Tool[]
---@param opts? { manager?: Lib.Deps.Manager }
---@return Lib.Deps.Plan
function M.plan(tools, opts)
  opts = opts or {}
  local manager = opts.manager or pm.detect()

  local present, missing, installable, unsupported, packages = {}, {}, {}, {}, {}
  -- Several tools routinely ship in ONE package — pdftotext and pdftoppm are
  -- both poppler-utils. Without this, a plan missing both would compose
  -- `apt install poppler-utils poppler-utils`. Each tool still appears in
  -- `installable` on its own (the report lists tools, not packages); only
  -- the package list is de-duplicated.
  local seen_pkg = {}

  for _, tool in ipairs(tools) do
    if core.has_exec(tool.bin) then
      present[#present + 1] = tool
    else
      missing[#missing + 1] = tool
      local pkg = manager and tool.pkg[manager.id] or nil
      if pkg then
        installable[#installable + 1] = tool
        if not seen_pkg[pkg] then
          seen_pkg[pkg] = true
          packages[#packages + 1] = pkg
        end
      else
        unsupported[#unsupported + 1] = tool
      end
    end
  end

  return {
    manager = manager,
    present = present,
    missing = missing,
    installable = installable,
    unsupported = unsupported,
    packages = packages,
    commands = manager and pm.commands(manager, packages) or {},
  }
end

---@internal
---The lines shown in the confirmation prompt: one per command, plus a note
---about any missing tool this host's manager has no package name for (those
---are silently left out of the command otherwise, which would look like the
---plan simply forgot them).
---@param plan Lib.Deps.Plan
---@return string
local function confirm_text(plan)
  local lines = { "Run the following to install the missing tools?", "" }
  for _, argv in ipairs(plan.commands) do
    lines[#lines + 1] = "  " .. pm.render(argv)
  end
  if #plan.unsupported > 0 then
    lines[#lines + 1] = ""
    local names = {}
    for _, tool in ipairs(plan.unsupported) do
      names[#names + 1] = tool.bin
    end
    lines[#lines + 1] = ("Not covered (no %s package declared): %s"):format(
      plan.manager and plan.manager.id or "?",
      table.concat(names, ", ")
    )
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "The command is typed into a terminal for you to submit — nothing runs on its own."
  return table.concat(lines, "\n")
end

---@internal
---Open a terminal split running the user's shell, and type `text` into it
---without submitting. Returns the buffer, or nil if the terminal could not
---be started.
---@param text string
---@return integer|nil bufnr
local function open_terminal_with(text)
  vim.cmd("belowright split")
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_win_set_buf(win, bufnr)

  local ok, chan = pcall(vim.fn.jobstart, { vim.o.shell }, { term = true })
  if not ok or chan <= 0 then
    vim.api.nvim_win_close(win, true)
    return nil
  end

  -- No trailing newline, on purpose: the user submits it (see module header).
  vim.fn.chansend(chan, text)
  vim.cmd("startinsert")
  return bufnr
end

---Offer to install everything in `plan` that this host's package manager can.
---
---Always asks first (showing the exact command), then opens a terminal with
---the command typed but not submitted. `opts.confirm = false` skips only the
---prompt — it does **not** submit the command, which stays the user's
---keystroke either way; it exists for callers that already asked in their own
---UI, and for tests.
---@param plan Lib.Deps.Plan
---@param opts? { confirm?: boolean }
---@return boolean started true when a terminal was opened
function M.run(plan, opts)
  opts = opts or {}
  local notify = require("lib.nvim.notify").create("[lib.nvim.deps]")

  if not plan.manager then
    notify.warn("No supported package manager found on this host — install the tools manually.")
    return false
  end
  if #plan.commands == 0 then
    if #plan.missing == 0 then
      notify.info("All declared tools are already installed.")
    else
      notify.warn(
        ("Nothing to install: no %s package name is declared for the missing tool(s)."):format(
          plan.manager.id
        )
      )
    end
    return false
  end

  if opts.confirm ~= false then
    local choice = vim.fn.confirm(confirm_text(plan), "&Open terminal\n&Cancel", 2, "Question")
    if choice ~= 1 then
      return false
    end
  end

  local parts = {}
  for _, argv in ipairs(plan.commands) do
    parts[#parts + 1] = pm.render(argv)
  end
  -- `&&` rather than `;`: a failed first install shouldn't be followed by the
  -- rest running against a half-set-up system.
  local text = table.concat(parts, " && ")

  if not open_terminal_with(text) then
    notify.error("Could not open a terminal; run manually:  " .. text)
    return false
  end
  return true
end

---@type Lib.Deps.Install
return M
