---@module 'lib.nvim.terminal.ask'
--- A program in a Neovim terminal asks the Neovim it runs under: the Neovim half of `bin/nvim-ask`.
---
--- A git hook has no terminal to ask on (Git for Windows starts hooks with no `/dev/tty` at all, and
--- git gives every hook `/dev/null` as stdin), but a process started from a Neovim terminal carries
--- `$NVIM`, the server address of that Neovim. `bin/nvim-ask` sends the question there over RPC
--- (`--remote-expr`), Neovim shows it as a `lib.nvim.ui.dialog.ask` dialog, and the script fetches
--- the answer. Neovim never blocks: `start` returns an id at once, `poll` is asked again until the
--- answer is there.
---
--- RPC surface (what `bin/nvim-ask` calls through `luaeval`):
---   start(spec)  -> id          spec = { question = string|string[], choices = string[],
---                                        title?, default?, timeout_ms? }
---   poll(id)     -> ""          still open
---                   "=<choice>" answered with that choice
---                   "!cancel"   dismissed, or not answered within `timeout_ms`
---                   "!gone"     unknown id (answered and fetched already, or Neovim restarted)
---   cancel(id)                  the asker gave up: the question is dropped (not asked if still queued)
---   script()     -> path        absolute path of `bin/nvim-ask`, for callers that are not on PATH
---
--- The question and the choices are data: they reach the dialog as strings, never as Ex text.
--- A question nobody polls for `STALE_MS` (its asker was killed) is dropped like a cancelled one.

local M = {}

local uv = vim.uv or vim.loop

--- An open question whose asker has not polled for this long is dropped.
M.STALE_MS = 15000

---@class Lib.Terminal.AskEntry
---@field state "open"|"done"|"dropped"
---@field answer string?
---@field touched number  uv.now() of the last poll (or of start)

---@type table<string, Lib.Terminal.AskEntry>
local entries = {}
local seq = 0

---@param v any
---@return boolean
local function is_text(v)
  return type(v) == "string" and v ~= ""
end

---Validate a spec from the wire; returns the question as one string, or nil and why.
---@param spec any
---@return string?, string?
local function question_of(spec)
  if type(spec) ~= "table" then
    return nil, "spec must be a table"
  end
  local q = spec.question
  if type(q) == "table" then
    for _, line in ipairs(q) do
      if type(line) ~= "string" then
        return nil, "question lines must be strings"
      end
    end
    q = table.concat(q, "\n")
  end
  if not is_text(q) then
    return nil, "question must be a non-empty string"
  end
  if type(spec.choices) ~= "table" or #spec.choices < 1 or #spec.choices > 9 then
    return nil, "choices must be a list of 1 to 9 labels"
  end
  for _, c in ipairs(spec.choices) do
    if not is_text(c) then
      return nil, "choices must be non-empty strings"
    end
  end
  return q
end

---Ask `spec.question` with `spec.choices`; returns the id to poll. A bad spec raises (the caller
---sees the message as the `--remote-expr` result and gives up).
---@param spec { question: string|string[], choices: string[], title?: string, default?: integer, timeout_ms?: integer }
---@return string id
function M.start(spec)
  local question, err = question_of(spec)
  if not question then
    error("lib.nvim.terminal.ask: " .. err, 0)
  end
  seq = seq + 1
  local id = tostring(seq)
  ---@type Lib.Terminal.AskEntry
  local entry = { state = "open", touched = uv.now() }
  entries[id] = entry
  local choices = vim.deepcopy(spec.choices)
  local default = tonumber(spec.default)
  vim.schedule(function()
    local ok, ask_err = pcall(require("lib.nvim.ui.dialog").ask, {
      question = question,
      choices = choices,
      default = default,
      title = is_text(spec.title) and spec.title or nil,
      max_wait_ms = tonumber(spec.timeout_ms),
      abandoned = function()
        return entry.state == "dropped" or (uv.now() - entry.touched) > M.STALE_MS
      end,
      on_answer = function(choice)
        if entry.state ~= "open" then
          return
        end
        entry.state = "done"
        entry.answer = type(choice) == "string" and choice or nil
      end,
    })
    if not ok then
      entry.state = "done"
      entry.answer = nil
      vim.notify("lib.nvim.terminal.ask: " .. tostring(ask_err), vim.log.levels.ERROR)
    end
  end)
  return id
end

---The state of question `id` (see the module doc); an answered one is forgotten once fetched.
---@param id string
---@return string
function M.poll(id)
  local entry = entries[tostring(id)]
  if not entry then
    return "!gone"
  end
  entry.touched = uv.now()
  if entry.state == "open" then
    return ""
  end
  entries[tostring(id)] = nil
  if entry.state == "done" and entry.answer then
    return "=" .. entry.answer
  end
  return "!cancel"
end

---The asker gave up on `id`: drop it (still queued: never asked).
---@param id string
---@return boolean known
function M.cancel(id)
  local entry = entries[tostring(id)]
  if not entry then
    return false
  end
  entry.state = "dropped"
  entries[tostring(id)] = nil
  return true
end

---Absolute path of the client script `bin/nvim-ask` (lib.nvim's root `/bin`), `/`-separated.
---@return string
function M.script()
  local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  local root = here:gsub("/lua/lib/nvim/terminal/ask%.lua$", "")
  return root .. "/bin/nvim-ask"
end

---Number of questions still tracked (open or answered but not fetched). For tests and health.
---@return integer
function M.count()
  local n = 0
  for _ in pairs(entries) do
    n = n + 1
  end
  return n
end

return M
