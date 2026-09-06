---@module 'lib.nvim.core.simple_echo'
--- Small helper wrapper to simplify common echo patterns.
--- Returns a single function that echoes messages via vim.api.nvim_echo.

--- Echo a message with optional highlight and error flag.
--- @param msg string main message text
--- @param hl string|nil highlight group name or nil
--- @param is_error boolean|nil treat as error
--- @return integer|string message id returned by nvim_echo or -1 if nothing shown
return function(msg, hl, is_error)
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
