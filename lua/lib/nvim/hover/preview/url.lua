---@module 'lib.nvim.hover.preview.url'
---@brief URL hover preview: the parsed URL when the web hover is on, the
---server's answer when fetching is on too.
---@description
--- **Both levels are off by default, for two different reasons.**
---
--- `hover.url.hover` is off because dev documentation is *made* of links. A
--- hover that opens on every one of them turns reading a README into a
--- flickering slideshow, and the float lands over the text being read.
--- `:Lib hover web on` is the reader saying "for the next while, links are
--- what I am interested in".
---
--- `hover.url.fetch` is off on top of that because fetching is a disclosure:
--- every link the cursor rests on becomes a request from this machine to that
--- host, and a document with fifty links becomes a request storm while
--- scrolling. With it on, the response's **status line comes first** — a
--- `404` or a `500` is the single most useful thing a hover can say about a
--- link — followed by `<title>`, `<meta name="description">` and the content
--- type.
---
--- Fetching goes through `lib.nvim.net.curl`, and results are cached by the
--- hover for the session: a URL is not re-fetched every time the cursor
--- passes it, which also means a server that has since recovered still shows
--- its old status until the cache is dropped (`:Lib hover web off` / `on`
--- does that).

local M = {}

---@internal
--- Split a URL into its parts without a URL library: enough for a display
--- line, not a spec-complete parser.
---@param url string
---@return table
local function split_url(url)
  local scheme, rest = url:match("^(%a[%w+.-]*):/?/?(.*)$")
  if not scheme then
    -- No scheme at all: `classify` only produces that for a `www.` host, so
    -- everything before the first `/` is the host.
    local host, path = url:match("^([^/]*)(.*)$")
    return { host = host, path = (path ~= "" and path or nil) }
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

---@internal
--- The reason phrase for a status code the server did not name itself. Only
--- the ones a link in a document actually produces — this is a hover, not an
--- HTTP reference.
---@type table<integer, string>
local STATUS_TEXT = {
  [200] = "OK",
  [201] = "Created",
  [204] = "No Content",
  [301] = "Moved Permanently",
  [302] = "Found",
  [304] = "Not Modified",
  [307] = "Temporary Redirect",
  [308] = "Permanent Redirect",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [403] = "Forbidden",
  [404] = "Not Found",
  [408] = "Request Timeout",
  [410] = "Gone",
  [418] = "I'm a teapot",
  [429] = "Too Many Requests",
  [500] = "Internal Server Error",
  [502] = "Bad Gateway",
  [503] = "Service Unavailable",
  [504] = "Gateway Timeout",
}

---@internal
--- Content type without its parameters, and the body size in bytes if the
--- server declared one — the two header facts that say what a link *is* when
--- there is no title to read (a PDF, a tarball, a JSON API).
---@param headers table<string, string>|nil
---@param body string|nil
---@return string|nil
local function type_line(headers, body)
  headers = headers or {}
  local ctype = headers["content-type"]
  if ctype then
    ctype = vim.trim(ctype:match("^([^;]+)") or ctype)
  end

  local length = tonumber(headers["content-length"]) or (body and #body or nil)
  local size
  if length then
    local ok, fmt = pcall(require, "lib.lua.strings.format")
    size = (ok and fmt and fmt.format_bytes) and fmt.format_bytes(length)
      or (tostring(length) .. " B")
  end

  if ctype and size then
    return ("%s · %s"):format(ctype, size)
  end
  return ctype or size
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
---
--- The callback always receives content, never nil: a failed request is an
--- answer worth showing ("✗ no answer", and the URL that was tried), and a
--- nil would collapse into "no hover at all", which is indistinguishable from
--- the feature being off.
---@param target Lib.Hover.Target
---@param opts Lib.Hover.PreviewOpts
---@param callback fun(content: Lib.Hover.Content)
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
    local offline = M.offline(target)

    if not ok or type(response) ~= "table" then
      -- No status line at all: DNS failure, refused connection, TLS error, or
      -- the timeout. Distinguished from an HTTP error, because "the server
      -- said 500" and "there was no server" are different problems and the
      -- reader is about to act on one of them.
      local lines = { "✗ no answer" }
      local reason = type(response) == "string" and vim.trim(response:gsub("%s+", " ")) or nil
      lines[#lines + 1] = (reason and reason ~= "") and reason
        or ("unreachable, or slower than " .. tostring(opts.url_timeout_ms or 2000) .. " ms")
      for _, line in ipairs(offline.lines) do
        lines[#lines + 1] = line
      end
      callback({ lines = lines, title = offline.title, highlight = "LibHoverError" })
      return
    end

    local status = tonumber(response.status) or 0
    local phrase = response.status_text
    if not phrase or phrase == "" then
      phrase = STATUS_TEXT[status] or ""
    end

    -- The status first, and on its own line. It is the answer to the question
    -- a reader hovers a link to ask -- "is this still there?" -- and burying
    -- it under a page title is what made the earlier version of this preview
    -- only decorative.
    local lines = { vim.trim(("HTTP %d %s"):format(status, phrase)) }

    local title, description = extract_meta(response.body or "")
    if title then
      lines[#lines + 1] = title
    end
    if description then
      lines[#lines + 1] = description
    end

    local ctype = type_line(response.headers, response.body)
    if ctype then
      lines[#lines + 1] = ctype
    end

    lines[#lines + 1] = ""
    for _, line in ipairs(offline.lines) do
      lines[#lines + 1] = line
    end

    callback({
      lines = lines,
      title = title and "page" or offline.title,
      -- 4xx/5xx marked, so a dead link is recognizable without reading the
      -- number. 3xx is not an error: curl followed it, and what is shown is
      -- the destination's own status.
      highlight = (status >= 400 or status == 0) and "LibHoverError" or nil,
    })
  end)
end

return M
