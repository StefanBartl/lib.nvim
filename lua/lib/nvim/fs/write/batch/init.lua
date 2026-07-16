---@module 'lib.nvim.fs.write.batch'
--- Write many files asynchronously and invoke one callback when all of them
--- have finished (success or failure). Built on `lib.nvim.fs.write.async`.
---
---   require("lib.nvim.fs.write.batch")({
---     { path = "/tmp/a.txt", content = "a" },
---     { path = "/tmp/b.txt", content = "b" },
---   }, function(all_ok, results)
---     -- results[i] corresponds to entries[i]
---   end)

require("lib.nvim.fs.write.batch.@types")

local write_async = require("lib.nvim.fs.write.async")

---@param entries { path: string, content: string }[]
---@param cb fun(all_ok: boolean, results: { path: string, ok: boolean, err: string|nil }[])
return function(entries, cb)
  local total = #entries

  if total == 0 then
    vim.schedule(function()
      cb(true, {})
    end)
    return
  end

  -- Results are written by index so their order matches `entries`, regardless
  -- of the order in which the individual writes complete.
  local results = {} ---@type { path: string, ok: boolean, err: string|nil }[]
  local remaining = total
  local all_ok = true

  for i = 1, total do
    local entry = entries[i]
    write_async(entry.path, entry.content, function(ok, err)
      results[i] = { path = entry.path, ok = ok, err = err }
      if not ok then
        all_ok = false
      end
      remaining = remaining - 1
      if remaining == 0 then
        cb(all_ok, results)
      end
    end)
  end
end
