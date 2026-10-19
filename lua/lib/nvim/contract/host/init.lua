---@module 'lib.nvim.contract.host'
---@brief The persistent engine process: a machine contract over a line protocol on stdin and stdout.
---@description
--- `host.make{ api = api }` returns the host of ONE plugin's contract (`lib.nvim.contract.api`). Moved here from
--- `tasks_nvim.host` (tasks.nvim@6bc8d99). `nvim --headless -u NONE -l scripts/<plugin>-host.lua` (the script is the
--- template `templates/contract_host.lua`) does what a command line `call <method>` does, many times in one process:
--- the modules are loaded once and a scan of a source that did not change can be answered from the plugin's caches,
--- so a question costs milliseconds and not a process start. Nothing else changes: the answers are the documents of
--- `api.call`, byte for byte.
---
--- The protocol, one line each way, UTF-8, `\t` separates the fields, a line ends with `\n`:
---
---     host -> client   `ready\t<PROTOCOL>`             once, when the modules are loaded
---     client -> host   `<id>\t<method>\t<params>`      `<id>` digits (at most 15); `<method>` runs to the next tab (or
---                                                      the end of the line); `<params>` is the JSON of the request
---                                                      (empty: none); no line break may be in it
---     host -> client   `<id>\t<document>`              the document `api.call` answers, on one line
---
--- The host ends when its input ends. A request is answered completely before the next is read (the plugin's lock is
--- not re-entrant, and the client keeps one question in flight). A line that is not a request is told on stderr and
--- skipped (nothing to answer it with: it has no id); an empty line (or one that is only the `\r` of a Windows line
--- ending) is skipped silently. A line that is too long is skipped as well, but when it starts with an id the client
--- gets an error document (`payload_too_large`) for it, so it never waits for ever. A method or parameter that the
--- dispatcher does not accept is the dispatcher's own error document, and the whole method name is judged there: the
--- host does not cut it at a character (`list-all` is asked for as `list-all`, never as `list`).
---
--- On Windows the host reads `io.stdin` in binary mode: in text mode the C runtime ends the stream at the first raw
--- `0x1A` byte, so the host would drop every later request and exit with nothing told. A line is cut at `\n` only; the
--- `\r` of a Windows line ending is stripped from the request.
---
--- A non-flat method carries its parameters under `params`: the host wraps them (`{"params": <params>}`); a flat
--- method (the write door) gets the text as it is. The text is spliced, not parsed: a `<params>` such as
--- `{},"schema":9` adds a top-level field of its own, which the dispatcher judges like any other. It is the client that
--- writes the whole line, so that is no way to anything it could not ask for anyway.
---
--- Limits: a line is read whole before its length is judged (`file:read("l")`), so a client that sends an endless line
--- without a line break holds memory until it stops; the client is the app that started the host, and is trusted
--- that far. When the output cannot be written any more (the client went away) the host ends.
---
---```lua
--- -- <plugin>/host.lua
--- local api = require("<plugin>.api")
--- return require("lib.nvim.contract.host").make({ api = api })
---
--- -- scripts/<plugin>-host.lua (the template does the rest)
--- require("<plugin>.host").serve(io.stdin, io.stdout)
---```
---
--- Not its job: finding the source or lib.nvim (the script), the document (`contract.api`, the plugin).

require("lib.nvim.contract.host.@types")

local M = {}

---The longest request line is a request plus the id and the method.
M.LINE_SLACK = 256

---`_O_BINARY` of the C runtime.
local O_BINARY = 0x8000

---Windows opens `io.stdin` in text mode, where a raw `0x1A` byte is the end of the file: everything after it is lost
---and the host would end without a word. Binary mode reads every byte (a `\r` stays and is stripped by `handle`).
---Only the process's own stdin is touched (a table in a spec, a file the caller opened, are not); elsewhere it is a no-op.
---@param input any
---@return boolean switched
function M.binary_stdin(input)
  if input ~= io.stdin or type(jit) ~= "table" or jit.os ~= "Windows" then
    return false
  end
  local loaded, ffi = pcall(require, "ffi")
  if not loaded then
    return false
  end
  -- declared once per process; if something declared it already (or the declaration is refused) the call below still
  -- decides, so a failing `cdef` is not a reason to leave the stream in text mode
  pcall(ffi.cdef, "int _setmode(int fd, int mode);")
  local called, previous = pcall(function()
    return ffi.C._setmode(0, O_BINARY)
  end)
  -- `_setmode` answers the previous mode, or -1 when it refuses
  return called and previous ~= -1
end

---@param cfg Lib.Contract.HostConfig
---@return Lib.Contract.Host
function M.make(cfg)
  if type(cfg) ~= "table" then
    error("contract.host.make needs a table", 2)
  end
  local api = cfg.api
  if
    type(api) ~= "table"
    or type(api.call) ~= "function"
    or type(api.minimal_error) ~= "function"
    or type(api.METHODS) ~= "table"
  then
    error("contract.host.make: api must be a lib.nvim.contract.api instance", 2)
  end
  local protocol = cfg.protocol or 1
  if type(protocol) ~= "number" or protocol < 1 or protocol ~= math.floor(protocol) then
    error("contract.host.make: protocol must be a whole number from 1", 2)
  end
  if
    cfg.call_opts ~= nil
    and type(cfg.call_opts) ~= "table"
    and type(cfg.call_opts) ~= "function"
  then
    error("contract.host.make: call_opts must be a table or a function", 2)
  end

  local host = { PROTOCOL = protocol }

  ---The longest line that is read: a request is at most `api.MAX_REQUEST_BYTES`, plus the id and the method.
  ---@return integer
  function host.max_line_bytes()
    return api.MAX_REQUEST_BYTES + M.LINE_SLACK
  end

  ---The options of one `api.call`: the plugin's (a table, or a function that builds them per request).
  ---@return table
  local function call_opts()
    local opts = cfg.call_opts
    if type(opts) == "function" then
      opts = opts()
    end
    return type(opts) == "table" and opts or {}
  end

  ---Answer one request line.
  ---@param line string
  ---@return string|nil reply   # `<id>\t<document>`, or nil for a line that is not a request.
  function host.handle(line)
    if type(line) ~= "string" then
      return nil
    end
    line = line:gsub("\r$", "")
    -- the method runs to the next tab (or the end of the line): the dispatcher judges the whole name, so a name with a
    -- dash or a dot is neither cut short nor answered as another method
    local id, method, params = line:match("^(%d+)\t([^\t]+)\t?(.*)$")
    if not id or #id > 15 then
      return nil
    end
    -- the dispatcher echoes an unknown name in its refusal: a name that cannot be shown on a terminal (control
    -- characters, the C1 range, more than 64 bytes) is refused without being echoed
    if #method > 64 or method:find("[%c\127]") or method:find("\194[\128-\159]") then
      return id
        .. "\t"
        .. api.minimal_error(
          "not_found",
          "unknown method (a name that is not printable or is too long)"
        )
    end
    local request = nil
    if params ~= "" then
      local def = api.METHODS[method]
      -- a flat method (the write door) carries its fields at the top of the request; the others carry theirs under
      -- `params`
      request = (type(def) == "table" and def.flat) and params or ('{"params":' .. params .. "}")
    end
    local called, text = pcall(function()
      return (api.call(method, request, call_opts()))
    end)
    if not called or type(text) ~= "string" then
      text = api.minimal_error("internal", "the host failed on this request")
    end
    -- A document is one line: a line break in it could only be whitespace between tokens.
    text = text:gsub("[\r\n]", " ")
    return id .. "\t" .. text
  end

  ---Serve until `input` ends (or `output` can no longer be written).
  ---@param input file*   # Lines in (`io.stdin`).
  ---@param output file*  # Lines out (`io.stdout`).
  ---@param warn? fun(text: string)
  function host.serve(input, output, warn)
    warn = warn or function(text)
      io.stderr:write(text .. "\n")
    end

    ---@param text string
    ---@return boolean written
    local function send(text)
      local wrote = output:write(text .. "\n")
      if not wrote then
        return false
      end
      output:flush()
      return true
    end

    M.binary_stdin(input)
    if not send("ready\t" .. host.PROTOCOL) then
      return
    end
    while true do
      local line = input:read("l")
      if line == nil then
        return
      end
      if #line > host.max_line_bytes() then
        warn("host: a line of " .. #line .. " bytes is skipped")
        -- the client is waiting for an answer to this id: it gets one
        local id = line:sub(1, 16):match("^(%d+)\t")
        if id then
          local limit = ("a request is at most %d bytes"):format(api.MAX_REQUEST_BYTES)
          if not send(id .. "\t" .. api.minimal_error("payload_too_large", limit)) then
            return
          end
        end
      else
        local reply = host.handle(line)
        if reply then
          if not send(reply) then
            return
          end
        elseif line ~= "" and line ~= "\r" then
          -- (`handle` strips one trailing `\r`: a blank line of a CRLF client is as empty as `""`)
          warn("host: a line that is not a request is skipped")
        end
      end
    end
  end

  return host --[[@as Lib.Contract.Host]]
end

return M
