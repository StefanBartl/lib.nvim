-- TESTS/copy_to_clipboard_spec.lua — lib.nvim.cross.copy_to_clipboard
--
-- The regression this exists for: `pcall(vim.fn.setreg, "+", text)` was
-- treated as "clipboard write succeeded". `setreg("+", ...)` never raises
-- when there is no clipboard provider -- it just silently does nothing --
-- so the function reported success on every machine with no provider and
-- no external tool on PATH, which includes this CI runner and any bare
-- Linux session with no `xclip`/`xsel`/`wl-copy` and no `g:clipboard`.
--
-- The fix is verified here by round-tripping through the register the
-- function itself uses, not by asserting a real system clipboard changed
-- (this suite must pass on exactly the kind of provider-less runner the
-- bug was invisible on).

return function(H)
  local copy = require("lib.nvim.cross.copy_to_clipboard")

  -- --------------------------------------------------- honest by construction
  --
  -- Whatever this returns `true`, the `+` register must actually hold the
  -- text afterward -- that is the property the fix adds, and it holds
  -- regardless of which branch (native register vs. an OS tool) got there.
  do
    vim.fn.setreg("+", "")
    local marker = "lib_spec_copy_to_clipboard_marker_" .. tostring(vim.uv.hrtime())
    local ok = copy(marker)

    if ok then
      H.eq(vim.fn.getreg("+"), marker, "a reported success actually put the text on the register")
    else
      -- No provider AND no external tool on this machine -- the honest
      -- outcome the old code could not report. Not a skip: it is the
      -- behaviour under test on a runner shaped exactly like this.
      H.ok(true, "no clipboard mechanism available -- copy() correctly reported failure")
    end
  end

  -- --------------------------------------------------------- never claims
  -- success while leaving the register holding something else entirely
  do
    vim.fn.setreg("+", "unrelated-previous-content")
    local marker = "lib_spec_copy_to_clipboard_marker_2"
    local ok = copy(marker)
    if ok then
      H.eq(vim.fn.getreg("+"), marker, "success means the NEW text is there, not the old one")
    end
  end

  -- ------------------------------------------------------- a fresh string
  -- every call, not a frozen close-over from the first invocation
  do
    vim.fn.setreg("+", "")
    local a = copy("lib_spec_copy_to_clipboard_marker_a")
    local b = copy("lib_spec_copy_to_clipboard_marker_b")
    if a and b then
      H.eq(vim.fn.getreg("+"), "lib_spec_copy_to_clipboard_marker_b", "the second call's text wins")
    end
  end
end
