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
    -- the host is not an extension
    for _, bare in ipairs({
      "http://example.com",
      "http://example.com/",
      "https://host:8080/dir.v2/file",
      "http://u:p@host.org",
    }) do
      eq(
        curl.cache_path(bare, { cache_dir = cache_dir }):match("%.%w+$"),
        nil,
        "cache_path: no extension for " .. bare
      )
    end
    ok(
      curl
        .cache_path("https://host:8080/dir.v2/pic.jpeg#frag", { cache_dir = cache_dir })
        :match("%.jpeg$") ~= nil,
      "cache_path: the extension of the last path segment, fragment ignored"
    )
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

  -- stale .part files (a crashed download) are swept once per directory, young ones are left alone
  do
    local dir = vim.fn.tempname() .. "-sweep"
    vim.fn.mkdir(dir, "p")
    local old_part, young_part, other =
      dir .. "/abc.png.part.1.2", dir .. "/def.png.part.3.4", dir .. "/keep.png"
    for _, f in ipairs({ old_part, young_part, other }) do
      local fh = assert(io.open(f, "wb"))
      fh:write("x")
      fh:close()
    end
    uv.fs_utime(old_part, os.time() - 3 * 24 * 3600, os.time() - 3 * 24 * 3600)
    uv.fs_utime(other, os.time() - 3 * 24 * 3600, os.time() - 3 * 24 * 3600)
    curl.cache_path("http://example.com/x.png", { cache_dir = dir })
    eq(uv.fs_stat(old_part), nil, "sweep: a day-old .part file is removed")
    ok(
      uv.fs_stat(young_part) ~= nil,
      "sweep: a young .part file stays (another instance may be writing it)"
    )
    ok(uv.fs_stat(other) ~= nil, "sweep: an old cache file that is no .part stays")
    vim.fn.delete(dir, "rf")
  end

  -- bounded cache: max_age_s / max_total_bytes drop least recently used entries, only cache-named files
  do
    local dir = vim.fn.tempname() .. "-curl-bound"
    vim.fn.mkdir(dir, "p")
    local function entry(tag, size, ago, ext)
      local p = dir .. "/" .. vim.fn.sha256(tag) .. (ext or "")
      vim.fn.writefile({ string.rep("x", size - 1) }, p, "b")
      local t = os.time() - ago
      uv.fs_utime(p, t, t)
      return p
    end
    local port, srv = start_server(function()
      return ok_response("12345678")
    end)
    local function fetch(name, opts)
      opts.cache_dir = dir
      return curl.download_cached_blocking(("http://127.0.0.1:%d/%s"):format(port, name), opts)
    end

    -- max_age_s
    local old = entry("old", 100, 5000, ".png")
    local young = entry("young", 100, 10)
    local foreign = dir .. "/notes.txt"
    vim.fn.writefile({ "mine" }, foreign)
    uv.fs_utime(foreign, os.time() - 9000, os.time() - 9000)
    local shorthex = dir .. "/deadbeef.txt"
    vim.fn.writefile({ "mine too" }, shorthex)
    uv.fs_utime(shorthex, os.time() - 9000, os.time() - 9000)
    local part = dir .. "/" .. vim.fn.sha256("p") .. ".png.part.1.2"
    vim.fn.writefile({ "partial" }, part)
    uv.fs_utime(part, os.time() - 9000, os.time() - 9000)
    local good, fresh = fetch("a.txt", { max_age_s = 1000 })
    ok(good, "max_age_s: download works")
    eq(uv.fs_stat(old), nil, "max_age_s: an entry unused for longer is removed")
    ok(uv.fs_stat(young) ~= nil, "max_age_s: a younger entry stays")
    ok(uv.fs_stat(fresh) ~= nil, "max_age_s: the file just stored stays")
    ok(uv.fs_stat(foreign) ~= nil, "max_age_s: a file without a cache name is never touched")
    ok(uv.fs_stat(part) ~= nil, "max_age_s: a .part file is never touched")
    ok(
      uv.fs_stat(shorthex) ~= nil,
      "max_age_s: a hex name that is not a 64-digit hash is never touched"
    )

    -- no limit set: nothing is removed
    local keepme = entry("keepme", 100, 99999)
    fetch("b.txt", {})
    ok(uv.fs_stat(keepme) ~= nil, "no limits: nothing is removed")
    vim.fn.delete(keepme)

    -- max_total_bytes: least recently used go first
    for _, p in ipairs({ old, young, fresh }) do
      vim.fn.delete(p)
    end
    local oldest = entry("o1", 100, 300)
    local middle = entry("o2", 100, 200)
    local newest = entry("o3", 100, 100)
    fetch("c.txt", { max_total_bytes = 250 }) -- 300 + 9 stored: must drop the oldest
    eq(uv.fs_stat(oldest), nil, "max_total_bytes: the least recently used entry goes first")
    ok(
      uv.fs_stat(middle) ~= nil and uv.fs_stat(newest) ~= nil,
      "max_total_bytes: stops once within the limit"
    )

    -- a hit renews the use time (so it survives), but not the mtime (ttl_s still counts from the download)
    local hit_url = ("http://127.0.0.1:%d/c.txt"):format(port)
    local hit_path = curl.cache_path(hit_url, { cache_dir = dir })
    local mt = os.time() - 4000
    uv.fs_utime(hit_path, mt, mt)
    local before = uv.fs_stat(middle)
    local hit_ok, _, hit_info = curl.download_cached_blocking(hit_url, { cache_dir = dir })
    ok(hit_ok and hit_info.cached, "hit: served from the cache")
    local st = uv.fs_stat(hit_path)
    ok(os.time() - st.atime.sec <= 5, "hit: the use time is renewed")
    eq(st.mtime.sec, mt, "hit: the mtime is left alone (ttl_s counts from the download)")
    ok(before ~= nil, "hit: setup")
    -- LRU: the hit entry outlives a never-used one that is younger by mtime
    fetch("d.txt", { max_total_bytes = 220 })
    ok(uv.fs_stat(hit_path) ~= nil, "max_total_bytes: an entry that was hit recently is kept")

    -- the file just stored survives a limit below its own size, whatever the spelling of cache_dir
    -- (trailing slash, backslashes on Windows): it must not be mistaken for an eviction candidate
    local spellings = { dir .. "/" }
    if vim.fn.has("win32") == 1 then
      -- only a real separator on Windows; elsewhere it would be a directory named with backslashes
      spellings[#spellings + 1] = (dir:gsub("/", string.char(92)))
    end
    for _, spelled in ipairs(spellings) do
      local g, stored = curl.download_cached_blocking(
        ("http://127.0.0.1:%d/own-%d.txt"):format(port, #spelled),
        { cache_dir = spelled, max_total_bytes = 1 }
      )
      ok(
        g and uv.fs_stat(stored) ~= nil,
        "max_total_bytes: the stored file is kept (cache_dir " .. spelled .. ")"
      )
    end

    -- a removal that fails does not count as freed space: the next entries go instead of stopping short
    local keys = {}
    for i = 1, 3 do
      keys[i] = entry("fail" .. i, 100, 600 - i * 100)
    end
    local real_unlink = uv.fs_unlink
    H.with_patched(uv, "fs_unlink", function(p, ...)
      if p:find(vim.fn.sha256("fail1"), 1, true) then
        return nil, "EBUSY"
      end
      return real_unlink(p, ...)
    end, function()
      fetch("e.txt", { max_total_bytes = 150 })
    end)
    ok(uv.fs_stat(keys[1]) ~= nil, "removal failure: the locked oldest entry is still there")
    eq(
      uv.fs_stat(keys[2]),
      nil,
      "removal failure: not counted as freed, so the next oldest goes too"
    )
    eq(
      uv.fs_stat(keys[3]),
      nil,
      "removal failure: ... and the one after that, until the limit is met"
    )
    -- review cases, each in a fresh directory so that the totals are exact
    local function new_dir()
      local d = vim.fn.tempname() .. "-curl-rev"
      vim.fn.mkdir(d, "p")
      return d
    end
    local function make(d, tag, size, atime, mtime)
      local p = d .. "/" .. vim.fn.sha256(tag)
      vim.fn.writefile({ string.rep("x", size - 1) }, p, "b")
      uv.fs_utime(p, atime, mtime or atime)
      return p
    end
    local function fetch_in(d, name, opts)
      opts.cache_dir = d
      return curl.download_cached_blocking(("http://127.0.0.1:%d/%s"):format(port, name), opts)
    end
    local t0 = os.time() - 1000

    -- the stored file (9 bytes) counts toward the total: 200 + 9 > 205 needs one eviction
    local d1 = new_dir()
    local a1, a2 = make(d1, "c1", 100, t0), make(d1, "c2", 100, t0 + 10)
    fetch_in(d1, "s1.txt", { max_total_bytes = 205 })
    eq(uv.fs_stat(a1), nil, "stored file counts: the least recently used entry goes")
    ok(uv.fs_stat(a2) ~= nil, "stored file counts: ... and only that one")

    -- equal use times: the smaller name goes first, deterministically
    local d2 = new_dir()
    local tied = { make(d2, "t1", 100, t0), make(d2, "t2", 100, t0), make(d2, "t3", 100, t0) }
    table.sort(tied)
    fetch_in(d2, "s2.txt", { max_total_bytes = 150 }) -- 309 total: two evictions
    eq(uv.fs_stat(tied[1]), nil, "tie-break: the smallest name goes first")
    eq(uv.fs_stat(tied[2]), nil, "tie-break: then the next smallest")
    ok(uv.fs_stat(tied[3]) ~= nil, "tie-break: the largest name stays")

    -- use time at sub-second precision: the entry used earlier goes, whatever its name
    local d3 = new_dir()
    local lo, hi = vim.fn.sha256("sub-a"), vim.fn.sha256("sub-b")
    if lo > hi then
      lo, hi = hi, lo
    end
    local older, newer = d3 .. "/" .. hi, d3 .. "/" .. lo -- the older entry has the LARGER name
    vim.fn.writefile({ string.rep("x", 99) }, older, "b")
    vim.fn.writefile({ string.rep("x", 99) }, newer, "b")
    uv.fs_utime(older, t0 + 0.1, t0 + 0.1)
    uv.fs_utime(newer, t0 + 0.9, t0 + 0.9)
    local st_o, st_n = uv.fs_stat(older), uv.fs_stat(newer)
    if st_o.mtime.nsec ~= 0 or st_n.mtime.nsec ~= 0 then -- the file system keeps fractions
      fetch_in(d3, "s3.txt", { max_total_bytes = 150 })
      eq(uv.fs_stat(older), nil, "sub-second: the entry used earlier goes first")
      ok(uv.fs_stat(newer) ~= nil, "sub-second: the entry used later stays")
    else
      H.skipped("curl cache sub-second order", "this file system stores whole seconds")
    end

    -- an unlink that finds the file already gone (another instance) frees its space all the same
    local d4 = new_dir()
    local g1 = make(d4, "g1", 99, t0)
    local g2 = make(d4, "g2", 99, t0 + 10)
    local g3 = make(d4, "g3", 99, t0 + 20)
    local orig_unlink = uv.fs_unlink
    H.with_patched(uv, "fs_unlink", function(p, ...)
      if p:find(vim.fn.sha256("g1"), 1, true) then
        orig_unlink(p, ...)
        return nil, "ENOENT: no such file or directory"
      end
      return orig_unlink(p, ...)
    end, function()
      fetch_in(d4, "s4.txt", { max_total_bytes = 250 }) -- 297 + 9: the lost file alone brings it to 207
    end)
    eq(uv.fs_stat(g1), nil, "lost race: setup, the oldest is gone")
    ok(
      uv.fs_stat(g2) ~= nil and uv.fs_stat(g3) ~= nil,
      "lost race: no other entry is evicted for it"
    )

    -- option validation, and 0 keeps only the file just stored
    for _, bad in ipairs({ "1000", -1, 0 / 0, true }) do
      local raised = pcall(
        curl.download_cached_blocking,
        "http://127.0.0.1:1/x",
        { cache_dir = d4, max_age_s = bad }
      )
      eq(raised, false, "validation: max_age_s = " .. vim.inspect(bad) .. " is refused")
    end
    local raised_total = pcall(
      curl.download_cached_blocking,
      "http://127.0.0.1:1/x",
      { cache_dir = d4, max_total_bytes = "9" }
    )
    eq(raised_total, false, "validation: a string max_total_bytes is refused")
    local d5 = new_dir()
    local z1 = make(d5, "z1", 100, t0)
    local zok, zpath = fetch_in(d5, "s5.txt", { max_total_bytes = 0 })
    eq(uv.fs_stat(z1), nil, "max_total_bytes = 0 removes every other entry")
    ok(zok and uv.fs_stat(zpath) ~= nil, "max_total_bytes = 0 keeps the file just stored")

    -- the async path prunes after a download and renews the use time on a hit
    local d6 = new_dir()
    local y_old = make(d6, "y-old", 100, t0)
    local async_url = ("http://127.0.0.1:%d/async.txt"):format(port)
    local got
    curl.download_cached(async_url, { cache_dir = d6, max_age_s = 500 }, function(g, p, info)
      got = { g, p, info }
    end)
    vim.wait(5000, function()
      return got ~= nil
    end, 10)
    ok(got and got[1], "async: download works")
    eq(uv.fs_stat(y_old), nil, "async: the stale entry is pruned after the download")
    ok(got and uv.fs_stat(got[2]) ~= nil, "async: the stored file stays")
    local mt_async = os.time() - 4000
    uv.fs_utime(got[2], mt_async, mt_async)
    local hit
    curl.download_cached(async_url, { cache_dir = d6 }, function(g, p, info)
      hit = { g, p, info }
    end)
    vim.wait(5000, function()
      return hit ~= nil
    end, 10)
    ok(hit and hit[3].cached, "async hit: served from the cache")
    local hst = uv.fs_stat(got[2])
    ok(os.time() - hst.atime.sec <= 5, "async hit: the use time is renewed")
    eq(hst.mtime.sec, mt_async, "async hit: the mtime is left alone")

    -- a failing prune never fails the download; it is reported once
    local d7 = new_dir()
    make(d7, "w1", 100, t0)
    local warned
    H.with_patched(vim, "notify_once", function(msg)
      warned = msg
    end, function()
      H.with_patched(vim.fs, "basename", function()
        error("boom from prune", 0)
      end, function()
        local wok = fetch_in(d7, "s7.txt", { max_age_s = 10 })
        ok(wok, "prune failure: the download still succeeds")
      end)
      vim.wait(2000, function()
        return warned ~= nil
      end, 10)
    end)
    ok(
      warned and warned:find("cache pruning failed", 1, true) ~= nil,
      "prune failure: reported as a warning"
    )

    for _, d in ipairs({ d1, d2, d3, d4, d5, d6, d7 }) do
      vim.fn.delete(d, "rf")
    end
    srv.close()
    vim.fn.delete(dir, "rf")
  end

  vim.fn.delete(cache_dir, "rf")
end
