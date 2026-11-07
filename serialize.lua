-- Serialize a plain improved-song def to a Lua chunk string for mod.cache.
local function serialize(value)
  local t = type(value)
  if t == "nil" then return "nil" end
  if t == "boolean" then return value and "true" or "false" end
  if t == "number" then return tostring(value) end
  if t == "string" then return string.format("%q", value) end
  if t ~= "table" then error("cannot serialize " .. t) end
  -- array?
  local isArray = true
  local n = 0
  for k in pairs(value) do
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
      isArray = false
      break
    end
    if k > n then n = k end
  end
  if isArray then
    for i = 1, n do
      if value[i] == nil then isArray = false break end
    end
  end
  local parts = {}
  if isArray then
    for i = 1, n do parts[#parts + 1] = serialize(value[i]) end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  for k, v in pairs(value) do
    local key
    if type(k) == "string" and k:match("^[_%a][_%w]*$") then
      key = k
    else
      key = "[" .. serialize(k) .. "]"
    end
    parts[#parts + 1] = key .. " = " .. serialize(v)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

return function(value)
  return "return " .. serialize(value) .. "\n"
end