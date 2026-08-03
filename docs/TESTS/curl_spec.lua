-- docs/TESTS/curl_spec.lua — lib.nvim.net.curl
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
  ---@return uv_tcp_t server
  local function start_server(response)
    local server = uv.new_tcp()
    assert(server:bind("127.0.0.1", 0))
    local port = server:getsockname().port
    server:listen(128, function(listen_err)
      assert(not listen_err, listen_err)
      local client = uv.new_tcp()
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
end
