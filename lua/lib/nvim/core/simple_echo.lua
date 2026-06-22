---@module 'lib.nvim.core.simple_echo'
-- Small helper wrapper to simplify common echo patterns.
-- This module returns a single function that echoes messages using vim.api.nvim_echo.
-- It preallocates a single-element chunks array to avoid reallocations when used frequently.
--
--[[                    USAGE:
		Variant 1: Calling a require function and calling a function on one line
		  require("lib.nvim.core.simple_echo")("All done.", nil, false)

		Variant 2: store a require function in a variable
		  local simple_echo = require("lib.nvim.core.simple_echo")
		  simple_echo("All done.", nil, false)
		  simple_echo("File not found.", "WarningMsg", true)
--]]


--- Echo a message with optional highlight and error flag.
--- @param msg string main message text
--- @param hl string|nil highlight group name or nil
--- @param is_error boolean|nil treat as error
--- @return integer|string message id returned by nvim_echo or -1 if nothing shown
return function(msg, hl, is_error)
  -- Preallocate a single-element chunks array to avoid repeated reallocations.
  ---@type EchoChunk[]
  local chunks = { [1] = { [1] = msg, [2] = hl } }

  -- Build opts table. If is_error is truthy, set err=true; otherwise leave nil to avoid emitting the key.
  local opts = {}
  if is_error then
    opts.err = true
  end

  -- Add the message to history (true). Return the message id to the caller.
  return vim.api.nvim_echo(chunks, true, opts)
end
