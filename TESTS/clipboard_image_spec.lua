-- TESTS/clipboard_image_spec.lua -- lib.nvim.clipboard_image: the clipboard image as a PNG file.

return function(H)
  local ok = H.ok
  local ci = require("lib.nvim.clipboard_image")

  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local PNG = "\137PNG\r\n\26\n" .. "rest-of-image"
  local tmp = vim.fn.tempname() .. "_clip.png"
  local function cleanup()
    pcall(vim.uv.fs_unlink, tmp)
  end

  -- ---- Linux: wl-paste preferred, xclip as the fallback ---------------------
  local seen
  local function fake(res)
    return function(cmd)
      seen = cmd
      return res
    end
  end
  local done, err = ci.save(tmp, {
    platform = "linux",
    has = function(exe)
      return exe == "wl-paste" or exe == "xclip"
    end,
    system = fake({ code = 0, stdout = PNG }),
  })
  ok(done, "linux/wl-paste saves: " .. tostring(err))
  eq(seen[1], "wl-paste", "wl-paste is preferred over xclip")
  eq(vim.fn.readblob(tmp):sub(1, 4), "\137PNG", "the bytes are written verbatim")
  cleanup()

  done = ci.save(tmp, {
    platform = "linux",
    has = function(exe)
      return exe == "xclip"
    end,
    system = fake({ code = 0, stdout = PNG }),
  })
  ok(done, "linux/xclip saves")
  eq(seen[1], "xclip", "xclip is used when wl-paste is missing")
  cleanup()

  -- ---- no image: nothing is written -----------------------------------------
  done, err = ci.save(tmp, {
    platform = "linux",
    has = function()
      return true
    end,
    system = fake({ code = 1, stdout = "" }),
  })
  ok(not done and err:find("no image", 1, true), "an empty clipboard says so")
  ok(vim.uv.fs_stat(tmp) == nil, "and writes nothing")

  done, err = ci.save(tmp, {
    platform = "linux",
    has = function()
      return true
    end,
    system = fake({ code = 0, stdout = "just some copied text" }),
  })
  ok(not done and err:find("no PNG", 1, true), "text on the clipboard is not stored as an image")
  ok(vim.uv.fs_stat(tmp) == nil, "and nothing is written for it either")

  -- ---- missing tools are a message, not an error ----------------------------
  done, err = ci.save(tmp, {
    platform = "linux",
    has = function()
      return false
    end,
  })
  ok(not done and err:find("wl-paste", 1, true), "no tool: the message names wl-paste/xclip")
  done, err = ci.save(tmp, {
    platform = "macos",
    has = function()
      return false
    end,
  })
  ok(not done and err:find("pngpaste", 1, true), "macOS without pngpaste says so")
  local tool, why = ci.tool({
    platform = "linux",
    has = function()
      return false
    end,
  })
  ok(tool == nil and why ~= nil, "tool() reports the reason for :checkhealth")
  eq(ci.tool({ platform = "windows" }), "powershell.exe", "tool() on Windows")

  -- ---- Windows / macOS: the tool writes the file itself ---------------------
  done, err = ci.save(tmp, {
    platform = "windows",
    system = function(cmd)
      ok(
        cmd[1] == "powershell.exe" and vim.tbl_contains(cmd, "-STA"),
        "windows runs powershell.exe -STA"
      )
      ok(
        cmd[#cmd]:find("'" .. tmp:gsub("'", "''") .. "'", 1, true),
        "the path is a quoted PowerShell string"
      )
      vim.fn.writefile({ "x" }, tmp, "b")
      return { code = 0 }
    end,
  })
  ok(done, "windows: a written file is success: " .. tostring(err))
  cleanup()

  done, err = ci.save(tmp, {
    platform = "windows",
    system = function()
      return { code = 3 }
    end,
  })
  ok(not done and err:find("no image", 1, true), "windows exit 3 means no image")

  done, err = ci.save(tmp, {
    platform = "windows",
    system = function()
      return { code = 0 }
    end,
  })
  ok(not done and err:find("no image", 1, true), "windows: success without a file is no image")

  done, err = ci.save(tmp, {
    platform = "macos",
    has = function()
      return true
    end,
    system = function()
      return { code = 2, stderr = "boom\n" }
    end,
  })
  ok(not done and err:find("boom", 1, true), "a failing tool reports its stderr")

  -- a quote in the path cannot break out of the PowerShell string
  local quoted
  ci.save("C:/it's/a.png", {
    platform = "windows",
    system = function(cmd)
      quoted = cmd[#cmd]
      return { code = 3 }
    end,
  })
  ok(quoted:find("'C:/it''s/a.png'", 1, true), "a single quote in the path is doubled")

  eq(
    select(2, ci.save("", {})),
    "clipboard_image.save needs a target path",
    "an empty path is refused"
  )
end
