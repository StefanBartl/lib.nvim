---@module 'lib.nvim.progress.resolve_style'
---Resolve a `Lib.Progress.Style` request to a concrete, loadable implementation.
---Mirrors the ripgrep/vimgrep auto-detection used elsewhere in these plugins:
---prefer the richer UI when available, otherwise fall back to something that
---always works without extra dependencies.

require("lib.nvim.progress.@types")

---@param want Lib.Progress.Style|nil
---@return Lib.Progress.StyleImpl
local function resolve_style(want)
  if want == "statusline" then
    return (require("lib.nvim.progress.styles.statusline"))
  end

  if want == "fidget" then
    if pcall(require, "fidget") then
      return (require("lib.nvim.progress.styles.fidget"))
    end
    return (require("lib.nvim.progress.styles.notify"))
  end

  if want == "notify" then
    return (require("lib.nvim.progress.styles.notify"))
  end

  if want == "float" then
    return (require("lib.nvim.progress.styles.float"))
  end

  -- "auto" (default) or unrecognized: prefer fidget, else notify.
  -- "float" is opt-in only: it is more intrusive (an interactive window) and
  -- must be requested explicitly, never picked automatically.
  if pcall(require, "fidget") then
    return (require("lib.nvim.progress.styles.fidget"))
  end
  return (require("lib.nvim.progress.styles.notify"))
end

return resolve_style
