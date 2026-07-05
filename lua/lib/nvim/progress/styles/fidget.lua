---@module 'lib.nvim.progress.styles.fidget'
---Optional renderer delegating to fidget.nvim's LSP-style progress API.
---
---`resolve_style.lua` only picks this module once `fidget` is confirmed
---loadable, but every call here is still `pcall`-guarded: fidget's progress
---API is not a stability-guaranteed surface, and a broken/incompatible
---version must degrade to a silent no-op rather than error out of the caller.

require("lib.nvim.progress.@types")

---@param spec Lib.Progress.Spec
---@return integer|nil
local function percentage(spec)
  if type(spec.current) == "number" and type(spec.total) == "number" and spec.total > 0 then
    return math.floor((spec.current / spec.total) * 100)
  end
  return nil
end

---@param spec Lib.Progress.Spec
---@return any|nil fidget handle
local function start(spec)
  local ok, handle = pcall(function()
    return require("fidget.progress").handle.create({
      title = spec.title,
      message = spec.text,
      percentage = percentage(spec),
      lsp_client = { name = spec.title },
    })
  end)
  if not ok then
    return nil
  end
  return handle
end

---@param state any|nil
---@param spec Lib.Progress.Spec
---@return any|nil
local function update(state, spec)
  if not state then
    return nil
  end
  pcall(function()
    state.message = spec.text
    state.percentage = percentage(spec)
  end)
  return state
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function finish(state, spec)
  if not state then
    return
  end
  pcall(function()
    state.message = spec.text or "done"
    state:finish()
  end)
end

---@param state any|nil
---@param spec Lib.Progress.Spec
local function cancel(state, spec)
  if not state then
    return
  end
  pcall(function()
    state.message = spec.text or "cancelled"
    state:cancel()
  end)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
