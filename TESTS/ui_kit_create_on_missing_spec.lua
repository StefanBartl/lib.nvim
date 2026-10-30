-- TESTS/ui_kit_create_on_missing_spec.lua -- kit.create_on_missing: the "path does not exist" dialog.
-- Create makes the file or directory with its missing parents (fs.create_entry) and opens a file;
-- "Open in filetree" is offered only for a loaded, set-up filetree.nvim (or a caller's function)
-- and reveals the deepest existing directory; Cancel and a dismissal do nothing; a path that
-- exists asks nothing. Answered through the dialog hook, so no window is needed.

return function(H)
  local eq, ok = H.eq, H.ok
  local function same(actual, expected, msg)
    if not vim.deep_equal(actual, expected) then
      error(
        ("FAIL %s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual)),
        2
      )
    end
  end
  local kit = require("lib.nvim.ui.kit")
  local com = require("lib.nvim.ui.kit.create_on_missing")

  eq(type(kit.create_on_missing), "function", "kit.create_on_missing is exposed")

  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")

  --- The questions the hook saw, and the answer it gives next.
  local seen, answer = {}, nil
  kit.set_dialog_hook(function(kind, opts)
    seen[#seen + 1] =
      { kind = kind, choices = opts.choices, question = opts.question, title = opts.title }
    return true, answer
  end)

  --- Run the dialog for `path` with `opts`, answered with `value`; the result `on_done` got.
  ---@return Lib.UI.Kit.CreateOnMissingResult|nil, integer calls
  local function run(path, value, opts)
    seen, answer = {}, value
    local box = { calls = 0 }
    opts = vim.tbl_extend("force", opts or {}, {
      path = path,
      on_done = function(res)
        box.calls = box.calls + 1
        box.res = res
      end,
    })
    kit.create_on_missing(opts)
    vim.wait(500, function()
      return box.calls > 0
    end, 5)
    vim.wait(20) -- a second (wrong) call would come right after the first
    return box.res, box.calls
  end

  local fake_ft
  --- Install a fake filetree.nvim in package.loaded; `initialized` as is_initialized() says.
  local function install_filetree(initialized, reveal_ok)
    fake_ft = { revealed = {} }
    package.loaded["filetree"] = {
      is_initialized = function()
        return initialized
      end,
      adapter = function()
        return {
          open_reveal = function(path, levels)
            fake_ft.revealed[#fake_ft.revealed + 1] = { path = path, levels = levels }
            return reveal_ok ~= false
          end,
        }
      end,
    }
  end

  local ok_run, err_run = pcall(function()
    -- Create: the file and every missing parent, then the file is opened
    local target = root .. "/a/b/new.txt"
    local res, calls = run(target, com.CREATE)
    eq(calls, 1, "create: on_done once")
    eq(res.action, "created", "create: reported as created")
    eq(res.kind, "file", "create: a file")
    eq(res.path, target, "create: the new path, normalized")
    eq(vim.fn.filereadable(target), 1, "create: the file exists")
    eq(
      vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
      target,
      "create: the file is open in the window"
    )
    eq(seen[1].kind, "confirm", "the question is a kit.confirm")
    ok(seen[1].question:find("new.txt does not exist", 1, true), "the question names the path")
    ok(
      seen[1].question:find("Missing directories are created too: a/b/", 1, true),
      "the question names the missing directories: " .. seen[1].question
    )
    eq(seen[1].title, "Create file?", "default title")
    vim.cmd("enew!")

    -- open = false: created, not opened; a missing file in an existing directory names no directories
    local buf_before = vim.api.nvim_get_current_buf()
    res = run(root .. "/plain.txt", com.CREATE, { open = false })
    eq(res.action, "created", "open=false: created")
    eq(vim.api.nvim_get_current_buf(), buf_before, "open=false: nothing opened")
    eq(
      seen[1].question:find("Missing directories", 1, true),
      nil,
      "no parent missing: no directory line"
    )

    -- open as a function is called with the path and the kind instead of :edit
    local opened
    res = run(root .. "/fn.txt", com.CREATE, {
      open = function(p, k)
        opened = { p, k }
      end,
    })
    eq(opened and opened[1], root .. "/fn.txt", "open fn: gets the path")
    eq(opened and opened[2], "file", "open fn: ...and the kind")
    eq(res.action, "created", "open fn: created")

    -- a trailing separator creates a directory (with parents) and opens nothing
    buf_before = vim.api.nvim_get_current_buf()
    res = run(root .. "/d1/d2/", com.CREATE)
    eq(res.action, "created", "dir: created")
    eq(res.kind, "directory", "dir: a directory")
    eq(vim.fn.isdirectory(root .. "/d1/d2"), 1, "dir: exists")
    eq(vim.api.nvim_get_current_buf(), buf_before, "dir: nothing opened")
    eq(seen[1].title, "Create directory?", "dir: its own title")
    ok(
      seen[1].question:find("Missing directories are created too: d1/d2/", 1, true),
      "dir: names the directories"
    )

    -- Cancel and a dismissal (nil) create nothing
    for _, v in ipairs({ com.CANCEL, false }) do
      local p = root .. "/x/cancel.txt"
      res = run(p, v or nil)
      eq(res.action, "cancelled", "cancel " .. tostring(v) .. ": reported")
      eq(res.path, p, "cancel: the missing path")
      eq(vim.fn.isdirectory(root .. "/x"), 0, "cancel: no directory made")
    end

    -- a path that exists asks nothing and is opened
    res = run(target, com.CREATE)
    eq(#seen, 0, "exists: no question")
    eq(res.action, "exists", "exists: reported")
    eq(res.kind, "file", "exists: a file")
    eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), target, "exists: opened")
    vim.cmd("enew!")

    -- create_entry refuses a bad name: an error result, nothing made
    local notified = {}
    H.with_patched(vim, "notify", function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end, function()
      res = run(root .. "/bad/na*me.txt", com.CREATE)
    end)
    eq(res.action, "error", "bad name: an error")
    ok(
      res.err and res.err:find("invalid characters", 1, true),
      "bad name: create_entry's reason: " .. tostring(res.err)
    )
    eq(vim.fn.isdirectory(root .. "/bad"), 0, "bad name: no parent directory left behind")
    eq(notified[1] and notified[1].level, vim.log.levels.ERROR, "bad name: told as an error")

    -- filetree: no filetree.nvim -> no button
    package.loaded["filetree"] = nil
    eq(com.filetree_available(), false, "no filetree loaded: not available")
    run(root .. "/nf/f.txt", com.CANCEL)
    same(seen[1].choices, { com.CREATE, com.CANCEL }, "no filetree: Create / Cancel only")

    -- loaded but not set up -> no button either
    install_filetree(false)
    eq(com.filetree_available(), false, "filetree not set up: not available")
    run(root .. "/nf/f.txt", com.CANCEL)
    same(seen[1].choices, { com.CREATE, com.CANCEL }, "filetree not set up: no button")

    -- set up -> the button, and choosing it reveals the deepest existing directory
    install_filetree(true)
    eq(com.filetree_available(), true, "filetree set up: available")
    res = run(root .. "/a/b/c/d/f.txt", com.FILETREE)
    same(seen[1].choices, { com.CREATE, com.FILETREE, com.CANCEL }, "filetree: the button between")
    eq(res.action, "filetree", "filetree: reported")
    eq(res.path, root .. "/a/b", "filetree: the deepest existing directory")
    eq(#fake_ft.revealed, 1, "filetree: revealed once")
    eq(fake_ft.revealed[1].path, root .. "/a/b", "filetree: open_reveal got that directory")
    eq(vim.fn.isdirectory(root .. "/a/b/c"), 0, "filetree: nothing created")

    -- the dialog hook may also answer by button index
    res = run(root .. "/a/b/c/idx.txt", 2)
    eq(res.action, "filetree", "filetree by index 2")

    -- filetree = false hides the button even with filetree.nvim present
    run(root .. "/nf/f.txt", com.CANCEL, { filetree = false })
    same(seen[1].choices, { com.CREATE, com.CANCEL }, "filetree=false: no button")

    -- a reveal that fails is an error, not a silent success
    install_filetree(true, false)
    H.with_patched(vim, "notify", function() end, function()
      res = run(root .. "/a/zz.txt", com.FILETREE)
    end)
    eq(res.action, "error", "failed reveal: an error")

    -- a caller's own reveal function: offered without filetree.nvim, called with the ancestor
    package.loaded["filetree"] = nil
    local got
    res = run(root .. "/a/q/r.txt", com.FILETREE, {
      filetree = function(p)
        got = p
        return true
      end,
    })
    same(seen[1].choices, { com.CREATE, com.FILETREE, com.CANCEL }, "own reveal: the button")
    eq(got, root .. "/a", "own reveal: gets the existing ancestor")
    eq(res.action, "filetree", "own reveal: reported")

    -- a missing or empty path is a caller error
    eq(pcall(kit.create_on_missing, {}), false, "no path: raises")
    eq(pcall(kit.create_on_missing, { path = "" }), false, "empty path: raises")
  end)

  kit.set_dialog_hook(nil)
  package.loaded["filetree"] = nil
  vim.fn.delete(root, "rf")
  if not ok_run then
    error(err_run, 0)
  end
end
