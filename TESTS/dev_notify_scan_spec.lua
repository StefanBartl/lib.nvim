-- TESTS/dev_notify_scan_spec.lua — lib.nvim.dev.notify_scan: message call-site
-- detection across sibling repos.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("lib.nvim.dev.notify_scan")

  local root = vim.fn.tempname()
  local function write(rel, lines)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end

  write("alpha.nvim/lua/alpha/init.lua", {
    'vim.notify("plain warning", vim.log.levels.WARN)',
    "local notify = vim.notify",
    "vim.notify(msg, 4)",
    '-- vim.notify("commented out")',
    'vim.api.nvim_echo({ { "echoed\\nline" } }, true, {})',
    'print("hello")',
    'local n = require("lib.nvim.notify").create("[alpha]")',
    'local level = require("lib.nvim.notify").resolve_log_level("warn")',
  })
  write("alpha.nvim/TESTS/skipped_spec.lua", { 'vim.notify("in a test")' })
  write("lib.nvim/lua/lib/x.lua", { 'vim.notify("excluded repo")' })
  write("notaplugin/readme.txt", { "vim.notify('no lua dir')" })

  local findings = scan.scan(root)
  vim.fn.delete(root, "rf")

  eq(#findings, 6, "commented, test, excluded-repo and non-plugin lines are ignored")
  local by_line = {}
  for _, f in ipairs(findings) do
    by_line[f.line] = f
    eq(f.repo, "alpha.nvim", "findings carry their repo")
  end

  eq(by_line[1].kind, "notify", "vim.notify is a notify call")
  eq(by_line[1].level, "WARN", "a spelled-out level is read")
  eq(by_line[1].text, "plain warning", "the literal head is captured")
  ok(not by_line[1].dynamic, "a literal argument is not dynamic")
  eq(by_line[2].kind, "bound", "a load-time binding of vim.notify is flagged")
  ok(by_line[3].dynamic, "a variable argument marks a wrapper")
  eq(by_line[3].level, "ERROR", "a numeric level is mapped")
  eq(by_line[5].kind, "echo", "nvim_echo is found")
  ok(by_line[5].multiline, "a literal with \n is multiline")
  eq(by_line[6].kind, "print", "print is found")
  eq(by_line[7].kind, "lib_notify", "lib.nvim.notify usage is found")
  eq(by_line[8], nil, "importing only resolve_log_level is not a notifier")

  local summary = scan.summarize(findings)
  eq(#summary, 1, "one row per repo")
  eq(summary[1].total, 6, "totals add up")
  eq(summary[1].bound, 1, "bound bindings are counted")

  ok(#scan.lines(root) >= 2, "lines() renders at least the table header")
end
