---@module 'lib.nvim.progress.styles.notify'
---Default progress renderer: renders through `vim.notify`.
---
---When a notify backend that returns a record with an `id` field is active
---(e.g. nvim-notify), updates replace the previous notification in place via
---its `replace` option. Otherwise every update is a plain sequential
---`vim.notify` call — still functional, just not visually merged.

require("lib.nvim.progress.@types")

---@param spec Lib.Progress.Spec
---@return string
local function render_text(spec)
  local parts = {}
  if spec.text and spec.text ~= "" then
    parts[#parts + 1] = spec.text
  end
  if type(spec.current) == "number" then
    if type(spec.total) == "number" and spec.total > 0 then
      parts[#parts + 1] = string.format("(%d/%d)", spec.current, spec.total)
    else
      parts[#parts + 1] = string.format("(%d)", spec.current)
    end
  end
  return spec.title .. table.concat(parts, " ")
end

---Notify, tolerating backends that don't support `replace` or return nothing.
---@param text string
---@param level integer
---@param replace_id any|nil
---@return any replace_id usable on the next call, or nil
local function do_notify(text, level, replace_id)
  local notify_opts = replace_id and { replace = replace_id } or {}
  local ok, rec = pcall(vim.notify, text, level, notify_opts)
  if ok and type(rec) == "table" and rec.id then
    return rec.id
  end
  return nil
end

---@param spec Lib.Progress.Spec
---@param opts Lib.Progress.Opts
---@return { id: any|nil, level: integer }
local function start(spec, opts)
  local level = opts.level or vim.log.levels.INFO
  return { id = do_notify(render_text(spec), level, nil), level = level }
end

---@param state { id: any|nil, level: integer }
---@param spec Lib.Progress.Spec
---@return { id: any|nil, level: integer }
local function update(state, spec)
  state.id = do_notify(render_text(spec), state.level, state.id) or state.id
  return state
end

---@param state { id: any|nil, level: integer }
---@param spec Lib.Progress.Spec
local function finish(state, spec)
  do_notify(render_text(spec), vim.log.levels.INFO, state.id)
end

---@param state { id: any|nil, level: integer }
---@param spec Lib.Progress.Spec
local function cancel(state, spec)
  do_notify(render_text(spec), vim.log.levels.WARN, state.id)
end

---@type Lib.Progress.StyleImpl
return { start = start, update = update, finish = finish, cancel = cancel }
