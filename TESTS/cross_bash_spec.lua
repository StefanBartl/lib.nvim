-- TESTS/cross_bash_spec.lua — lib.nvim.cross.bash (Git Bash locator, never the WSL launcher)

return function(H)
  local eq = H.eq
  local bash = require("lib.nvim.cross.bash")

  --- A fake system: `files` are the paths that exist, `env` the variables.
  ---@param o { windows?: boolean, env?: table<string,string>, files?: string[], exec_path?: string, path_bash?: string }
  ---@return Lib.Cross.Bash.Io
  local function fake(o)
    local files = {}
    for _, f in ipairs(o.files or {}) do
      files[f] = true
    end
    return {
      is_windows = function()
        return o.windows ~= false
      end,
      getenv = function(name)
        return (o.env or {})[name]
      end,
      is_file = function(path)
        return files[path] == true
      end,
      git_exec_path = function()
        return o.exec_path
      end,
      exepath = function(name)
        return name == "bash" and o.path_bash or nil
      end,
    }
  end

  -- 1. ProgramFiles (backslashes are normalized)
  eq(
    bash.locate(fake({
      env = { ProgramFiles = [[D:\Apps]] },
      files = { "D:/Apps/Git/bin/bash.exe" },
    })),
    "D:/Apps/Git/bin/bash.exe",
    "ProgramFiles candidate"
  )

  -- 2. ProgramW6432 when ProgramFiles has no Git (32-bit process)
  eq(
    bash.locate(fake({
      env = { ProgramFiles = [[C:\Program Files (x86)]], ProgramW6432 = [[E:\PF]] },
      files = { "E:/PF/Git/bin/bash.exe" },
    })),
    "E:/PF/Git/bin/bash.exe",
    "ProgramW6432 candidate"
  )

  -- 3. derived from `git --exec-path` (scoop / portable install), trailing newline as git prints it
  eq(
    bash.locate(fake({
      exec_path = "C:/Users/u/scoop/apps/git/current/mingw64/libexec/git-core\n",
      files = { "C:/Users/u/scoop/apps/git/current/bin/bash.exe" },
    })),
    "C:/Users/u/scoop/apps/git/current/bin/bash.exe",
    "git --exec-path candidate"
  )

  -- 4. the fixed default path
  eq(
    bash.locate(fake({ files = { "C:/Program Files/Git/bin/bash.exe" } })),
    "C:/Program Files/Git/bin/bash.exe",
    "fixed default candidate"
  )

  -- 5. bash on PATH that is a real Git Bash
  eq(
    bash.locate(
      fake({ path_bash = [[F:\tools\git\bin\bash.exe]], files = { "F:/tools/git/bin/bash.exe" } })
    ),
    "F:/tools/git/bin/bash.exe",
    "bash on PATH when it is not the WSL launcher"
  )

  -- WSL launcher on PATH: never returned, named in the reason
  for _, wsl in ipairs({
    [[C:\Windows\System32\bash.exe]],
    [[C:\Users\u\AppData\Local\Microsoft\WindowsApps\bash.exe]],
  }) do
    local files = { (wsl:gsub("\\", "/")) }
    local path, reason = bash.locate(fake({ path_bash = wsl, files = files }))
    eq(path, nil, "WSL launcher is never returned: " .. wsl)
    eq(
      type(reason) == "string" and reason:find("WSL launcher, skipped", 1, true) ~= nil,
      true,
      "reason names it"
    )
  end

  -- even a ProgramFiles that points into System32 is not taken
  eq(
    bash.locate(fake({
      env = { ProgramFiles = [[C:\Windows\System32]] },
      files = { "C:/Windows/System32/Git/bin/bash.exe" },
    })),
    nil,
    "a candidate inside System32 is rejected"
  )

  -- nothing found: nil + reason listing the searched places
  local none, why = bash.locate(fake({ env = { ProgramFiles = "C:/PF" } }))
  eq(none, nil, "no candidate -> nil")
  eq(
    why:find("C:/PF/Git/bin/bash.exe", 1, true) ~= nil,
    true,
    "reason lists ProgramFiles candidate"
  )
  eq(
    why:find("C:/Program Files/Git/bin/bash.exe", 1, true) ~= nil,
    true,
    "reason lists the default candidate"
  )

  -- order: ProgramFiles wins over the PATH entry
  eq(
    bash.locate(fake({
      env = { ProgramFiles = "C:/PF" },
      files = { "C:/PF/Git/bin/bash.exe", "F:/other/bash.exe" },
      path_bash = "F:/other/bash.exe",
    })),
    "C:/PF/Git/bin/bash.exe",
    "ProgramFiles comes before PATH"
  )

  -- not Windows: plain `bash` when it is on PATH
  eq(bash.locate(fake({ windows = false, path_bash = "/usr/bin/bash" })), "bash", "POSIX: bash")
  local p, r = bash.locate(fake({ windows = false }))
  eq(p, nil, "POSIX without bash -> nil")
  eq(type(r), "string", "POSIX without bash -> reason")

  eq(bash.is_wsl_launcher([[C:\WINDOWS\system32\bash.exe]]), true, "case-insensitive System32")
  eq(
    bash.is_wsl_launcher("C:/Program Files/Git/bin/bash.exe"),
    false,
    "Git Bash is not the launcher"
  )

  -- ARM64 Git for Windows (clangarm64) and MSYS2 (only usr/bin/bash.exe)
  eq(
    bash.locate(fake({
      exec_path = "D:/PortableGit/clangarm64/libexec/git-core",
      files = { "D:/PortableGit/bin/bash.exe" },
    })),
    "D:/PortableGit/bin/bash.exe",
    "clangarm64 exec-path"
  )
  eq(
    bash.locate(fake({
      exec_path = "C:/msys64/mingw64/libexec/git-core",
      files = { "C:/msys64/usr/bin/bash.exe" },
    })),
    "C:/msys64/usr/bin/bash.exe",
    "MSYS2 layout falls back to usr/bin"
  )

  -- the same folder from ProgramFiles, ProgramW6432 and the default is searched once
  local stats = 0
  local io_dup = fake({
    env = { ProgramFiles = [[C:\Program Files]], ProgramW6432 = [[C:\Program Files]] },
  })
  io_dup.is_file = function()
    stats = stats + 1
    return false
  end
  local _, dup_reason = bash.locate(io_dup)
  eq(stats, 1, "one stat for one folder")
  local _, count = dup_reason:gsub("Program Files/Git/bin/bash%.exe", "")
  eq(count, 1, "the reason names it once")

  -- memoized: locate runs once until clear()
  local orig, calls = bash.locate, 0
  bash.locate = function()
    calls = calls + 1
    return "X"
  end
  bash.clear()
  bash.find()
  bash.find()
  eq(calls, 1, "find() is memoized")
  bash.clear()
  eq(bash.find(), "X", "find() returns the located path")
  eq(calls, 2, "clear() resets the memo")
  bash.locate = orig
  bash.clear()
  eq(require("lib.nvim.cross").bash, bash.find, "cross.bash is the locator")

  -- a fast event gets nil + reason, nothing is cached
  local fast_path, fast_reason
  local timer = assert((vim.uv or vim.loop).new_timer())
  timer:start(0, 0, function()
    fast_path, fast_reason = bash.find()
    timer:close()
  end)
  vim.wait(2000, function()
    return fast_reason ~= nil
  end)
  eq(fast_path, nil, "fast event: no path")
  eq(
    type(fast_reason) == "string" and fast_reason:find("fast event", 1, true) ~= nil,
    true,
    "fast event: reason"
  )

  local a = bash.find()

  -- live: on this Windows machine the result (if any) is a real file and not the launcher
  if vim.fn.has("win32") == 1 and a then
    eq(bash.is_wsl_launcher(a), false, "live result is not the WSL launcher")
    eq((vim.uv or vim.loop).fs_stat(a) ~= nil, true, "live result exists")
  end
  bash.clear()
end
