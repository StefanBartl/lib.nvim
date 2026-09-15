-- TESTS/config_repo_file_spec.lua — lib.nvim.config.repo_file
--
-- Real temp files on disk (this module's whole job is reading one), one
-- fixture per failure mode plus the allowlist split itself.

return function(H)
  local eq, ok = H.eq, H.ok

  local repo_file = require("lib.nvim.config.repo_file")

  ---@param content string
  ---@return string path
  local function write_fixture(content)
    local path = H.tmpfile(".json")
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
    return path
  end

  local ALLOWED = { servers = true, formatter = true }

  -- ---------------------------------------------------------- happy path

  do
    local path = write_fixture('{"servers":["luals"],"keymaps":{"x":"y"},"formatter":true}')
    local result, reason, detail = repo_file.load(path, ALLOWED)
    ok(result ~= nil, "repo_file.load: a valid object with mixed keys returns a result")
    eq(reason, nil, "repo_file.load: no reason on success")
    eq(detail, nil, "repo_file.load: no detail on success")
    eq(result.data.servers[1], "luals", "repo_file.load: allowed key kept")
    eq(result.data.formatter, true, "repo_file.load: second allowed key kept")
    eq(result.data.keymaps, nil, "repo_file.load: refused key dropped from data")
    eq(#result.refused, 1, "repo_file.load: exactly one refused key")
    eq(result.refused[1], "keymaps", "repo_file.load: refused key named")
    vim.fn.delete(path)
  end

  -- refused keys come back sorted, regardless of file order
  do
    local path = write_fixture('{"z_unknown":1,"a_unknown":2,"servers":["luals"]}')
    local result = repo_file.load(path, ALLOWED)
    eq(result.refused[1], "a_unknown", "repo_file.load: refused keys sorted (1)")
    eq(result.refused[2], "z_unknown", "repo_file.load: refused keys sorted (2)")
    vim.fn.delete(path)
  end

  -- every key refused -> data is present but empty, not itself an error
  do
    local path = write_fixture('{"keymaps":{}}')
    local result, reason = repo_file.load(path, ALLOWED)
    ok(result ~= nil, "repo_file.load: an object with zero allowed keys is still a result")
    eq(reason, nil, "repo_file.load: not an error when every key is refused")
    eq(next(result.data), nil, "repo_file.load: data is empty when every key is refused")
    eq(#result.refused, 1, "repo_file.load: the one refused key is still reported")
    vim.fn.delete(path)
  end

  -- ---------------------------------------------------------- null handling

  do
    local path = write_fixture('{"servers":null,"formatter":true}')
    local result = repo_file.load(path, ALLOWED)
    eq(result.data.servers, nil, "repo_file.load: JSON null is dropped, not kept as a sentinel")
    eq(result.data.formatter, true, "repo_file.load: sibling key unaffected by a null elsewhere")
    vim.fn.delete(path)
  end

  -- ------------------------------------------------------------- empty file

  do
    local path = write_fixture("")
    local result, reason, detail = repo_file.load(path, ALLOWED)
    eq(result, nil, "repo_file.load: empty file returns no result")
    eq(reason, "empty", "repo_file.load: empty file reason is 'empty'")
    eq(detail, nil, "repo_file.load: empty file has no detail")
    vim.fn.delete(path)
  end

  do
    local path = write_fixture("   \n\t  \n")
    local result, reason = repo_file.load(path, ALLOWED)
    eq(result, nil, "repo_file.load: whitespace-only file is also 'empty'")
    eq(reason, "empty", "repo_file.load: whitespace-only reason is 'empty'")
    vim.fn.delete(path)
  end

  -- --------------------------------------------------------- invalid input

  do
    local path = write_fixture("{not json")
    local result, reason, detail = repo_file.load(path, ALLOWED)
    eq(result, nil, "repo_file.load: malformed JSON returns no result")
    eq(reason, "invalid_json", "repo_file.load: malformed JSON reason")
    ok(
      type(detail) == "string" and #detail > 0,
      "repo_file.load: invalid_json carries a detail message"
    )
    vim.fn.delete(path)
  end

  do
    local path = write_fixture("[1,2,3]")
    local result, reason, detail = repo_file.load(path, ALLOWED)
    eq(result, nil, "repo_file.load: a JSON array is not an object")
    eq(reason, "not_object", "repo_file.load: array reason is 'not_object'")
    eq(detail, nil, "repo_file.load: not_object has no detail")
    vim.fn.delete(path)
  end

  do
    local path = write_fixture('"just a string"')
    local result, reason = repo_file.load(path, ALLOWED)
    eq(result, nil, "repo_file.load: a bare JSON scalar is not an object")
    eq(reason, "not_object", "repo_file.load: scalar reason is 'not_object'")
    vim.fn.delete(path)
  end

  -- ------------------------------------------------------- unreadable file

  do
    local path = H.tmpfile(".json") -- never created on disk
    local result, reason, detail = repo_file.load(path, ALLOWED)
    eq(result, nil, "repo_file.load: a missing file returns no result")
    eq(reason, "read_failed", "repo_file.load: missing file reason is 'read_failed'")
    ok(
      type(detail) == "string" and #detail > 0,
      "repo_file.load: read_failed carries a detail message"
    )
  end
end
