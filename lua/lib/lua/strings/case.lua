---@module 'lib.lua.strings.case'
--- Case-shape detection/reapplication and word-casing transforms, pure Lua.
--- Complements the case-*format* helpers already in `lib.lua.strings.core`
--- (snake_case/camel_case/kebab_case/capitalize/...): this module is about
--- detecting/preserving a word's existing casing shape and about sentence-
--- and title-casing whole strings.

local M = {}

---Detect the casing "shape" of a word.
---@param word string
---@return "lower"|"upper"|"capital"|"mixed"
function M.case_shape(word)
  if word == word:lower() then
    return "lower"
  end
  if word == word:upper() then
    return "upper"
  end
  if word:sub(1, 1) == word:sub(1, 1):upper() and word:sub(2) == word:sub(2):lower() then
    return "capital"
  end
  return "mixed"
end

---Reapply a previously-detected shape onto (possibly different) text.
---"mixed" is a no-op (there is no single rule to reapply).
---@param word string
---@param shape "lower"|"upper"|"capital"|"mixed"
---@return string
function M.apply_shape(word, shape)
  if shape == "lower" then
    return word:lower()
  elseif shape == "upper" then
    return word:upper()
  elseif shape == "capital" then
    return word:sub(1, 1):upper() .. word:sub(2):lower()
  end
  return word
end

---Change the casing of a whole string.
---@param str string
---@param mode "title"|"sentence"|"upper"|"lower"
---@return string
function M.change_case(str, mode)
  if mode == "upper" then
    return str:upper()
  elseif mode == "lower" then
    return str:lower()
  elseif mode == "sentence" then
    local lowered = str:lower()
    return (lowered:gsub("^%s*(%a)", string.upper, 1))
  elseif mode == "title" then
    return (str:gsub("(%a[%w']*)", function(word)
      return word:sub(1, 1):upper() .. word:sub(2):lower()
    end))
  end
  return str
end

return M
