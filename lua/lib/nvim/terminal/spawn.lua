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
---@return integer|nil bufnr
---@return string|nil err why the window could not be opened (nothing is left behind then)
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
      return nil, nil, tostring(winid)
    end
    return winid, bufnr
  end
  -- E36 (not enough room) must come back as a failure, not a throw that
  -- leaves the buffer created above behind.
  local ok, split_err =
    pcall(vim.cmd, layout == "vsplit" and "belowright vsplit" or "belowright split")
  if not ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return nil, nil, tostring(split_err)
  end
  local winid = vim.api.nvim_get_current_win()
  if opts.size then
    -- The height of a vsplit is the height of its whole row: setting it would
    -- resize the windows beside it too.
    if layout == "vsplit" then
      pcall(vim.api.nvim_win_set_width, winid, opts.size)
    else
      pcall(vim.api.nvim_win_set_height, winid, opts.size)
    end
  end
  vim.api.nvim_win_set_buf(winid, bufnr)
  return winid, bufnr
end

---Closes `winid` and wipes `bufnr`, both only if still there. Never throws:
---closing the last window (E444) leaves it, the buffer goes either way when
---it is not shown anywhere else.
---@param winid integer
---@param bufnr integer
local function discard(winid, bufnr)
  if vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
  if vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) == 0 then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
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

  local winid, bufnr, win_err = open_window(opts)
  if not winid or not bufnr then
    return nil, "failed to open the window: " .. (win_err or "unknown error")
  end

  local close = opts.close_on_exit or "never"
  local job_opts = {
    cwd = opts.cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        -- The window may already be gone (closed by hand) by now, or be the
        -- last one (then it stays); either way on_exit below still runs.
        if close == "always" or (close == "ok" and code == 0) then
          discard(winid, bufnr)
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
    discard(winid, bufnr)
    return nil, ("failed to start %s"):format(argv[1])
  end

  if opts.on_open then
    -- A throwing on_open would leave a running program in a window its caller
    -- does not know about: stop it and report like any other start failure.
    local open_ok, open_err = pcall(opts.on_open, bufnr, winid, job)
    if not open_ok then
      pcall(vim.fn.jobstop, job)
      discard(winid, bufnr)
      return nil, ("on_open failed for %s: %s"):format(argv[1], tostring(open_err))
    end
  end
  if opts.startinsert ~= false then
    vim.cmd("startinsert")
  end
  return { bufnr = bufnr, winid = winid, job = job }
end

return M
