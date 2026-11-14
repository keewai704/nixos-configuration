--!nonstrict
local M = {}

local BULLET = "\u{2022}"

local TYPE_GLYPHS = {
  Login = "world",
  Card = "credit-card",
  Identity = "id-badge-2",
  Note = "note",
  ["SSH Key"] = "key",
}

local TYPE_KEYS = {
  Login = "type.login",
  Card = "type.card",
  Identity = "type.identity",
  Note = "type.note",
  ["SSH Key"] = "type.ssh",
}

function M.typeGlyph(entryType)
  return TYPE_GLYPHS[entryType] or "lock"
end

function M.typeKey(entryType)
  return TYPE_KEYS[entryType] or "type.login"
end

function M.repeatBullet(count)
  return string.rep(BULLET, count)
end

function M.mask()
  return M.repeatBullet(8)
end

function M.onlyDigits(value)
  return (string.gsub(tostring(value), "[^%d]", ""))
end

function M.cardNumber(number)
  local digits = M.onlyDigits(number)
  local groups = {}
  local index = 1
  while index <= #digits do
    table.insert(groups, string.sub(digits, index, index + 3))
    index = index + 4
  end
  return table.concat(groups, " ")
end

function M.maskCardNumber(number)
  local digits = M.onlyDigits(number)
  if #digits <= 4 then
    return M.repeatBullet(4)
  end
  return table.concat({ M.repeatBullet(4), M.repeatBullet(4), M.repeatBullet(4), string.sub(digits, -4) }, " ")
end

function M.expiry(month, year)
  local monthText = noctalia.string.trim(tostring(month or ""))
  local yearText = noctalia.string.trim(tostring(year or ""))
  if monthText == "" and yearText == "" then
    return nil
  end
  if #monthText == 1 then
    monthText = "0" .. monthText
  end
  if monthText == "" then
    return yearText
  end
  if yearText == "" then
    return monthText
  end
  return monthText .. "/" .. yearText
end

function M.identityName(identity)
  local parts = {}
  for _, key in { "title", "first_name", "middle_name", "last_name" } do
    local value = identity[key]
    if type(value) == "string" and noctalia.string.trim(value) ~= "" then
      table.insert(parts, noctalia.string.trim(value))
    end
  end
  return table.concat(parts, " ")
end

function M.addressLines(identity)
  local lines = {}
  for _, key in { "address1", "address2", "address3" } do
    local value = identity[key]
    if type(value) == "string" and noctalia.string.trim(value) ~= "" then
      table.insert(lines, noctalia.string.trim(value))
    end
  end
  local region = {}
  for _, key in { "city", "state" } do
    local value = identity[key]
    if type(value) == "string" and noctalia.string.trim(value) ~= "" then
      table.insert(region, noctalia.string.trim(value))
    end
  end
  local regionText = table.concat(region, ", ")
  local postal = identity.postal_code
  if type(postal) == "string" and noctalia.string.trim(postal) ~= "" then
    regionText = regionText == "" and noctalia.string.trim(postal) or regionText .. " " .. noctalia.string.trim(postal)
  end
  if regionText ~= "" then
    table.insert(lines, regionText)
  end
  local country = identity.country
  if type(country) == "string" and noctalia.string.trim(country) ~= "" then
    table.insert(lines, noctalia.string.trim(country))
  end
  return table.concat(lines, "\n")
end

function M.date(iso)
  if type(iso) ~= "string" then
    return ""
  end
  local day = string.match(iso, "^(%d%d%d%d%-%d%d%-%d%d)")
  if day ~= nil then
    return day
  end
  return iso
end

function M.nonEmpty(value)
  if type(value) ~= "string" then
    return nil
  end
  local trimmed = noctalia.string.trim(value)
  if trimmed == "" then
    return nil
  end
  return trimmed
end

return M
