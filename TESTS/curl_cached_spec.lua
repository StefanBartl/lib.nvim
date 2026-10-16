-- TESTS/curl_cached_spec.lua — lib.nvim.net.curl: download_cached (URL-hash cache) and the byte limit that
-- also holds for a response without Content-Length.
--
-- Real curl against a tiny `vim.uv` TCP server, like curl_spec.lua. No external test dependency.

return function(H)
  local eq, ok = H.eq, H.ok
  local curl = require("lib.nvim.net.curl")
  local uv = vim.uv or vim.loop

  if vim.fn.executable("curl") ~= 1 then
    H.skipped("curl download_cached", "no curl on this host")
    return
  end

  local CRLF = string.char(13, 10)

  ---A server that answers EVERY connection with `make_response(n)` (n counts the requests), then closes.
  ---@param make_response fun(n: integer): string
  ---@return integer port
  ---@return { hits: integer, close: fun() } server
  local function start_server(make_response)
    local state = { hits = 0 }
    local server = assert(uv.new_tcp())
    assert(server:bind("127.0.0.1", 0))
    local port = server:getsockname().port
    server:listen(128, function()
      local client = assert(uv.new_tcp())
      server:accept(client)
      client:read_start(function()
        client:read_stop()
        state.hits = state.hits + 1
        client:write(make_response(state.hits))
        client:shutdown(function()
          client:close()
        end)
      end)
    end)
    function state.close()
      if not server:is_closing() then
        server:close()
      end
    end
    return port, state
  end

  local function ok_response(body)
    return table.concat({
      "HTTP/1.1 200 OK",
      "Content-Length: " .. #body,
      "Connection: close",
      "",
      body,
    }, CRLF)
  end

  local cache_dir = vim.fn.tempname() .. "-curl-cache"
  vim.fn.mkdir(cache_dir, "p")
  local function listing()
    local names = vim.fn.readdir(cache_dir)
    table.sort(names)
    return names
  end

  -- cache_path: sha256 of the whole URL, the extension of the URL's path
  do
    local a = curl.cache_path("http://x.example/a/pic.PNG?size=1", { cache_dir = cache_dir })
    local b = curl.cache_path("http://x.example/a/pic.PNG?size=2", { cache_dir = cache_dir })
    ok(a ~= b, "cache_path: the query is part of the key")
    ok(a:match("%.png$") ~= nil, "cache_path: the extension of the path is kept, lower-cased")
    ok(
      a:find(vim.fn.sha256("http://x.example/a/pic.PNG?size=1"), 1, true) ~= nil,
      "cache_path: the name is the URL hash"
    )
    ok(
      curl.cache_path("http://x.example/noext", { cache_dir = cache_dir }):match("%.[%w]+$") == nil,
      "cache_path: no extension, none invented"
    )
    eq(vim.fs.dirname(a), vim.fs.normalize(cache_dir), "cache_path: inside cache_dir")
  end

  -- blocking: miss downloads, hit makes no request
  do
    local port, srv = start_server(function(n)
      return ok_response("payload-" .. n)
    end)
    local url = ("http://127.0.0.1:%d/file.txt"):format(port)
    local good, path, info = curl.download_cached_blocking(url, { cache_dir = cache_dir })
    ok(good, "blocking miss: downloads: " .. tostring(path))
    eq(info.cached, false, "blocking miss: not from cache")
    eq(info.response.status, 200, "blocking miss: the response is handed back")
    eq(
      table.concat(vim.fn.readfile(path, "b"), "\n"),
      "payload-1",
      "blocking miss: the body is in the cache file"
    )
    eq(#listing(), 1, "blocking miss: exactly one file, no .part left")

    local good2, path2, info2 = curl.download_cached_blocking(url, { cache_dir = cache_dir })
    ok(good2, "blocking hit: ok")
    eq(path2, path, "blocking hit: the same path")
    eq(info2.cached, true, "blocking hit: reported as cached")
    eq(srv.hits, 1, "blocking hit: no second request was made")

    -- refresh and ttl force a new request
    local _, _, info3 =
      curl.download_cached_blocking(url, { cache_dir = cache_dir, refresh = true })
    eq(info3.cached, false, "refresh = true: downloads again")
    eq(srv.hits, 2, "refresh = true: a second request was made")
    eq(
      table.concat(vim.fn.readfile(path, "b"), "\n"),
      "payload-2",
      "refresh = true: the file is replaced"
    )

    uv.fs_utime(path, os.time() - 1000, os.time() - 1000)
    local _, _, info4 = curl.download_cached_blocking(url, { cache_dir = cache_dir, ttl_s = 60 })
    eq(info4.cached, false, "ttl_s: an older file is downloaded again")
    local _, _, info5 = curl.download_cached_blocking(url, { cache_dir = cache_dir, ttl_s = 60 })
    eq(info5.cached, true, "ttl_s: a fresh file is served")
    srv.close()
  end

  -- a non-2xx answer is never cached
  do
    local port, srv = start_server(function()
      local body = "not here"
      return table.concat(
        { "HTTP/1.1 404 Not Found", "Content-Length: " .. #body, "Connection: close", "", body },
        CRLF
      )
    end)
    local before = #listing()
    local url = ("http://127.0.0.1:%d/missing.txt"):format(port)
    local good, err = curl.download_cached_blocking(url, { cache_dir = cache_dir })
    eq(good, false, "404: not a download")
    ok(
      tostring(err):find("404", 1, true) ~= nil,
      "404: the status is in the error: " .. tostring(err)
    )
    eq(#listing(), before, "404: nothing is left in the cache dir (no error page, no .part)")
    eq(uv.fs_stat(curl.cache_path(url, { cache_dir = cache_dir })), nil, "404: no cache entry")
    srv.close()
  end

  -- max_bytes with a Content-Length: refused, nothing cached
  do
    local port, srv = start_server(function()
      return ok_response(string.rep("x", 5000))
    end)
    local before = #listing()
    local good = curl.download_cached_blocking(
      ("http://127.0.0.1:%d/big.bin"):format(port),
      { cache_dir = cache_dir, max_bytes = 100 }
    )
    eq(good, false, "max_bytes (announced size): refused")
    eq(#listing(), before, "max_bytes (announced size): nothing cached")
    srv.close()
  end

  -- max_bytes WITHOUT Content-Length (chunked): refused whether curl enforces --max-filesize itself (current
  -- curl: "Exceeded the maximum allowed file size") or our own check of the written file does (older curl)
  local function names_limit(err)
    err = tostring(err)
    return err:find("max_bytes", 1, true) ~= nil
      or err:find("maximum allowed file size", 1, true) ~= nil
  end
  do
    local body = string.rep("y", 4000)
    local port, srv = start_server(function()
      return table.concat({
        "HTTP/1.1 200 OK",
        "Transfer-Encoding: chunked",
        "Connection: close",
        "",
        string.format("%x", #body),
        body,
        "0",
        "",
        "",
      }, CRLF)
    end)
    local before = #listing()
    local url = ("http://127.0.0.1:%d/chunked.bin"):format(port)
    local good, err = curl.download_cached_blocking(url, { cache_dir = cache_dir, max_bytes = 100 })
    eq(good, false, "max_bytes (chunked): refused although curl cannot see the size")
    ok(names_limit(err), "max_bytes (chunked): the reason names the limit: " .. tostring(err))
    eq(#listing(), before, "max_bytes (chunked): nothing cached")

    -- the same through the plain download: the partial file is removed
    local dest = vim.fn.tempname()
    local ok2, err2 = curl.download_blocking(url, dest, { max_bytes = 100 })
    eq(ok2, false, "download_blocking (chunked): refused")
    ok(names_limit(err2), "download_blocking (chunked): the reason names the limit")
    eq(uv.fs_stat(dest), nil, "download_blocking (chunked): no file left behind")
    srv.close()
  end

  -- async: the same contract through the callback, and a chunked endless body is cut while it streams
  do
    local port, srv = start_server(function(n)
      return ok_response("async-" .. n)
    end)
    local url = ("http://127.0.0.1:%d/async.txt"):format(port)
    local done
    curl.download_cached(url, { cache_dir = cache_dir }, function(good, path, info)
      done = { ok = good, path = path, info = info }
    end)
    vim.wait(10000, function()
      return done ~= nil
    end, 10)
    ok(done and done.ok, "async miss: ok")
    eq(done.info.cached, false, "async miss: not cached yet")
    eq(
      table.concat(vim.fn.readfile(done.path, "b"), "\n"),
      "async-1",
      "async miss: body in the cache file"
    )

    local again
    curl.download_cached(url, { cache_dir = cache_dir }, function(good, path, info)
      again = { ok = good, path = path, info = info }
    end)
    vim.wait(10000, function()
      return again ~= nil
    end, 10)
    ok(again and again.ok and again.info.cached, "async hit: served from the cache")
    eq(srv.hits, 1, "async hit: no second request")
    srv.close()

    -- an endless chunked body: the watcher kills curl once the file passes max_bytes
    local endless = assert(uv.new_tcp())
    assert(endless:bind("127.0.0.1", 0))
    local eport = endless:getsockname().port
    local feeder
    endless:listen(8, function()
      local client = assert(uv.new_tcp())
      endless:accept(client)
      client:read_start(function()
        client:read_stop()
        client:write(
          table.concat({ "HTTP/1.1 200 OK", "Transfer-Encoding: chunked", "", "" }, CRLF)
        )
        local chunk = string.format("%x", 1024) .. CRLF .. string.rep("z", 1024) .. CRLF
        feeder = uv.new_timer()
        feeder:start(0, 20, function()
          if client:is_closing() then
            feeder:stop()
            return
          end
          client:write(chunk, function(werr)
            if werr and not client:is_closing() then
              client:close()
            end
          end)
        end)
      end)
    end)
    local dest = vim.fn.tempname()
    local result
    local started = uv.hrtime()
    curl.download(
      ("http://127.0.0.1:%d/endless"):format(eport),
      dest,
      { max_bytes = 20 * 1024, timeout_ms = 60000 },
      function(good, err)
        result = { ok = good, err = err }
      end
    )
    vim.wait(30000, function()
      return result ~= nil
    end, 20)
    local took_ms = (uv.hrtime() - started) / 1e6
    if feeder and not feeder:is_closing() then
      feeder:stop()
      feeder:close()
    end
    if not endless:is_closing() then
      endless:close()
    end
    ok(result ~= nil, "endless body: the download ended")
    eq(result and result.ok, false, "endless body: refused")
    ok(names_limit(result and result.err), "endless body: the reason names the limit")
    ok(
      took_ms < 20000,
      ("endless body: cut while streaming, not at the 60 s timeout (%.0f ms)"):format(took_ms)
    )
    eq(uv.fs_stat(dest), nil, "endless body: no file left behind")
  end

  -- an older curl that ignores --max-filesize without a known size: simulated by a vim.system that writes
  -- the file anyway and exits 0 -- our own check must still refuse it and remove the file
  do
    local real_system = vim.system
    ---@param argv string[]
    ---@return string
    local function dest_of(argv)
      for i, a in ipairs(argv) do
        if a == "-o" then
          return argv[i + 1]
        end
      end
      error("no -o in argv")
    end
    local headers = table.concat({ "HTTP/1.1 200 OK", "Connection: close", "", "" }, CRLF)
    local function write_big(dest)
      local f = assert(io.open(dest, "wb"))
      f:write(string.rep("q", 5000))
      f:close()
    end

    -- blocking
    vim.system = function(argv)
      write_big(dest_of(argv))
      return {
        wait = function()
          return { code = 0, stdout = headers, stderr = "" }
        end,
      }
    end
    local dest = vim.fn.tempname()
    local good, err = curl.download_blocking("http://127.0.0.1:1/x", dest, { max_bytes = 100 })
    vim.system = real_system
    eq(good, false, "ignoring curl, blocking: refused by our own check")
    ok(names_limit(err), "ignoring curl, blocking: the reason names the limit")
    eq(uv.fs_stat(dest), nil, "ignoring curl, blocking: the file is removed")

    -- async
    vim.system = function(argv, _, on_exit)
      write_big(dest_of(argv))
      vim.schedule(function()
        on_exit({ code = 0, stdout = headers, stderr = "" })
      end)
      return { kill = function() end }
    end
    local dest2 = vim.fn.tempname()
    local res
    curl.download("http://127.0.0.1:1/x", dest2, { max_bytes = 100 }, function(ok_, err_)
      res = { ok = ok_, err = err_ }
    end)
    vim.wait(5000, function()
      return res ~= nil
    end, 10)
    vim.system = real_system
    ok(res ~= nil, "ignoring curl, async: the callback fires")
    eq(res and res.ok, false, "ignoring curl, async: refused by our own check")
    ok(names_limit(res and res.err), "ignoring curl, async: the reason names the limit")
    eq(uv.fs_stat(dest2), nil, "ignoring curl, async: the file is removed")
  end

  vim.fn.delete(cache_dir, "rf")
end
