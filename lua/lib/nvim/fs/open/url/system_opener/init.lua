---@module 'lib.nvim.fs.open.url.system_opener'
---@deprecated Use `lib.nvim.cross.open_default` instead.
--- Thin compatibility shim over `lib.nvim.cross.open_default`, kept so the
--- existing `.open(url)` / `.open(url, { on_exit = … })` call sites keep
--- working while they migrate.
---
--- The two modules solved the same problem twice. `open_default` is the more
--- complete one — it runs `expand_path` (`~`, `$VAR`, `%VAR%`) and, on WSL,
--- translates a Linux path to its Windows equivalent via `wslpath` before
--- handing it to `explorer.exe`; this module did neither, so a `~/x.pdf` or a
--- `/home/...` path under WSL opened wrong or not at all. No caller was using
--- the extra `cfg` surface (`prefer_ui_open`, `enable_windows_opener`,
--- `open_cmd_*`) or the `vim.ui.open`-first dispatch, so the shim drops them:
--- only `cfg.on_exit` is forwarded. `is_like` / `is_ike` stay as-is.

require("lib.nvim.fs.open.url.system_opener.@types")

local M = {}

--- In-place "open URL" via the system opener.
---
--- Deprecated alias for `require("lib.nvim.cross.open_default")(url,
--- { on_exit = cfg.on_exit })`. The return value reports whether an opener
--- was *dispatched*, not whether it succeeded — pass `cfg.on_exit` to observe
--- the actual exit code.
---@deprecated Use `require("lib.nvim.cross.open_default")(url)` instead.
---@param url string
---@param cfg? Lib.Fs.Open.Url.SystemOpener.Cfg  Only `on_exit` is honored; the rest are ignored.
---@return boolean opened
function M.open(url, cfg)
  cfg = cfg or {}
  local ok = require("lib.nvim.cross.open_default")(url, { on_exit = cfg.on_exit })
  return ok
end

--- Quick predicate: looks like a web/URI target.
---@param s string
---@return boolean
function M.is_like(s)
  if s:match("^https?://") or s:match("^file://") then
    return true
  end
  if s:match("^www%.") then
    return true
  end
  if s:match("^[A-Za-z0-9%-_]+%.[A-Za-z]+") then
    return true
  end
  return false
end

--- Deprecated misspelling of `is_like`, kept as an alias so existing call
--- sites keep working. Prefer `M.is_like`.
---@deprecated use `M.is_like` instead
M.is_ike = M.is_like

return M
