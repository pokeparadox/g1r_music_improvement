-- Pure helpers for the music test menu.  Entries and variants are plain
-- tables built by main.lua; keeping the navigation logic here makes it
-- testable without the engine.

local M = {}

-- Version identity for cycling: native playback is its own slot.
function M.versionKey(variant)
  if not variant then return "" end
  if variant.mix or (variant.candidate and variant.candidate.mix) then
    return "MIX_" .. tostring(variant.version or "")
  end
  return tostring(variant.generation or "")
end

function M.rightText(variant)
  if not variant then return "" end
  local text = "G" .. tostring(variant.generation or 1)
  if variant.mix or (variant.candidate and variant.candidate.mix) then
    return "G3 MIX"
  end
  if not variant.native then
    text = text .. (variant.improved and " IMP" or " STK")
  end
  return text
end

function M.title(improved)
  return improved and "MUSIC TEST [IMP]" or "MUSIC TEST [STK]"
end

-- Distinct version slots in display order, preserving entry order.
function M.versionKeys(entry)
  local keys, seen = {}, {}
  for _, variant in ipairs(entry and entry.variants or {}) do
    local key = M.versionKey(variant)
    if not seen[key] then
      seen[key] = true
      keys[#keys + 1] = key
    end
  end
  return keys
end

-- Variant for a version slot at the requested improved/stock mode.
-- Falls back to the other kind when that combination is not available.
function M.select(entry, versionKey, improved)
  local fallback
  local nativeVariant
  for _, variant in ipairs(entry and entry.variants or {}) do
    if M.versionKey(variant) == versionKey then
      if variant.native then
        nativeVariant = nativeVariant or variant
      end
      if (not variant.native) and variant.improved == improved then
        return variant
      elseif variant.native and improved == false then
        return variant
      elseif not variant.native then
        fallback = fallback or variant
      end
    end
  end
  if improved == false and nativeVariant then return nativeVariant end
  if fallback then return fallback end
  return nativeVariant
end

-- Move `dir` slots from the current version and return that variant.
function M.cycle(entry, versionKey, dir, improved)
  local keys = M.versionKeys(entry)
  if #keys == 0 then return nil end
  local index = 1
  for i, key in ipairs(keys) do
    if key == versionKey then index = i break end
  end
  index = ((index - 1 + (dir or 1)) % #keys) + 1
  return M.select(entry, keys[index], improved)
end

return M
