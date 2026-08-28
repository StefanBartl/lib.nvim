---@module 'lib.nvim.hover.preview.url'
---@brief URL hover preview: the parsed URL always, page metadata only when
---explicitly enabled.
---@description
--- **Fetching is off by default, on purpose.** A hover that silently issues
--- HTTP requests is both a privacy problem (every link you brush past is
--- disclosed to its host) and a practical one (a document with fifty links
--- becomes a request storm while scrolling). The default preview is
--- therefore purely local: scheme, host, path, decoded query — parsed, not
--- fetched.
---
--- With `hover.url.fetch = true`, `<title>` and `<meta name="description">`
--- are fetched through `lib.nvim.net.curl` and cached.

local M = {}

---@internal
--- Split a URL into its parts without a URL library: enough for a display
--- line, not a spec-complete parser.
---@param url string
---@return table
local function split_url(url)
  local scheme, rest = url:match("^(%a[%w+.-]*):/?/?(.*)$")
  if not scheme then
    return { host = url }
  end

  -- mailto: and other non-hierarchical schemes have no host/path split.
  if scheme == "mailto" then
    return { scheme = scheme, host = rest }
  end

  local hostport, path = rest:match("^([^/]*)(.*)$")
  local path_part, query = (path or ""):match("^([^?]*)%??(.*)$")
  return {
    scheme = scheme,
    host = hostport,
    path = (path_part ~= "" and path_part or nil),
    query = (query ~= "" and query or nil),
  }
end

---@internal
--- Percent-decode for display. Reuses lib.nvim's decoder rather than a local
--- gsub so `+`-vs-`%20` handling matches everywhere else in the ecosystem.
---@param s string
---@return string
local function decode(s)
  local ok, enc = pcall(require, "lib.lua.strings.encoding")
  if ok and enc and enc.url_decode then
    local decoded_ok, decoded = pcall(enc.url_decode, s)
    if decoded_ok then
      return decoded
    end
  end
  return s
end

---@internal
--- Pull `<title>` and `<meta name="description">` out of an HTML body.
--- Deliberately pattern-based: a hover does not justify a real HTML parser,
--- and a miss degrades to "no title found" rather than being wrong.
---@param body string
---@return string|nil title
---@return string|nil description
local function extract_meta(body)
  local title = body:match("<title[^>]*>(.-)</title>")
  if title then
    title = decode(vim.trim(title:gsub("%s+", " ")))
    if title == "" then
      title = nil
    end
  end

  local description = body:match("<meta[^>]-name=[\"']description[\"'][^>]-content=[\"'](.-)[\"']")
    or body:match("<meta[^>]-content=[\"'](.-)[\"'][^>]-name=[\"']description[\"']")
  if description then
    description = decode(vim.trim(description:gsub("%s+", " ")))
    if description == "" then
      description = nil
    end
  end

  return title, description
end

--- The always-available, offline preview: the URL taken apart.
---@param target Lib.Hover.Target
---@return Lib.Hover.Content
function M.offline(target)
  local parts = split_url(target.url or target.raw)
  local lines = {}

  if parts.host and parts.host ~= "" then
    lines[#lines + 1] = parts.host
  end
  if parts.path and parts.path ~= "/" then
    lines[#lines + 1] = decode(parts.path)
  end
  if parts.query then
    lines[#lines + 1] = "? " .. decode(parts.query)
  end
  if #lines == 0 then
    lines[#lines + 1] = target.raw
  end

  return { lines = lines, title = parts.scheme or "url" }
end

--- Fetch page metadata. Only called when `hover.url.fetch` is on.
---@param target Lib.Hover.Target
---@param opts Lib.Hover.PreviewOpts
---@param callback fun(content: Lib.Hover.Content|nil, err: string|nil)
function M.fetch(target, opts, callback)
  local url = target.url or target.raw

  -- Only http(s) is fetchable; mailto:/file: and friends stay offline.
  if not url:match("^https?://") then
    callback(M.offline(target))
    return
  end

  local ok_curl, curl = pcall(require, "lib.nvim.net.curl")
  if not ok_curl then
    local content = M.offline(target)
    content.lines[#content.lines + 1] = "(lib.nvim.net.curl unavailable)"
    callback(content)
    return
  end

  curl.fetch_raw(url, {
    method = "GET",
    timeout_ms = opts.url_timeout_ms or 2000,
    -- Follow redirects and ask for HTML; without an Accept header some hosts
    -- answer with an API representation that has no <title> at all.
    raw_args = { "-L", "--max-filesize", "2000000" },
    headers = { Accept = "text/html,application/xhtml+xml" },
  }, function(ok, response)
    local content = M.offline(target)

    if not ok or type(response) ~= "table" then
      content.lines[#content.lines + 1] = "(fetch failed)"
      callback(content)
      return
    end

    local title, description = extract_meta(response.body or "")
    local lines = {}
    if title then
      lines[#lines + 1] = title
    end
    if description then
      lines[#lines + 1] = description
    end
    if #lines > 0 then
      lines[#lines + 1] = ""
    end
    for _, line in ipairs(content.lines) do
      lines[#lines + 1] = line
    end
    lines[#lines + 1] = ("HTTP %s"):format(response.status or "?")

    callback({ lines = lines, title = title and "page" or content.title })
  end)
end

return M
