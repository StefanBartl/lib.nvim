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

---Split `text` into words on `_`, `-`, whitespace and inner lower->upper boundaries, so "fooBar", "foo_bar" and
---"foo-bar" all give { "foo", "bar" }. Digits stay inside their word.
---@param text string
---@return string[]
local function split_words(text)
  local words = {}
  for chunk in text:gmatch("[%a%d]+") do
    local start = 1
    for i = 2, #chunk do
      local prev, cur = chunk:sub(i - 1, i - 1), chunk:sub(i, i)
      if cur:match("%u") and prev:match("%l") then
        words[#words + 1] = chunk:sub(start, i - 1)
        start = i
      end
    end
    words[#words + 1] = chunk:sub(start)
  end
  return words
end

---Detect the casing style of a token or identifier: `"upper"`, `"lower"`, `"title"` (one capitalised word),
---`"camel"` or `"pascal"` (several words in mixed case, by the first letter). A separator-joined name such as
---`foo_bar` or `FOO_BAR` is `"lower"` / `"upper"`: the style is about letter case, not the separator.
---nil when there is no letter to judge.
---@param text string|nil
---@return "upper"|"lower"|"title"|"camel"|"pascal"|nil
function M.identifier_style(text)
  if not text or text == "" or not text:match("%a") then
    return nil
  end
  local has_upper, has_lower = text:match("%u") ~= nil, text:match("%l") ~= nil
  if has_upper and not has_lower then
    return "upper"
  end
  if has_lower and not has_upper then
    return "lower"
  end
  if #split_words(text) <= 1 then
    return "title"
  end
  return text:sub(1, 1):match("%u") and "pascal" or "camel"
end

---Re-case `text` in `style` (as `identifier_style` returns it). `"camel"` and `"pascal"` re-join the words of
---`text` without separators; the other styles change letter case only. An unknown or nil style, or empty
---text, returns `text` unchanged (nil gives `""`).
---@param text string|nil
---@param style "upper"|"lower"|"title"|"camel"|"pascal"|nil
---@return string
function M.apply_style(text, style)
  if not text or text == "" or not style then
    return text or ""
  end
  if style == "upper" then
    return text:upper()
  elseif style == "lower" then
    return text:lower()
  elseif style == "title" then
    return text:sub(1, 1):upper() .. text:sub(2):lower()
  elseif style == "camel" or style == "pascal" then
    local words = split_words(text)
    if #words == 0 then
      return text
    end
    local out = {}
    for i, w in ipairs(words) do
      local lw = w:lower()
      out[i] = (i == 1 and style == "camel") and lw or (lw:sub(1, 1):upper() .. lw:sub(2))
    end
    return table.concat(out)
  end
  return text
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
    return (
      str:gsub("(%a[%w']*)", function(word)
        return word:sub(1, 1):upper() .. word:sub(2):lower()
      end)
    )
  end
  return str
end

---@type Lib.Strings.Case
return M
