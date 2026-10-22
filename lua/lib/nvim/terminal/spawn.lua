---@module 'lib.nvim.terminal.spawn'
--- Start a program in a terminal buffer shown in a float or a split.
---
--- The common core of every "run this in a terminal window" feature: build the
--- window, `jobstart` the argv (never a shell string) with `term = true`, treat
--- a return value `<= 0` as a failure that must not leave a window around a
--- dead terminal, and tidy up in `on_exit` (the window may be gone by then).
--- What differs between callers stays with them: titles and terminal-mode
--- keymaps (`opts.on_open`), what to type, what to do after the exit.

local M = {}

local DEFAULT_RATIO = 0.9

---Geometry of a centered float covering `ratio` of the editor. Pure.
---@param columns integer
---@param lines integer
---@param ratio? number 0 < ratio <= 1, default 0.9
---@return { width: integer, height: integer, row: integer, col: integer }
function M.float_geometry(columns, lines, ratio)
  ratio = ratio or DEFAULT_RATIO
  local width = math.floor(columns * ratio)
  local height = math.floor(lines * ratio)
  return {
    width = width,
    height = height,
    row = math.floor((lines - height) / 2 - 1),
    col = math.floor((columns - width) / 2),
  }
end

---Normalize `argv`: a non-empty list of strings is used as is, a non-empty
---string is wrapped as one program name (no shell parsing). Pure.
---@param argv string|string[]|nil
---@return string[]|nil argv
---@return string|nil err
function M.normalize_argv(argv)
  if type(argv) == "string" then
    if argv == "" then
      return nil, "argv is empty"
    end
    return { argv }
  end
  if type(argv) ~= "table" or #argv == 0 then
    return nil, "argv must be a non-empty list"
  end
  for _, a in ipairs(argv) do
    if type(a) ~= "string" then
      return nil, "argv holds a non-string"
    end
  end
  return argv
end

---@param opts Lib.Terminal.SpawnOpts
---@return integer|nil winid
---@return integer bufnr
local function open_window(opts)
  local layout = opts.layout or "float"
  local bufnr = vim.api.nvim_create_buf(false, layout == "float")
  if layout == "float" then
    local g = M.float_geometry(vim.o.columns, vim.o.lines, opts.ratio)
    local ok, winid = pcall(vim.api.nvim_open_win, bufnr, true, {
      relative = "editor",
      width = g.width,
      height = g.height,
      row = g.row,
      col = g.col,
      border = opts.border or "rounded",
      style = "minimal",
      title = opts.title,
      title_pos = opts.title and "center" or nil,
    })
    if not ok then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      return nil, bufnr
    end
    return winid, bufnr
  end
  vim.cmd(layout == "vsplit" and "belowright vsplit" or "belowright split")
  local winid = vim.api.nvim_get_current_win()
  if opts.size then
    vim.api.nvim_win_set_height(winid, opts.size)
  end
  vim.api.nvim_win_set_buf(winid, bufnr)
  return winid, bufnr
end

---Start `opts.argv` in a terminal window.
---
---`close_on_exit`: `"always"` closes the window when the program ends,
---`"ok"` only on exit code 0, `"never"` (default) leaves it. `on_exit(code,
---bufnr)` runs scheduled, after that.
---
---Returns `nil, message` when the window or the job could not be created; no
---window is left behind in that case and `on_exit` never fires.
---@param opts Lib.Terminal.SpawnOpts
---@return Lib.Terminal.Spawned|nil spawned
---@return string|nil err
function M.spawn(opts)
  opts = opts or {}
  local argv, err = M.normalize_argv(opts.argv)
  if not argv then
    return nil, err
  end

  local winid, bufnr = open_window(opts)
  if not winid then
    return nil, "failed to open the window"
  end

  local close = opts.close_on_exit or "never"
  local job_opts = {
    cwd = opts.cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        -- The window may already be gone (closed by hand) by now.
        if
          (close == "always" or (close == "ok" and code == 0))
          and vim.api.nvim_win_is_valid(winid)
        then
          vim.api.nvim_win_close(winid, true)
        end
        if opts.on_exit then
          opts.on_exit(code, bufnr)
        end
      end)
    end,
  }

  local ok, job
  if vim.fn.has("nvim-0.11") == 1 then
    ok, job = pcall(vim.fn.jobstart, argv, vim.tbl_extend("force", job_opts, { term = true }))
  else
    ---@diagnostic disable-next-line: deprecated
    ok, job = pcall(vim.fn.termopen, argv, job_opts)
  end
  -- jobstart() returns 0 (invalid arguments) or -1 (not executable) on a
  -- SYNCHRONOUS failure; on_exit never fires for either, so the window around
  -- the dead terminal has to be closed here.
  if not ok or type(job) ~= "number" or job <= 0 then
    pcall(vim.api.nvim_win_close, winid, true)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return nil, ("failed to start %s"):format(argv[1])
  end

  if opts.on_open then
    opts.on_open(bufnr, winid, job)
  end
  if opts.startinsert ~= false then
    vim.cmd("startinsert")
  end
  return { bufnr = bufnr, winid = winid, job = job }
end

return M
