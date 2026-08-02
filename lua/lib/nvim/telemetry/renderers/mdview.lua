---@module 'lib.nvim.telemetry.renderers.mdview'
--- Bridges a rendered report to a browser tab via mdview.nvim's own
--- `:MDView standalone` — which already does exactly the right thing for
--- this, so the bridge is thin. See the "Browser report" section of
--- lua/lib/nvim/telemetry/README.md for the reasoning.
---
--- `:MDView standalone` hands a FILE PATH to the relay binary's own --watch
--- mode and steps out of the chain entirely: the relay watches the file on
--- disk and broadcasts changes to the browser itself. Combined with
--- `report_file = true` (telemetry rewrites that same path on every flush),
--- the browser tab becomes a live dashboard with no new machinery on either
--- side — neither plugin gains a poller, a socket, or a timer it did not
--- already have.
---
--- Soft dependency, never hard: `pcall(require, "mdview")`, every call here
--- pcall-guarded, degrade to `false, err` rather than throwing. Same
--- discipline `lib.nvim.progress.styles.fidget` documents for fidget.nvim —
--- an external plugin's surface is not stability-guaranteed.

local report_file = require("lib.nvim.telemetry.report_file")

local M = {}

---@return boolean
function M.available()
  return pcall(require, "mdview")
end

---Write `lines` to `path` and hand it to `:MDView standalone`.
---@param lines string[]
---@param path string
---@return boolean ok, string|nil err
function M.open(lines, path)
  if not M.available() then
    return false, "mdview.nvim is not installed/loadable"
  end

  local ok_write, write_err = report_file.write(path, lines)
  if not ok_write then
    return false, write_err
  end

  local ok_cmd, cmd_err = pcall(vim.cmd, ("MDView standalone %s"):format(vim.fn.fnameescape(path)))
  if not ok_cmd then
    return false, "MDView standalone failed: " .. tostring(cmd_err)
  end

  return true, nil
end

return M
