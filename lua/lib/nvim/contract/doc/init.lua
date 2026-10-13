---@module 'lib.nvim.contract.doc'
---@brief The documents of a machine contract: the head every one starts with, `seal`, `encode`, the error document.
---@description
--- `doc.new{ plugin, schema, ... }` returns the document builder of ONE plugin's contract (`tasks-export/1`,
--- `rules-export/1`). Moved here from the head/seal/encode part of `tasks_nvim.contract` (tasks.nvim@921a0c4); what
--- a document CONTAINS (snapshot, list, a rule) stays with the plugin.
---
--- Every document starts with the same head (`schema`, `plugin`, `kind`, `generated_at`, `<scope_key>.id`, `engine`).
--- A document that comes from a scan is sealed with `rev` (what the source looked like) and `digest` (the hash of the
--- content WITHOUT `generated_at` and `engine`: two runs on an unchanged source have the same digest, whenever and by
--- whichever build of the engine they ran).
---
--- Rules the documents keep:
---  - **no path of this machine**: `relative`, `safe_path` and `redact` turn paths into source-relative ones, an
---    absolute one into `<external>/<name>`, the root inside a message into the placeholder (`<vault>`);
---  - **a document is at most `MAX_DOC_BYTES`** (8 MiB); a bigger one is the error `payload_too_large`, never a
---    cut-off document; an error document is exempt (the limit must never keep a client from being told why);
---  - the bytes are canonical (`lib.nvim.json.canonical`): same document, same bytes.
---
--- Seams for specs and golden files, read at CALL time so a spec can replace them on the instance: `clock`
--- (`generated_at`), `engine_info` (`engine`), `MAX_DOC_BYTES`. A plugin that exposes the seams on its own module
--- forwards them: `d.clock = function() return M.clock() end`.
---
---```lua
--- local d = require("lib.nvim.contract.doc").new({
---   plugin = "rules.nvim", schema = 1, scope_key = "source", engine_version = "0.1.0",
---   plugin_root = plugin_root,
--- })
--- local doc = d.head("rules.hello", root)
--- doc.rules = rules
--- local text, err = d.encode(d.seal(doc, d.rev_of(lines)))
---```
---
--- Not its job: what a document contains, parsing a request and mapping an error to a code (`contract.api`).

require("lib.nvim.contract.doc.@types")

local json = require("lib.nvim.json.canonical")
local etag = require("lib.nvim.fs.etag")

local M = {}

---@param s string
---@return string
local function lower_slash(s)
  return (s:gsub("\\", "/"))
end

---A document is never bigger than this unless the plugin says so.
M.DEFAULT_MAX_DOC_BYTES = 8 * 1024 * 1024

---@param cfg Lib.Contract.DocConfig
---@return Lib.Contract.Doc
function M.new(cfg)
  if type(cfg) ~= "table" then
    error("contract.doc.new needs a table", 2)
  end
  if type(cfg.plugin) ~= "string" or cfg.plugin == "" then
    error("contract.doc.new: plugin must be a non-empty string", 2)
  end
  if type(cfg.schema) ~= "number" or cfg.schema < 1 or cfg.schema ~= math.floor(cfg.schema) then
    error("contract.doc.new: schema must be a whole number from 1", 2)
  end

  local kind_prefix = cfg.kind_prefix or (cfg.plugin:gsub("%.nvim$", ""))
  local scope_key = cfg.scope_key or "vault"
  local placeholder = cfg.placeholder or ("<" .. scope_key .. ">")
  local hint = cfg.too_large_hint or "ask for a page or an area"
  local error_kind = kind_prefix .. ".error"
  local plugin_root = cfg.plugin_root and lower_slash(cfg.plugin_root):gsub("/+$", "") or nil

  local d = {
    SCHEMA = cfg.schema,
    PLUGIN = cfg.plugin,
    ENGINE_VERSION = cfg.engine_version or "0.0.0",
    MAX_DOC_BYTES = cfg.max_bytes or M.DEFAULT_MAX_DOC_BYTES,
    ERROR_KIND = error_kind,
    PLACEHOLDER = placeholder,
  }

  ---`<prefix>.<name>`: the `kind` of a document.
  ---@param name string
  ---@return string
  function d.kind(name)
    return kind_prefix .. "." .. name
  end

  -- ── the engine ───────────────────────────────────────────────────────────────

  local git_cache
  local git_tries = 0

  ---Short commit of the plugin checkout; "unknown" when there is no git, no checkout or no `plugin_root`. A definite
  ---answer is kept for the life of the process. A lookup that did not finish in time (a loaded machine, a slow start
  ---of git) is not: it is asked again, three times at most, so a long-lived host does not stay "unknown" because of
  ---one slow moment. Only the first look gets the full wait; a retry is quick (a warm git answers in about 100 ms),
  ---so a machine that stays loaded holds a request for 3 s in all, not 6.
  ---@return string
  local function engine_git()
    if git_cache then
      return git_cache
    end
    if not plugin_root then
      git_cache = "unknown"
      return git_cache
    end
    local wait_ms = git_tries == 0 and 2000 or 500
    local ok, res = pcall(function()
      return vim
        .system({ "git", "-C", plugin_root, "rev-parse", "--short", "HEAD" }, { text = true })
        :wait(wait_ms)
    end)
    if ok and res and res.code == 0 then
      local sha = vim.trim(res.stdout or "")
      if sha:match("^%x+$") then
        git_cache = sha
        return git_cache
      end
    end
    -- git ran and said there is no commit (code 1..): that stays. No answer in time (the code 124 of `:wait`, the
    -- signal of the kill, or an error of the start): try again on a later call.
    git_tries = git_tries + 1
    local answered = ok and res and res.code ~= 124 and (res.signal or 0) == 0
    if answered or git_tries >= 3 then
      git_cache = "unknown"
      return git_cache
    end
    return "unknown"
  end

  ---The time a document is stamped with (UTC, `YYYY-MM-DDTHH:MM:SSZ`). A seam: golden files and reproducible runs
  ---set a fixed one; nothing else changes it.
  ---@return string
  function d.clock()
    return os.date("!%Y-%m-%dT%H:%M:%SZ") --[[@as string]]
  end

  ---What the head says about the engine (same seam, same reason).
  ---@return { version: string, git: string, nvim: string }
  function d.engine_info()
    return { version = d.ENGINE_VERSION, git = engine_git(), nvim = tostring(vim.version()) }
  end

  ---The head every document starts with.
  ---@param kind string
  ---@param root? string
  ---@return table
  function d.head(kind, root)
    return {
      schema = d.SCHEMA,
      plugin = d.PLUGIN,
      kind = kind,
      generated_at = d.clock(),
      [scope_key] = json.object({ id = root and vim.fs.basename(root) or "" }),
      engine = json.object(d.engine_info()),
    }
  end

  -- ── paths: nothing of this machine in a document ────────────────────────────

  ---`path` relative to the root, with `/`; `nil` when it is not inside it (case-insensitive: a Windows path).
  ---@param root string
  ---@param path string
  ---@return string|nil
  function d.relative(root, path)
    local p = lower_slash(path)
    local r = lower_slash(root):gsub("/+$", "")
    if p:sub(1, #r + 1):lower() == (r .. "/"):lower() then
      return p:sub(#r + 2)
    end
    return nil
  end

  ---A reference or a path in a message without anything that belongs to this machine: inside the root it is
  ---relative, an absolute or `~` path is `<external>/<name>`, anything else stays as it is.
  ---@param root string
  ---@param s string
  ---@return string
  function d.safe_path(root, s)
    local text = lower_slash(s)
    local rel = d.relative(root, text)
    if rel then
      return rel
    end
    if text:match("^%a:/") or text:match("^/") or text:match("^~") then
      return "<external>/" .. (text:match("([^/]+)/*$") or "")
    end
    return text
  end

  ---Free text (a message of the engine) with the root named by the placeholder, in both spellings of the path and
  ---whatever the case.
  ---@param root string
  ---@param s string
  ---@return string
  function d.redact(root, s)
    if root == "" then
      return s
    end
    local out = s
    for _, form in ipairs({ root, (root:gsub("/", "\\")) }) do
      local at = 1
      while true do
        local i, j = out:lower():find(form:lower(), at, true)
        if not i then
          break
        end
        out = out:sub(1, i - 1) .. placeholder .. out:sub(j + 1)
        at = i + #placeholder
      end
    end
    return out
  end

  -- ── sealing and encoding ─────────────────────────────────────────────────────

  ---`rev`: what the source looked like, from lines the plugin builds (an id and a version tag each). The order of
  ---the lines does not matter.
  ---@param lines string[]
  ---@return string
  function d.rev_of(lines)
    local sorted = vim.list_slice(lines, 1)
    table.sort(sorted)
    return "rev:" .. etag.sha256(table.concat(sorted, "\n")):sub(1, 6)
  end

  ---Put `rev` and `digest` on a document. The digest is the hash of the compact document without `generated_at` and
  ---without `engine`.
  ---@param doc table
  ---@param rev? string
  ---@return table
  function d.seal(doc, rev)
    doc.rev = rev
    local at, engine = doc.generated_at, doc.engine
    doc.generated_at, doc.engine, doc.digest = nil, nil, nil
    doc.digest = "sha256:" .. etag.sha256(json.encode(doc)):sub(1, 16)
    doc.generated_at, doc.engine = at, engine
    return doc
  end

  ---The canonical bytes of a document; one bigger than the limit is an error, never a cut-off document.
  ---@param doc table
  ---@param opts? Lib.Json.CanonicalOpts
  ---@return string|nil text
  ---@return Lib.Contract.Error|nil err
  function d.encode(doc, opts)
    local ok, text = pcall(json.encode, doc, opts)
    if not ok then
      return nil, { code = "internal", message = tostring(text), retryable = false }
    end
    -- an error document is exempt: the limit must never keep a client from being told why
    if #text > d.MAX_DOC_BYTES and doc.kind ~= error_kind then
      return nil,
        {
          code = "payload_too_large",
          message = ("the document is %d bytes, more than the %d the contract allows; %s"):format(
            #text,
            d.MAX_DOC_BYTES,
            hint
          ),
          retryable = false,
        }
    end
    return text, nil
  end

  ---An error document.
  ---@param err Lib.Contract.Error
  ---@param root? string
  ---@return table
  function d.error_doc(err, root)
    local doc = d.head(error_kind, root)
    doc.code = err.code
    doc.message = root and d.redact(root, err.message) or err.message
    doc.retryable = err.retryable == true
    if err.details then
      doc.details = json.object(err.details)
    end
    return doc
  end

  return d --[[@as Lib.Contract.Doc]]
end

return M
