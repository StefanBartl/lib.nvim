-- TESTS/support/data_classes_cases.lua -- the vendored copy of tasks-desktop's shared `areas.json` case list
--
-- tasks-desktop keeps one list of cases (ui/web/classes-cases.mjs) that its Rust hub and its web reader answer alike;
-- ui/web/classes-cases-dump.mjs prints it as JSON. lib.nvim keeps that list as a fixture
-- (TESTS/fixtures/data_classes_cases.json, one case per line) with a sidecar naming its source commit and its sha256
-- (TESTS/fixtures/data_classes_cases.source.json), so the spec runs without a checkout and without node. This module
-- is shared by the spec (reading the fixture, comparing it with a local checkout) and by
-- scripts/regen_data_classes_cases.lua (writing it).
--
-- A checkout is always read at its HEAD (`git cat-file`, into a temporary directory), never its working tree:
-- tasks-desktop is a shared checkout where another session may be halfway through the case list, and the sidecar
-- names a commit, so the fixture must be what that commit dumps.

local M = {}

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local tests = vim.fs.dirname(here)

M.FIXTURE = vim.fs.joinpath(tests, "fixtures", "data_classes_cases.json")
M.SOURCE = vim.fs.joinpath(tests, "fixtures", "data_classes_cases.source.json")
M.GENERATOR = "ui/web/classes-cases-dump.mjs"
--- What the dump reads: the generator and the case list, both under ui/web.
M.TREE = "ui/web"
M.REGENERATE =
  "nvim -n -i NONE --headless -u NONE -l scripts/regen_data_classes_cases.lua [--force] [tasks-desktop dir]"
--- A run of at least this many equal bytes is written as `<pair>*<count>;` in the fixture's hex.
M.MIN_RUN = 16

---@class lib.test.ClassesCase
---@field name string
---@field hex string The file of the case, hex-encoded; in the fixture runs are written `<pair>*<count>;`.
---@field refused boolean
---@field shows table<string, string> Area -> the class the reader must show for it.

---@param path string
---@return string|nil text
local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  -- the repository checks text out with LF (.gitattributes); a CRLF copy must not change the checksum
  return (text:gsub("\r\n", "\n"))
end

---@param path string
---@param content string
local function write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

--- The checkout of tasks-desktop to compare with: `TASKS_DESKTOP_DIR`, else a sibling of the current directory.
---@return string
function M.checkout_dir()
  local dir = vim.env.TASKS_DESKTOP_DIR
  if dir == nil or dir == "" then
    dir = vim.fs.joinpath(vim.fs.dirname(vim.fn.getcwd()), "tasks-desktop")
  end
  return dir
end

--- Expand the runs of a fixture hex (`20*5;` -> `2020202020`) and check that the result is plain hex.
---@param hex string
---@return string
function M.hex_expand(hex)
  local plain = hex:gsub("(%x%x)%*(%d+);", function(pair, count)
    return pair:rep(tonumber(count))
  end)
  if #plain % 2 ~= 0 or plain:find("[^%x]") then
    error("not a fixture hex: " .. hex:sub(1, 80), 2)
  end
  return plain
end

--- Write every run of at least MIN_RUN equal bytes as `<pair>*<count>;`; the rest stays as it is. The pairs are kept
--- as they are written (case included), so `hex_expand(hex_compress(h)) == h` byte for byte.
---@param hex string Plain hex.
---@return string
function M.hex_compress(hex)
  local out = {}
  local i, len, literal = 1, #hex, 1
  while i <= len do
    local pair = hex:sub(i, i + 1)
    local j = i + 2
    while hex:sub(j, j + 1) == pair do
      j = j + 2
    end
    local count = (j - i) / 2
    if count >= M.MIN_RUN then
      out[#out + 1] = hex:sub(literal, i - 1)
      out[#out + 1] = ("%s*%d;"):format(pair, count)
      literal = j
    end
    i = j
  end
  out[#out + 1] = hex:sub(literal)
  return table.concat(out)
end

--- The bytes of a case's file.
---@param hex string Fixture hex (runs allowed) or plain hex.
---@return string
function M.bytes(hex)
  return (
    M.hex_expand(hex):gsub("%x%x", function(pair)
      return string.char(tonumber(pair, 16))
    end)
  )
end

--- The case list as fixture text: a JSON array with one case per line and the keys in a fixed order, so the same
--- list always gives the same bytes (and the same sha256) and a changed case is a one-line diff. The hex is written
--- with its runs compressed, whether it came compressed (the fixture) or plain (a dump).
---@param cases lib.test.ClassesCase[]
---@return string
function M.encode(cases)
  local lines = {}
  for i, c in ipairs(cases) do
    local areas = vim.tbl_keys(c.shows or {})
    table.sort(areas)
    local shows = {}
    for _, area in ipairs(areas) do
      shows[#shows + 1] = vim.json.encode(area) .. ":" .. vim.json.encode(c.shows[area])
    end
    lines[#lines + 1] = ('{"name":%s,"hex":%s,"refused":%s,"shows":{%s}}%s'):format(
      vim.json.encode(c.name),
      vim.json.encode(M.hex_compress(M.hex_expand(c.hex))),
      c.refused == true and "true" or "false",
      table.concat(shows, ","),
      i < #cases and "," or ""
    )
  end
  return "[\n" .. table.concat(lines, "\n") .. "\n]\n"
end

--- The sidecar text for a fixture text.
---@param source { repo: string, commit: string, count: integer, sha256: string }
---@return string
function M.encode_source(source)
  return table.concat({
    "{",
    '  "repo": ' .. vim.json.encode(source.repo) .. ",",
    '  "commit": ' .. vim.json.encode(source.commit) .. ",",
    '  "generator": ' .. vim.json.encode(M.GENERATOR) .. ",",
    '  "cases": ' .. tostring(source.count) .. ",",
    '  "sha256": ' .. vim.json.encode(source.sha256) .. ",",
    '  "regenerate": ' .. vim.json.encode(M.REGENERATE),
    "}",
    "",
  }, "\n")
end

--- Read a fixture and its sidecar (default: the vendored ones).
---@param fixture_path? string
---@param source_path? string
---@return string|nil text The fixture text (LF line endings).
---@return lib.test.ClassesCase[]|string cases The cases, or why they could not be read.
---@return table|nil source The decoded sidecar.
function M.read_fixture(fixture_path, source_path)
  fixture_path = fixture_path or M.FIXTURE
  source_path = source_path or M.SOURCE
  local text = read(fixture_path)
  if text == nil then
    return nil, "cannot read " .. fixture_path
  end
  local source_text = read(source_path)
  if source_text == nil then
    return nil, "cannot read " .. source_path
  end
  return text, vim.json.decode(text), vim.json.decode(source_text)
end

---@param dir string
---@param args string[]
---@param opts? vim.SystemOpts
---@return vim.SystemCompleted
local function git(dir, args, opts)
  return vim
    .system(vim.list_extend({ "git", "-C", dir }, args), opts or { text = true })
    :wait(30000)
end

--- The checkout's HEAD, nil when `dir` is not a git checkout.
---@param dir string
---@return string|nil
function M.head(dir)
  local res = git(dir, { "rev-parse", "--verify", "-q", "HEAD^{commit}" })
  if res.code ~= 0 then
    return nil
  end
  return vim.trim(res.stdout or "")
end

--- Whether the checkout's HEAD contains `commit` (`merge-base --is-ancestor`, exit 0). Only then can it say that a
--- fixture made from `commit` lags behind: an older checkout, one on a diverged branch, or one that does not have
--- the commit at all knows nothing about it.
---@param dir string
---@param commit string
---@return boolean contains
---@return string|nil why Why not.
function M.contains(dir, commit)
  local head = M.head(dir)
  if head == nil then
    return false, dir .. " is not a git checkout"
  end
  local res = git(dir, { "merge-base", "--is-ancestor", commit, "HEAD" })
  if res.code == 0 then
    return true
  elseif res.code == 1 then
    return false,
      ("HEAD %s of %s does not contain %s (the checkout is older or on a diverged branch)"):format(
        head,
        dir,
        commit
      )
  end
  return false,
    ("%s does not know %s (git exit %d: %s)"):format(
      dir,
      commit,
      res.code,
      vim.trim(res.stderr or "")
    )
end

--- Whether the files the dump reads (M.TREE) have uncommitted changes to tracked files. Untracked files do not count.
---@param dir string
---@return boolean
function M.tracked_changes(dir)
  local res = git(dir, { "status", "--porcelain", "--untracked-files=no", "--", M.TREE })
  return res.code == 0 and vim.trim(res.stdout or "") ~= ""
end

--- Copy M.TREE as committed at HEAD into a new temporary directory (`git cat-file --batch`, nothing in the checkout
--- is touched: no index, no worktree).
---@param dir string
---@return string|nil tmp The directory (holding `ui/web/...`); the caller deletes it.
---@return string|nil why
function M.export_head(dir)
  local ls = git(dir, { "ls-tree", "-r", "-z", "--name-only", "HEAD", "--", M.TREE })
  if ls.code ~= 0 then
    return nil, "git ls-tree failed: " .. vim.trim(ls.stderr or "")
  end
  local paths = vim.split(ls.stdout or "", "\0", { plain = true, trimempty = true })
  if #paths == 0 then
    return nil, ("HEAD of %s has no %s"):format(dir, M.TREE)
  end
  local input = {}
  for _, path in ipairs(paths) do
    input[#input + 1] = "HEAD:" .. path .. "\n"
  end
  local res = git(dir, { "cat-file", "--batch" }, { stdin = table.concat(input), text = false })
  if res.code ~= 0 then
    return nil, "git cat-file failed: " .. tostring(res.stderr)
  end
  local out = res.stdout or ""
  local tmp = vim.fn.tempname()
  local pos = 1
  for _, path in ipairs(paths) do
    local nl = out:find("\n", pos, true)
    local header = nl and out:sub(pos, nl - 1) or ""
    local kind, size = header:match("^%x+ (%a+) (%d+)$")
    if kind == nil then
      vim.fn.delete(tmp, "rf")
      return nil, ("git cat-file: unexpected header %q for %s"):format(header, path)
    end
    size = tonumber(size)
    if kind == "blob" then
      write(vim.fs.joinpath(tmp, path), out:sub(nl + 1, nl + size))
    end
    pos = nl + size + 2 -- the content, then one LF
  end
  return tmp
end

--- Run the dump in a tree that holds `ui/web` (an export, see M.export_head).
---@param tree string
---@return lib.test.ClassesCase[]|nil cases
---@return string|nil why
function M.dump(tree)
  if vim.fn.executable("node") == 0 then
    return nil, "node is not on PATH"
  end
  local res = vim
    .system({ "node", "web/classes-cases-dump.mjs" }, { cwd = vim.fs.joinpath(tree, "ui"), text = false })
    :wait(60000)
  if res.code ~= 0 then
    return nil, "the dump failed: " .. vim.trim(tostring(res.stderr))
  end
  local okd, cases = pcall(vim.json.decode, res.stdout)
  if not okd or type(cases) ~= "table" then
    return nil, "the dump is not JSON: " .. tostring(cases)
  end
  return cases
end

--- Dump the case list as committed at the checkout's HEAD.
---@param dir string
---@param runner? fun(tree: string): lib.test.ClassesCase[]|nil, string|nil The dump (default M.dump; tests pass a fake).
---@return lib.test.ClassesCase[]|nil cases
---@return string|nil why
function M.dump_head(dir, runner)
  local has = git(dir, { "cat-file", "-e", "HEAD:" .. M.GENERATOR })
  if has.code ~= 0 then
    return nil, ("HEAD of %s has no %s"):format(dir, M.GENERATOR)
  end
  local tmp, why = M.export_head(dir)
  if tmp == nil then
    return nil, why
  end
  local okr, cases, reason = pcall(runner or M.dump, tmp)
  vim.fn.delete(tmp, "rf")
  if not okr then
    return nil, "the dump raised: " .. tostring(cases)
  end
  return cases, reason
end

---@class lib.test.ClassesCasesCompare
---@field state "current"|"lags"|"n/a"
---@field reason string|nil For "n/a": why there is nothing to compare.
---@field head string|nil
---@field count integer|nil The number of cases at HEAD.

--- Compare a fixture with the case list committed at a checkout's HEAD. Says "lags" only when HEAD contains the
--- fixture's commit and dumps a different list; every other case (no checkout, an older or diverged checkout, a
--- commit it does not know, no node, a dump that fails) is "n/a" with the reason.
---@param dir string
---@param source { commit: string }
---@param text string The fixture text.
---@param runner? fun(tree: string): lib.test.ClassesCase[]|nil, string|nil
---@return lib.test.ClassesCasesCompare
function M.compare(dir, source, text, runner)
  local head = M.head(dir)
  if head == nil then
    return { state = "n/a", reason = "no tasks-desktop checkout at " .. dir }
  end
  local contains, why = M.contains(dir, source.commit)
  if not contains then
    return { state = "n/a", reason = why, head = head }
  end
  local live, reason = M.dump_head(dir, runner)
  if live == nil then
    return { state = "n/a", reason = reason, head = head }
  end
  return {
    state = M.encode(live) == text and "current" or "lags",
    head = head,
    count = #live,
  }
end

--- Rewrite a fixture and its sidecar from the case list committed at a checkout's HEAD. Refused when the checkout
--- does not contain the commit the current sidecar names (that would silently go back to an older list), unless
--- `force`.
---@param dir string
---@param opts? { force?: boolean, runner?: fun(tree: string): lib.test.ClassesCase[]|nil, string|nil, fixture?: string, source?: string }
---@return boolean ok
---@return string message
function M.regenerate(dir, opts)
  opts = opts or {}
  local fixture_path = opts.fixture or M.FIXTURE
  local source_path = opts.source or M.SOURCE
  local head = M.head(dir)
  if head == nil then
    return false, dir .. " is not a git checkout"
  end
  local old_text = read(source_path)
  if old_text ~= nil and not opts.force then
    local okd, old = pcall(vim.json.decode, old_text)
    if not okd or type(old) ~= "table" or type(old.commit) ~= "string" then
      return false, source_path .. " has no commit; pass --force to overwrite it"
    end
    local contains, why = M.contains(dir, old.commit)
    if not contains then
      return false,
        ("refusing to go back: the fixture comes from %s, and %s; update the checkout, or pass --force"):format(
          old.commit,
          why
        )
    end
  end
  local cases, reason = M.dump_head(dir, opts.runner)
  if cases == nil then
    return false, reason or "the dump gave nothing"
  end
  local text = M.encode(cases)
  write(fixture_path, text)
  write(
    source_path,
    M.encode_source({
      repo = "tasks-desktop",
      commit = head,
      count = #cases,
      sha256 = vim.fn.sha256(text),
    })
  )
  local note = ""
  if M.tracked_changes(dir) then
    note = (" (uncommitted changes under %s ignored)"):format(M.TREE)
  end
  return true, ("wrote %d cases from tasks-desktop@%s%s"):format(#cases, head, note)
end

return M
