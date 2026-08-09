-- Text helpers that have to cope with more than A-Z.
--
-- Lua's string.lower only touches ASCII, so a Cyrillic or accented name keeps
-- its capitals and a case-insensitive search quietly stops being case
-- insensitive: "Проект" and "проект" never match. This lowercases the two ranges
-- that actually turn up in a media library - Cyrillic and the accented Latin of
-- western Europe - by arithmetic on the UTF-8 bytes rather than a table of
-- thousands of mappings, which keeps it fast enough for a filter that runs on
-- every keystroke.
--
-- It is deliberately not full Unicode case folding. Greek, Turkish dotted i and
-- the rest would each need their own rules, and nobody has asked.

local M = {}

-- Cyrillic in UTF-8:
--   А-П  U+0410-041F  D0 90..D0 9F  ->  а-п  U+0430-043F  D0 B0..D0 BF
--   Р-Я  U+0420-042F  D0 A0..D0 AF  ->  р-я  U+0450-044F  D1 80..D1 8F
--   Ё    U+0401       D0 81         ->  ё    U+0451       D1 91
-- Latin-1 supplement:
--   À-Þ  U+00C0-00DE  C3 80..C3 9E  ->  à-þ  U+00E0-00FE  C3 A0..C3 BE
--   with U+00D7 (the multiplication sign) sitting in the middle and not a letter.
function M.lower(value)
  value = tostring(value or "")
  if not value:find("[\128-\255]") then return value:lower() end
  local out = {}
  local i, n = 1, #value
  while i <= n do
    local b1 = value:byte(i)
    if b1 < 0x80 then
      out[#out + 1] = string.char(b1):lower()
      i = i + 1
    elseif b1 == 0xD0 and i < n then
      local b2 = value:byte(i + 1)
      if b2 == 0x81 then
        out[#out + 1] = "\209\145"
      elseif b2 >= 0x90 and b2 <= 0x9F then
        out[#out + 1] = string.char(0xD0, b2 + 0x20)
      elseif b2 >= 0xA0 and b2 <= 0xAF then
        out[#out + 1] = string.char(0xD1, b2 - 0x20)
      else
        out[#out + 1] = string.char(b1, b2)
      end
      i = i + 2
    elseif b1 == 0xC3 and i < n then
      local b2 = value:byte(i + 1)
      if b2 >= 0x80 and b2 <= 0x9E and b2 ~= 0x97 then
        out[#out + 1] = string.char(0xC3, b2 + 0x20)
      else
        out[#out + 1] = string.char(b1, b2)
      end
      i = i + 2
    else
      -- Anything else is copied whole, so a character this does not know about
      -- comes out unharmed rather than mangled.
      local len = b1 >= 0xF0 and 4 or b1 >= 0xE0 and 3 or b1 >= 0xC0 and 2 or 1
      out[#out + 1] = value:sub(i, i + len - 1)
      i = i + len
    end
  end
  return table.concat(out)
end

return M
