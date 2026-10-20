-- TESTS/copy_image_to_clipboard_spec.lua — lib.nvim.cross.copy_image_to_clipboard
--
-- `plan` is pure, so every platform's choice is checked here on whichever one runs the
-- suite; `copy` is checked only for the refusals that happen before any tool is started.

return function(H)
  local clip = require("lib.nvim.cross.copy_image_to_clipboard")

  local function platform(over)
    local p = {
      windows = false,
      wsl = false,
      macos = false,
      linux = false,
      wayland = false,
      x11 = false,
      wslenv = "",
      has = function()
        return true
      end,
    }
    for k, v in pairs(over or {}) do
      p[k] = v
    end
    return p
  end

  local function only(...)
    local set = {}
    for _, bin in ipairs({ ... }) do
      set[bin] = true
    end
    return function(bin)
      return set[bin] == true
    end
  end

  -- A name that would break or hijack any script it were spliced into.
  local hostile = "/tmp/it's $(rm -rf ~); `x` ’quote’.png"

  local function joined(plan)
    return table.concat(plan.argv, " ")
  end

  -- native Windows ------------------------------------------------------------
  do
    local plan =
      clip.plan(hostile, platform({ windows = true, has = only("powershell.exe", "pwsh") }))
    H.eq(plan.argv[1], "powershell.exe", "windows: prefers powershell.exe")
    H.ok(
      vim.tbl_contains(plan.argv, "-STA"),
      "windows: runs -STA (the WinForms clipboard needs it)"
    )
    H.eq(plan.env.LIB_NVIM_CLIP_IMAGE, hostile, "windows: the path travels in the environment")
    H.ok(not joined(plan):find("rm -rf", 1, true), "windows: the path never enters the script")
    H.eq(plan.stdin_file, nil, "windows: nothing on stdin")

    plan = clip.plan(hostile, platform({ windows = true, has = only("pwsh") }))
    H.eq(plan.argv[1], "pwsh", "windows: falls back to pwsh")

    local none, err = clip.plan(hostile, platform({ windows = true, has = only() }))
    H.eq(none, nil, "windows: no PowerShell, no plan")
    H.ok(err:find("powershell", 1, true) ~= nil, "windows: and says which tool is missing")
  end

  -- WSL -----------------------------------------------------------------------
  do
    local plan = clip.plan("/home/u/a.png", platform({ wsl = true, has = only("powershell.exe") }))
    H.eq(plan.argv[1], "powershell.exe", "wsl: goes through powershell.exe")
    H.eq(plan.env.WSLENV, "LIB_NVIM_CLIP_IMAGE/p", "wsl: WSLENV translates the path")

    plan = clip.plan(
      "/home/u/a.png",
      platform({ wsl = true, wslenv = "USERPROFILE/p", has = only("powershell.exe") })
    )
    H.eq(plan.env.WSLENV, "USERPROFILE/p:LIB_NVIM_CLIP_IMAGE/p", "wsl: an existing WSLENV is kept")
  end

  -- macOS ---------------------------------------------------------------------
  do
    local plan = clip.plan(hostile, platform({ macos = true, has = only("osascript") }))
    H.eq(plan.argv[1], "osascript", "macos: osascript")
    H.ok(joined(plan):find("PNGf", 1, true) ~= nil, "macos: reads the file as PNG")
    H.eq(plan.env.LIB_NVIM_CLIP_IMAGE, hostile, "macos: the path travels in the environment")
    H.ok(not joined(plan):find("rm -rf", 1, true), "macos: the path never enters the script")
  end

  -- Linux ---------------------------------------------------------------------
  do
    local plan = clip.plan("/tmp/a.png", platform({ linux = true, wayland = true, x11 = true }))
    H.eq(plan.argv[1], "wl-copy", "linux: Wayland first when both are there")
    H.ok(plan.stdin_file == true, "linux: wl-copy reads the image on stdin")
    H.ok(vim.tbl_contains(plan.argv, "image/png"), "linux: wl-copy is told the type")

    plan = clip.plan(hostile, platform({ linux = true, x11 = true }))
    H.eq(plan.argv[1], "xclip", "linux: xclip under X11")
    H.eq(plan.argv[#plan.argv], hostile, "linux: xclip gets the path as one argv element")

    plan = clip.plan("/tmp/a.png", platform({ linux = true, wayland = true, has = only("xclip") }))
    H.eq(plan.argv[1], "xclip", "linux: falls back to whatever is on PATH")

    local none, err =
      clip.plan("/tmp/a.png", platform({ linux = true, x11 = true, has = only("xsel") }))
    H.eq(none, nil, "linux: xsel cannot carry images, so no plan")
    H.ok(err:find("xclip", 1, true) ~= nil, "linux: and says what to install")
  end

  -- nothing at all ------------------------------------------------------------
  do
    local none = clip.plan("/tmp/a.png", platform())
    H.eq(none, nil, "unknown platform: no plan")
  end

  -- copy(): refusals before any tool starts -----------------------------------
  local function copy_result(path)
    local got
    clip(path, function(ok, err)
      got = { ok = ok, err = err }
    end)
    vim.wait(1000, function()
      return got ~= nil
    end)
    return got
  end

  do
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")

    local fake = dir .. "/not-really.png"
    local fd = assert(io.open(fake, "wb"))
    fd:write("GIF89a")
    fd:close()

    local got = copy_result(fake)
    H.ok(got and got.ok == false, "copy: a file that is not a PNG is refused")
    H.ok(got and tostring(got.err):find("not a PNG", 1, true) ~= nil, "copy: and says so")

    got = copy_result(dir .. "/missing.png")
    H.ok(got and got.ok == false, "copy: a missing file is refused")
    H.ok(got and tostring(got.err):find("cannot read", 1, true) ~= nil, "copy: and says so")

    got = copy_result("")
    H.ok(got and got.ok == false, "copy: an empty path is refused")

    vim.fn.delete(dir, "rf")
  end
end
