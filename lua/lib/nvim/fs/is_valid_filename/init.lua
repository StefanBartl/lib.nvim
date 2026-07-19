---@module 'lib.nvim.fs.is_valid_filename'
--- Validate a bare filename (not a full path) for filesystem safety.
---
--- Rejects the characters that are illegal in a filename on Windows
--- (`\/:*?"<>|`), which is also a safe, conservative subset to reject on
--- POSIX (where only `/` and NUL are truly illegal) — staying cross-platform
--- correct is more valuable here than allowing a few extra bytes POSIX would
--- technically permit. Also rejects an embedded NUL, an empty string, and a
--- whitespace-only string.
---
--- Upstreamed from reposcope.nvim's `utils.protection.is_valid_filename`
--- (same rules), to close a gap in `lib.nvim.fs.create_entry`: that module
--- previously only checked for a non-empty string, so a name containing one
--- of these characters failed at the raw `mkdirp`/`io.open` syscall instead
--- of with a clean message before attempting it.

local INVALID_CHARS = '[\\/:*?"<>|%z]'

---@param name string|nil
---@return boolean ok
---@return string|nil err  Reason the name is invalid; nil when ok is true
return function(name)
  if name == nil then
    return false, "filename is nil"
  end
  if type(name) ~= "string" then
    return false, "filename must be a string"
  end
  if name == "" then
    return false, "filename is empty"
  end
  if name:match("^%s*$") then
    return false, "filename is only whitespace"
  end
  if name:match(INVALID_CHARS) then
    return false, "filename contains invalid characters"
  end
  return true, nil
end
