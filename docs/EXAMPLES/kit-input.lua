-- docs/EXAMPLES/kit-input.lua
--
-- Module:   lib.nvim.ui.kit.input (lib.nvim.ui.kit.input)
-- Scenario: a single-line, themed prompt -- a drop-in replacement for
--           vim.ui.input() that matches whatever kit theme the rest of the
--           plugin uses. Opens focused in insert mode; <CR> submits,
--           <Esc> cancels (on_cancel fires, on_submit does not).

local kit = require("lib.nvim.ui.kit")

kit.input({
  prompt = "New branch name",
  default = "feature/",
  on_submit = function(text)
    vim.notify("branch: " .. text)
  end,
  on_cancel = function()
    vim.notify("cancelled", vim.log.levels.WARN)
  end,
})

-- `expand_env = true` runs the submitted line through
-- lib.nvim.cross.fs.expand_path (~, $VAR, ${VAR}, %VAR% on Windows) before
-- on_submit sees it -- opt in whenever the prompt is asking for a path:
kit.input({
  prompt = "Export to",
  default = "~/exports/",
  expand_env = true,
  on_submit = function(path)
    -- `path` has already been through expand_path; ~ and env vars are gone.
    require("myplugin").export_to(path)
  end,
})

-- `secret = true` masks the input as you type -- a vim.fn.inputsecret()
-- replacement. Each character is concealed behind `mask` (default "*"); the
-- real text still reaches on_submit, it's just never echoed on screen (see
-- lib.nvim.ui.kit.input's module doc for what this does and doesn't protect
-- against).
kit.input({
  prompt = "Registry password",
  secret = true,
  on_submit = function(password)
    require("myplugin").login(password)
  end,
})

-- override the placeholder character:
kit.input({ prompt = "PIN", secret = true, mask = "•", on_submit = function(pin) end })

-- `completion = "file"` wires <Tab> to real ins-completion (vim.fn.complete())
-- over vim.fn.getcompletion() candidates -- a `vim.fn.input(..., completion =
-- "file")` replacement. <Tab>/<S-Tab> cycle the popup once it's open; <CR>
-- accepts the highlighted candidate first, then submits on a second <CR>.
-- Accepts any getcompletion() type, not just "file" (e.g. "dir", "buffer").
kit.input({
  prompt = "Path to executable",
  completion = "file",
  on_submit = function(path)
    require("myplugin").set_executable(path)
  end,
})

-- `lib.nvim.ui.kit.prompt` (see kit-prompt.lua) wraps this same component
-- for the "ask a free-text question" half of a yes/no-or-text prompt --
-- reach for `kit.input` directly when you only ever need the text case.
