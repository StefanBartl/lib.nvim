-- TESTS/autocmd_docs_spec.lua — lib.nvim.bindings.autocmd.docs
--
-- Both cases here are "silently writes a wrong document" failures, which is
-- the one outcome this generator must not have: a page that omits things
-- without saying so is worse than no page, because the reader takes the table
-- for the whole list.

return function(H)
  local eq, ok = H.eq, H.ok

  local docs = require("lib.nvim.bindings.autocmd.docs")

  ---@param dir string
  ---@return string[]
  local function read_all(dir)
    local out = {}
    for _, name in ipairs(vim.fn.readdir(dir) or {}) do
      for line in io.lines(dir .. "/" .. name) do
        out[#out + 1] = line
      end
    end
    return out
  end

  ---Register an autocmd from a file that really lives under `root`, so its
  ---recorded `src` is an absolute path the way it is in a real session (under
  ---`nvim -l` the spec's own source is relative, which is exactly what the
  ---filter below cannot match).
  ---@param root string
  ---@param body string
  ---@return nil
  local function register_from(root, body)
    vim.fn.mkdir(root .. "/lua/specplugin", "p")
    local file = root .. "/lua/specplugin/init.lua"
    local fd = assert(io.open(file, "w"))
    fd:write(body)
    fd:close()
    dofile(file)
  end

  -- --------------------------------------------------- a Windows-shaped root
  -- Every path this module compares is forward-slashed, and `r.src` is
  -- normalized on the way in -- but `opts.root` was not. A caller passing what
  -- `vim.fn.fnamemodify()` hands back (backslashes, on Windows) matched no
  -- record at all and got an empty document with no error.
  do
    local base = (vim.fn.tempname():gsub("\\", "/"))
    local out = base .. "/out"
    vim.fn.mkdir(out, "p")

    register_from(
      base,
      [[
        require("lib.nvim.bindings.autocmd").create("User", function() end, {
          group = "spec_docs_group",
          pattern = "SpecDocsEvent",
          desc = "spec docs marker",
        })
      ]]
    )

    local written_ok, err = docs.write({ dir = out, root = base:gsub("/", "\\") })
    eq(written_ok, true, "write() succeeds for a backslashed root: " .. tostring(err))

    local body = table.concat(read_all(out), "\n")
    ok(
      body:find("spec docs marker", 1, true) ~= nil,
      "a backslashed root still matches the records it owns"
    )

    vim.api.nvim_del_augroup_by_name("spec_docs_group")
  end

  -- ------------------------------------------------- dispatchers are listed
  -- A dispatcher is ONE autocmd fanning out to N handlers, so the record table
  -- can only ever show a single row for it. Without the handler table below it,
  -- a page would claim one listener where several are -- the same failure, one
  -- level down.
  do
    local base = (vim.fn.tempname():gsub("\\", "/"))
    local out = base .. "/out"
    vim.fn.mkdir(out, "p")

    register_from(
      base,
      [[
        local d = require("lib.nvim.bindings.autocmd.dispatcher").new({
          event = "User",
          name = "spec_docs_dispatcher",
          group = "spec_docs_dispatcher",
          key = function(ev) return ev.match end,
        })
        d.register("SpecKey", {
          load = function() end,
          owner = "spec",
          desc = "spec dispatched handler",
        })
        d.attach()
      ]]
    )

    local written_ok, err = docs.write({ dir = out, root = base })
    eq(written_ok, true, "write() succeeds with a dispatcher registered: " .. tostring(err))

    local body = table.concat(read_all(out), "\n")
    ok(body:find("Dispatched handlers", 1, true) ~= nil, "the dispatcher section is rendered")
    ok(
      body:find("spec dispatched handler", 1, true) ~= nil,
      "a handler's desc reaches the page, not just the dispatcher's own autocmd"
    )
    ok(body:find("`SpecKey`", 1, true) ~= nil, "the handler's key is shown as its scope")

    vim.api.nvim_del_augroup_by_name("spec_docs_dispatcher")
  end
end
