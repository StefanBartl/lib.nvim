---@module 'lib.nvim.cross.fs.separators.has_win_sep'

---@param s string
---@return string|nil # the matched drive-prefix substring, or nil on no match
return function(s)
  -- "E:/path/.." or "C:\path\.."
  return s:match("^[A-Za-z]:[\\/]")
end
