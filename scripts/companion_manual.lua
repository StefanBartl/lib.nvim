-- scripts/companion_manual.lua -- a manual check of lib.nvim.companion with a REAL terminal window.
--
-- From the repo root:
--   nvim --headless -u NONE -l scripts/companion_manual.lua
-- or from an interactive nvim with lib.nvim on the rtp:
--   :luafile scripts/companion_manual.lua
--
-- Opens a companion in the platform's terminal (Windows Terminal on Windows), pushes a few
-- updates, triggers an action from the companion side over RPC (as its keymap would), changes the
-- title and closes it. Prints one line per step; the window opens and closes by itself. Set
-- COMPANION_MANUAL_KEEP=1 to leave the window open for a look (q closes it; the script then waits
-- for that).

vim.opt.rtp:prepend(vim.fn.getcwd())
local companion = require("lib.nvim.companion")

local function say(fmt, ...)
  io.stdout:write(("[companion] " .. fmt):format(...), "\n")
  io.stdout:flush()
end

local function pause(ms)
  vim.wait(ms, function()
    return false
  end, 10)
end

local got = {}
local closed = false
local page = 0

local function render(h)
  local lines = { ("Memory  page %d"):format(page), "" }
  local hls = { { line = 0, col_start = 0, col_end = 6, group = "Title" } }
  for i = 0, 7 do
    local addr = page * 128 + i * 16
    local bytes = {}
    for j = 0, 15 do
      bytes[#bytes + 1] = ("%02x"):format((addr + j) % 256)
    end
    lines[#lines + 1] = ("%08x  %s"):format(addr, table.concat(bytes, " "))
    hls[#hls + 1] = { line = i + 2, col_start = 0, col_end = 8, group = "Comment" }
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "n/p: page   a: jump (asks for an address)   q: close"
  h:update(lines, hls)
end

local h, err = companion.open({
  title = "Memory",
  lines = { "starting ..." },
  filetype = "text",
  actions = {
    page = function(delta)
      page = page + delta
      got[#got + 1] = "page " .. delta
      say("action page(%d) -> page %d", delta, page)
    end,
    jump = function(addr)
      got[#got + 1] = "jump " .. tostring(addr)
      say("action jump(%s)", tostring(addr))
    end,
  },
  keys = { n = { "page", 1 }, p = { "page", -1 }, a = { "jump", prompt = "Address: " } },
  on_close = function()
    closed = true
    say("on_close")
  end,
})
if not h then
  say("open failed: %s", tostring(err))
  vim.cmd("cquit 1")
end
say("opened handle %d (server %s)", h.id, vim.v.servername)

if not vim.wait(15000, function()
  return h:is_attached() or not h:is_open()
end, 20) then
  say("the companion did not attach within 15 s")
  h:close()
  vim.cmd("cquit 1")
end
if not h:is_open() then
  say("the companion closed before it attached")
  vim.cmd("cquit 1")
end
say("attached: channel %d, companion server %s", h.chan, tostring(h.servername))

for _ = 1, 3 do
  render(h)
  page = page + 1
  pause(600)
end
say("pushed 3 updates")

-- a key in the companion, done the way its keymap does it
local ok_rpc, rpc_err = pcall(
  vim.rpcrequest,
  h.chan,
  "nvim_exec_lua",
  "require('lib.nvim.companion.client').send('page', { -1 })",
  {}
)
say("triggered the n/p action from the companion side: %s", ok_rpc and "ok" or tostring(rpc_err))
vim.wait(3000, function()
  return #got >= 1
end, 20)
say("actions received in the main instance: %s", vim.inspect(got))
render(h)
h:set_title("Memory (page " .. page .. ")")
pause(800)

if vim.env.COMPANION_MANUAL_KEEP == "1" then
  say("COMPANION_MANUAL_KEEP=1: press q in the companion window to end")
  vim.wait(600000, function()
    return closed
  end, 50)
else
  h:close()
end
say(
  "closed: handle open=%s on_close=%s handles left=%d",
  tostring(h:is_open()),
  tostring(closed),
  #companion.handles()
)
say("DONE")
vim.cmd("qa!")
