---@module 'lib.nvim.cross.uv.wait_until'
--- Poll a predicate on a libuv timer until it returns true or a maximum
--- number of attempts is reached. Generic — not tied to any specific
--- filesystem/process use case (e.g. "wait for a file to appear", "wait for
--- a port to open").

---@param predicate fun(): boolean
---@param opts? { interval_ms?: integer, max_attempts?: integer }
---@param cb fun(ok: boolean)
return function(predicate, opts, cb)
  opts = opts or {}
  local interval_ms = opts.interval_ms or 100
  local max_attempts = opts.max_attempts or 50

  local loop = vim.uv or vim.loop
  local timer = loop.new_timer()
  local attempts = 0

  local function stop(ok)
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
    vim.schedule(function()
      cb(ok)
    end)
  end

  timer:start(0, interval_ms, function()
    attempts = attempts + 1
    local ok = predicate()
    if ok then
      stop(true)
    elseif attempts >= max_attempts then
      stop(false)
    end
  end)
end
