---@module 'lib.nvim.harvest.sink'
--- Where rendered text ends up: the clipboard, a file, a scratch buffer, or
--- an interactive picker.
---
--- Each sink is a plain function — there is no sink "registry" to register
--- into and no shared state. They live together because every collect-and-show
--- feature needs the same three or four endings, and each one has a real
--- portability wrinkle worth solving once (clipboard provider fallbacks,
--- byte-exact file writes, scratch buffers that don't pollute the buffer list).
---
---```lua
--- local sink = require("lib.nvim.harvest.sink")
--- sink.clipboard(text)
--- sink.file(text, "/tmp/out.md")
--- sink.scratch(text, { title = "Links", filetype = "markdown" })
--- sink.select(items, { prompt = "Links", format = tostring }, function(item) ... end)
---```

require("lib.nvim.harvest.@types")

local M = {}

--- Copy `text` to the system clipboard.
---@param text string
---@return boolean ok, string|nil err
function M.clipboard(text)
  local ok_mod, copy = pcall(require, "lib.nvim.cross.copy_to_clipboard")
  if not ok_mod then
    return false, "clipboard helper unavailable"
  end
  if copy(text) then
    return true, nil
  end
  return false, "no working clipboard provider"
end

--- Write `text` to `path`, creating parent directories as needed.
---@param text string
---@param path string
---@return boolean ok, string|nil err
function M.file(text, path)
  if not path or path == "" then
    return false, "no output path given"
  end
  local ok_mod, to_file = pcall(require, "lib.nvim.fs.write.to_file")
  if not ok_mod then
    return false, "file writer unavailable"
  end
  return to_file(vim.fs.normalize(vim.fn.expand(path)), text)
end

--- Show `text` in a throwaway scratch buffer.
---
--- `buflisted = false` + `bufhidden = wipe` is deliberate: a results view is
--- not a document, so it should not show up in `:ls`, in a buffer picker, or
--- in a session file, and it should disappear the moment its window closes.
---@param text string
---@param opts Lib.Harvest.ScratchOpts|nil
---@return integer bufnr
function M.scratch(text, opts)
  opts = opts or {}

  local split = opts.split or "split"
  if split == "split" then
    vim.cmd("new")
  elseif split == "vsplit" then
    vim.cmd("vnew")
  elseif split == "tab" then
    vim.cmd("tabnew")
  end

  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].filetype = opts.filetype or "markdown"

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false

  if opts.title and opts.title ~= "" then
    -- A scratch buffer name only has to be unique; collisions raise E95, and
    -- a results view is not worth aborting over, hence the pcall.
    pcall(vim.api.nvim_buf_set_name, bufnr, opts.title)
  end

  return bufnr
end

--- Present `items` and invoke `on_choose` with the picked one.
--- Prefers lib.nvim's own float chooser, falling back to `vim.ui.select`.
---@generic T
---@param items T[]
---@param opts Lib.Harvest.SelectOpts|nil
---@param on_choose fun(item: T, idx: integer)
function M.select(items, opts, on_choose)
  opts = opts or {}
  if not items or #items == 0 then
    return
  end
  local format = opts.format or tostring

  local ok, kit = pcall(require, "lib.nvim.ui.kit")
  if ok and kit and type(kit.select) == "function" then
    local labels = {}
    for i, it in ipairs(items) do
      labels[i] = format(it)
    end
    kit.select({
      items = labels,
      title = opts.prompt or "Select",
      relative = "editor",
      on_select = function(_label, idx)
        local chosen = items[idx]
        if chosen then
          on_choose(chosen, idx)
        end
      end,
    })
    return
  end

  vim.ui.select(items, {
    prompt = opts.prompt or "Select",
    format_item = format,
  }, function(choice, idx)
    if choice then
      on_choose(choice, idx)
    end
  end)
end

return M
