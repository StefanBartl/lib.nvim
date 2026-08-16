---@module 'lib.nvim.fs.write.async'
--- Asynchronous counterpart to `lib.nvim.fs.write.to_file`: creates the
--- parent directory synchronously, then opens/writes/closes the file via
--- libuv without blocking the editor.
---
---   require("lib.nvim.fs.write.async")("/tmp/out.txt", "hello", function(ok, err)
---     if not ok then vim.notify("write failed: " .. tostring(err)) end
---   end)
---
--- `cb` is invoked on the main loop (wrapped in `vim.schedule`), so it is
--- safe to touch `vim.api.*` from inside it.

require("lib.nvim.fs.write.async.@types")

-- LuaJIT (Neovim's Lua runtime) has neither `table.pack` nor Lua 5.2+'s
-- `table.unpack` — only the global `unpack`, and no `pack` at all.
---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack
local pack = table.pack or function(...)
  return { n = select("#", ...), ... }
end

-- ============================================================================
-- Internal coroutine-await plumbing, mirroring the private helper of the
-- same shape in `lib.nvim.fs.collect_recursive` (`collect_async` etc.).
-- Deliberately duplicated here rather than extracted into a shared/public
-- module — this repo's plenary/libuv research explicitly avoids building a
-- general async library without a concrete second-and-beyond consumer
-- driving its shape; two near-identical private copies is the honest cost
-- of that restraint.
-- ============================================================================

---@internal
--- Suspend the running coroutine until `starter` settles. `starter(resume)`
--- must arrange for `resume(...)` to be called — typically by passing it
--- straight through as a libuv callback. Whatever `resume` receives becomes
--- this call's return values. Only valid inside a coroutine driven by
--- `run_async`.
---@param starter fun(resume: fun(...))
---@return ... whatever `resume` was called with
local function await(starter)
  return coroutine.yield(starter)
end

---@internal
--- Drive a coroutine written against `await()` to completion. `on_done`
--- receives `body`'s return values (possibly multiple), `vim.schedule`-
--- dispatched — every resume happens from inside a raw libuv callback (fast-
--- event context), so nothing past the last `await()` may safely touch
--- `vim.fn`/`vim.api` without this.
---@param body fun(): ...
---@param on_done fun(...)
local function run_async(body, on_done)
  local co = coroutine.create(body)

  local function step(...)
    local results = pack(coroutine.resume(co, ...))
    if not results[1] then
      -- A bug in `body` surfaces here, inside a libuv callback rather than
      -- the caller's own stack — routed through vim.schedule + vim.notify
      -- so it reaches :messages instead of vanishing into the event loop.
      local err = results[2]
      vim.schedule(function()
        vim.notify("[lib.nvim.fs.write.async] " .. tostring(err), vim.log.levels.ERROR)
      end)
      return
    end
    if coroutine.status(co) == "dead" then
      vim.schedule(function()
        on_done(unpack(results, 2, results.n))
      end)
      return
    end
    -- results[2] is the starter function `body` handed to `await()`,
    -- expecting `step` itself as its `resume` callback.
    results[2](step)
  end

  step()
end

---@param path string
---@param content string
---@param cb fun(ok: boolean, err: string|nil)
return function(path, content, cb)
  local uv = vim.uv or vim.loop

  local dir = vim.fn.fnamemodify(path, ":h")
  if dir == "" then
    vim.schedule(function()
      cb(false, "Invalid directory for path: " .. path)
    end)
    return
  end
  local ok_mkdir, err_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    vim.schedule(function()
      cb(false, "mkdir failed: " .. tostring(err_mkdir))
    end)
    return
  end

  run_async(function()
    -- 438 == 0644 (decimal literal; libuv takes the mode as a number).
    local open_err, fd = await(function(resume)
      uv.fs_open(path, "w", 438, resume)
    end)
    if open_err or not fd then
      return false, "open failed: " .. tostring(open_err or path)
    end

    local write_err = await(function(resume)
      uv.fs_write(fd, content, -1, resume)
    end)
    local close_err = await(function(resume)
      uv.fs_close(fd, resume)
    end)

    local err = write_err or close_err
    return err == nil, err and tostring(err) or nil
  end, cb)
end
