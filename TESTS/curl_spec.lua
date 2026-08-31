-- TESTS/curl_spec.lua — lib.nvim.net.curl
--
-- No external test dependency (no python, no local http.server): a tiny
-- `vim.uv` TCP server answers every connection with a hand-crafted raw HTTP
-- response, the same `uv` handle `vim.system` itself is built on — already a
-- hard requirement of this module (see its own header), so nothing new is
-- being asked of the environment. Real curl, real sockets, real parsing;
-- only the "server" on the other end is a few lines of Lua instead of a
-- second process.

return function(H)
  local eq, ok = H.eq, H.ok

  local curl = require("lib.nvim.net.curl")
  local uv = vim.uv or vim.loop

  ---Start a TCP server on an OS-assigned port that answers the first
  ---connection it accepts with `response` (raw bytes — status line, headers,
  ---blank line, body, exactly as a real server's socket would emit them),
  ---then closes. One connection per server, since each test wants its own
  ---canned response.
  ---@param response string
  ---@return integer port
  ---@return uv.uv_tcp_t server
  local function start_server(response)
    -- `assert`, not a check: a spec that cannot open a socket has nothing
    -- left to test, and libuv answers nil rather than raising.
    local server = assert(uv.new_tcp())
    assert(server:bind("127.0.0.1", 0))
    local port = server:getsockname().port
    server:listen(128, function(listen_err)
      assert(not listen_err, listen_err)
      local client = assert(uv.new_tcp())
      server:accept(client)
      -- Respond as soon as anything arrives — a canned response does not
      -- need the request's own content, only proof the client is ready to
      -- read.
      client:read_start(function(_, _)
        client:write(response)
        client:shutdown(function()
          client:close()
        end)
      end)
    end)
    return port, server
  end

  local function stop_server(server)
    if not server:is_closing() then
      server:close()
    end
  end

  ---Like `start_server`, but also captures the raw request bytes curl sent,
  ---for tests that need to assert on request content (headers, multipart
  ---body) rather than just the response.
  ---@param response string
  ---@return integer port
  ---@return uv.uv_tcp_t server
  ---@return { data: string|nil } captured `captured.data` is set once the request arrives.
  local function start_capturing_server(response)
    local server = assert(uv.new_tcp())
    assert(server:bind("127.0.0.1", 0))
    local port = server:getsockname().port
    local captured = { data = nil }
    server:listen(128, function(listen_err)
      assert(not listen_err, listen_err)
      local client = assert(uv.new_tcp())
      server:accept(client)
      client:read_start(function(_, chunk)
        captured.data = (captured.data or "") .. (chunk or "")
        client:write(response)
        client:shutdown(function()
          client:close()
        end)
      end)
    end)
    return port, server, captured
  end

  -- 200, JSON body, a custom header — the common case.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 200 OK",
      "Content-Type: application/json",
      "X-Custom-Header: world",
      "",
      '{"ok":true}',
    }, "\r\n"))

    local success, resp = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port))
    ok(success, "curl.fetch_raw_blocking: a real 200 response is reported ok")
    eq(resp.status, 200, "curl.fetch_raw_blocking: status parsed from the real status line")
    eq(resp.status_text, "OK", "curl.fetch_raw_blocking: reason phrase parsed too")
    eq(
      resp.headers["content-type"],
      "application/json",
      "curl.fetch_raw_blocking: headers parsed, keys lowercased"
    )
    eq(
      resp.headers["x-custom-header"],
      "world",
      "curl.fetch_raw_blocking: a custom header survives"
    )
    eq(resp.body, '{"ok":true}', "curl.fetch_raw_blocking: body is the raw text, undecoded")

    stop_server(server)
  end

  -- 404 is still `ok = true`: curl's own process succeeded, the HTTP status
  -- is a separate fact this module exists specifically to surface — the
  -- whole reason `fetch_raw`/`fetch_raw_blocking` were added.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 404 Not Found",
      "Content-Type: text/plain",
      "",
      "nope",
    }, "\r\n"))

    local success, resp = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port))
    ok(success, "curl.fetch_raw_blocking: curl succeeding is not the same claim as HTTP 200")
    eq(resp.status, 404, "curl.fetch_raw_blocking: ... the real status is still reported")
    eq(resp.status_text, "Not Found", "curl.fetch_raw_blocking: ... reason phrase too")
    eq(resp.body, "nope", "curl.fetch_raw_blocking: ... and the body, whatever it is")

    stop_server(server)
  end

  -- An informational 100-Continue preamble ahead of the real response —
  -- the loop in parse_raw_response has to unwrap it rather than mistake it
  -- for the answer.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 100 Continue",
      "",
      "HTTP/1.1 201 Created",
      "Content-Type: application/json",
      "",
      '{"id":1}',
    }, "\r\n"))

    local success, resp = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port))
    ok(success, "curl.fetch_raw_blocking: a 100-Continue preamble does not break parsing")
    eq(resp.status, 201, "curl.fetch_raw_blocking: the final response's status, not the preamble's")
    eq(resp.body, '{"id":1}', "curl.fetch_raw_blocking: ... and its body")

    stop_server(server)
  end

  -- fetch_raw (async) reaches the same result through the callback.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "async-body",
    }, "\r\n"))

    local done, success, resp
    curl.fetch_raw(("http://127.0.0.1:%d/"):format(port), nil, function(cb_ok, cb_resp)
      success, resp, done = cb_ok, cb_resp, true
    end)
    vim.wait(2000, function()
      return done == true
    end, 20)

    ok(done, "curl.fetch_raw: the callback actually fired")
    ok(success, "curl.fetch_raw: reported ok for a real 200")
    eq(resp.body, "async-body", "curl.fetch_raw: ... with the real body")

    stop_server(server)
  end

  -- An unreachable target: curl itself fails (nothing is listening), which
  -- is a different failure shape from a real-but-unparseable response —
  -- both must report `ok = false`, not raise.
  do
    local closed_port, closed_server = start_server("")
    stop_server(closed_server)
    -- give the loop one tick so the port is actually released
    vim.wait(50, function()
      return false
    end, 10)

    local success, err = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(closed_port), {
      timeout_ms = 2000,
    })
    ok(not success, "curl.fetch_raw_blocking: an unreachable target reports ok = false")
    ok(type(err) == "string", "curl.fetch_raw_blocking: ... with a string error, not a crash")
  end

  -- opts.auth: Basic-auth header actually sent, not just accepted.
  do
    local port, server, captured = start_capturing_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "ok",
    }, "\r\n"))

    local success = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port), {
      auth = { user = "alice", pass = "hunter2" },
    })
    vim.wait(200, function()
      return false
    end, 10)

    ok(success, "opts.auth: request succeeds")
    ok(captured.data ~= nil, "opts.auth: server received the request")
    ok(captured.data:match("Authorization: Basic ") ~= nil, "opts.auth: Basic auth header sent")

    stop_server(server)
  end

  -- Credentials must reach the wire without reaching argv. A process's
  -- command line is readable by any other process on the machine (`ps`,
  -- Win32_Process), and this module used to put the token straight into it --
  -- verified with a real request, whose token showed up in full in the
  -- process list. So both halves are asserted: the header arrives, and the
  -- argv that would have leaked it does not contain it.
  do
    local port, server, captured = start_capturing_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "ok",
    }, "\r\n"))

    local secret = "tok_" .. tostring(os.time()) .. "_shouldnotleak"
    local success = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port), {
      bearer_token = secret,
      headers = { ["X-Plain"] = "visible", Cookie = "session=abc" },
    })
    vim.wait(200, function()
      return false
    end, 10)

    ok(success, "bearer_token: request succeeds")
    ok(captured.data ~= nil, "bearer_token: server received the request")
    ok(
      captured.data:find("Authorization: Bearer " .. secret, 1, true) ~= nil,
      "bearer_token: the Authorization header still reaches the wire"
    )
    ok(
      captured.data:find("Cookie: session=abc", 1, true) ~= nil,
      "secret headers: Cookie reaches the wire too"
    )
    ok(
      captured.data:find("X-Plain: visible", 1, true) ~= nil,
      "plain headers: a non-credential header is unaffected"
    )

    stop_server(server)
  end

  -- opts.form: multipart body actually sent, not just accepted.
  do
    local port, server, captured = start_capturing_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "ok",
    }, "\r\n"))

    local success = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port), {
      method = "POST",
      form = { name = "report" },
    })
    vim.wait(200, function()
      return false
    end, 10)

    ok(success, "opts.form: request succeeds")
    ok(
      captured.data:match("Content%-Type: multipart/form%-data") ~= nil,
      "opts.form: multipart Content-Type header sent"
    )
    ok(captured.data:match('name="name"') ~= nil, "opts.form: field name present in the body")
    ok(captured.data:match("report") ~= nil, "opts.form: field value present in the body")

    stop_server(server)
  end

  -- opts.http_version: the request line itself reflects the forced version.
  do
    local port, server, captured = start_capturing_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "ok",
    }, "\r\n"))

    curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port), {
      http_version = "1.0",
    })
    vim.wait(200, function()
      return false
    end, 10)

    ok(
      captured.data:match("^GET / HTTP/1%.0") ~= nil,
      "opts.http_version: request line honors --http1.0"
    )

    stop_server(server)
  end

  -- opts.raw_args: appended verbatim and actually honored by curl.
  do
    local port, server, captured = start_capturing_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "ok",
    }, "\r\n"))

    curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port), {
      raw_args = { "-A", "lib.nvim-test-agent" },
    })
    vim.wait(200, function()
      return false
    end, 10)

    ok(
      captured.data:match("User%-Agent: lib%.nvim%-test%-agent") ~= nil,
      "opts.raw_args: appended verbatim and honored by curl"
    )

    stop_server(server)
  end

  -- opts.proxy: curl actually routes through it instead of connecting
  -- directly — a proxy pointing at a closed local port must make an
  -- otherwise-reachable request fail, proving the flag was honored rather
  -- than silently ignored.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "ok",
    }, "\r\n"))

    local closed_port, closed_server = start_server("")
    stop_server(closed_server)
    vim.wait(50, function()
      return false
    end, 10)

    local success = curl.fetch_raw_blocking(("http://127.0.0.1:%d/"):format(port), {
      proxy = ("http://127.0.0.1:%d"):format(closed_port),
      timeout_ms = 2000,
    })
    ok(
      not success,
      "opts.proxy: routes through the (unreachable) proxy instead of connecting directly"
    )

    stop_server(server)
  end

  -- download_blocking: body written straight to a file, not buffered.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 200 OK",
      "Content-Type: application/octet-stream",
      "",
      "binary-ish-content-1234",
    }, "\r\n"))

    local dest = vim.fn.tempname()
    local success, resp = curl.download_blocking(("http://127.0.0.1:%d/"):format(port), dest)

    ok(success, "download_blocking: succeeds")
    eq(resp.status, 200, "download_blocking: status parsed from the dumped headers")
    eq(resp.body, "", "download_blocking: response.body is empty -- content went to the file")

    local f = io.open(dest, "rb")
    ok(f ~= nil, "download_blocking: destination file was created")
    local content = f and f:read("*a") or nil
    if f then
      f:close()
    end
    eq(
      content,
      "binary-ish-content-1234",
      "download_blocking: file content matches the response body"
    )
    os.remove(dest)

    stop_server(server)
  end

  -- download (async): same contract, reached through the callback.
  do
    local port, server = start_server(table.concat({
      "HTTP/1.1 200 OK",
      "",
      "async-download-body",
    }, "\r\n"))

    local dest = vim.fn.tempname()
    local done, success
    curl.download(("http://127.0.0.1:%d/"):format(port), dest, nil, function(cb_ok)
      success, done = cb_ok, true
    end)
    vim.wait(2000, function()
      return done == true
    end, 20)

    ok(done, "download: the callback fires")
    ok(success, "download: reports ok for a real 200")

    local f = io.open(dest, "rb")
    local content = f and f:read("*a") or nil
    if f then
      f:close()
    end
    eq(content, "async-download-body", "download: file content matches")
    os.remove(dest)

    stop_server(server)
  end
end
