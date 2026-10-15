-- TESTS/resolve_lib_nvim_spec.lua -- templates/resolve_lib_nvim.lua: the snippet a plugin copies to find its sibling
-- lib.nvim checkout. A folder name with a comma must stay ONE runtimepath entry ('runtimepath' is a comma list).

return function(H)
  local eq, ok = H.eq, H.ok

  local template = vim.fn.getcwd() .. "/templates/resolve_lib_nvim.lua"
  local resolve = dofile(template)

  local base = vim.fn.tempname() .. "-resolve"
  local lib = base .. "/my,lib.nvim"
  vim.fn.mkdir(lib .. "/lua/lib", "p")
  lib = vim.fs.normalize(lib)

  local saved_rtp = vim.o.runtimepath
  local saved_path = package.path
  local saved_env = vim.env.LIB_NVIM_PATH
  vim.env.LIB_NVIM_PATH = lib

  local found, reached, stray = nil, 0, false
  -- Whatever goes wrong inside, the runtimepath, package.path and the environment are put back below: a spec
  -- that leaves them changed would colour every spec after it in this one editor.
  local ran, err = pcall(function()
    found = resolve()
    -- Asked of the runtime itself, not of `vim.opt.rtp:get()` (which splits a `\,` it is given back wrong):
    -- does the runtimepath reach the checkout's `lua/lib` folder?
    for _, dir in ipairs(vim.api.nvim_get_runtime_file("lua/lib", true)) do
      local normalized = vim.fs.normalize(dir)
      if normalized == lib .. "/lua/lib" then
        reached = reached + 1
      end
      if normalized:find(base .. "/my/lua/lib", 1, true) then
        stray = true
      end
    end
  end)

  vim.o.runtimepath = saved_rtp
  package.path = saved_path
  vim.env.LIB_NVIM_PATH = saved_env
  vim.fn.delete(base, "rf")

  ok(ran, "resolve() ran without raising: " .. tostring(err))
  eq(found, lib, "the checkout with a comma in its name is found")
  eq(reached, 1, "and the runtimepath reaches its lua/lib folder (one entry, not two halves)")
  ok(not stray, "nothing was added for the half before the comma")
end
