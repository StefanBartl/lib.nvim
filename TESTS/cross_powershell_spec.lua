-- TESTS/cross_powershell_spec.lua — lib.nvim.cross.powershell

return function(H)
  local eq = H.eq
  local escape = require("lib.nvim.cross.powershell").escape_single

  eq(escape("plain name.md"), "plain name.md", "plain text is untouched")
  eq(escape("it's"), "it''s", "the ASCII quote is doubled")
  for _, cp in ipairs({ 0x2018, 0x2019, 0x201A, 0x201B }) do
    local q = vim.fn.nr2char(cp)
    eq(escape("a" .. q .. "b"), "a" .. q .. q .. "b", ("U+%X is doubled"):format(cp))
  end
  eq(
    escape("\195\164\226\130\172 \226\128\156x\226\128\157"),
    "\195\164\226\130\172 \226\128\156x\226\128\157",
    "other multi-byte text stays"
  )
  eq(escape("'\226\128\153'"), "''\226\128\153\226\128\153''", "a mix is doubled quote by quote")
  eq(select("#", escape("x")), 1, "a single return value")

  if vim.fn.has("win32") == 1 and vim.fn.executable("powershell") == 1 then
    local name = "x\226\128\153; Write-Output INJECTED; \226\128\153"
    local res = vim
      .system({
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); Write-Output '" .. escape(
          name
        ) .. "'",
      }, { text = true })
      :wait()
    eq(
      (res.stdout or ""):gsub("\r?\n$", ""),
      name,
      "a real PowerShell reads the string back unchanged"
    )
  end
end
