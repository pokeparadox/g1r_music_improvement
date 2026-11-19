-- Pure helpers for the music test menu.  Entries and variants are plain
-- tables built by main.lua; keeping the navigation logic here makes it
-- testable without the engine.

local V

local M = {}

-- main.lua injects the already-loaded mod module; standalone tests can rely
-- on require("versions") from the mod directory.
function M.setVersions(versions)
  V = versions
end

local function versionsModule()
  if V then return V end
  local ok, module = pcall(require, "versions")
  if ok and type(module) == "table" then V = module return V end
  return { variantKind = function() return "g1" end,
    variantLabel = function(_) return "G1" end, MENU_KINDS = {} }
end

local function kind(variant)
  return versionsModule().variantKind(variant)
end

-- Version identity for cycling: each alternative kind is its own slot.
function M.versionKey(variant)
  return kind(variant)
end

function M.rightText(variant)
  return versionsModule().variantLabel(variant)
end

function M.title()
  return "MUSIC TEST"
end

-- Distinct version slots in canonical display order.
function M.versionKeys(entry)
  local present, keys = {}, {}
  local versions = versionsModule()
  for _, variant in ipairs(entry and entry.variants or {}) do
    present[M.versionKey(variant)] = true
  end
  for _, item in ipairs(versions.MENU_KINDS) do
    if present[item.key] then keys[#keys + 1] = item.key end
  end
  for key in pairs(present) do
    if not versions.variantLabel(key):match("^%?") then
      local known = false
      for _, existing in ipairs(keys) do if existing == key then known = true break end end
      if not known then keys[#keys + 1] = key end
    end
  end
  return keys
end

-- Variant for a kind slot.  Multiple source versions of one kind reuse the
-- slot; keep the first prepared record.
function M.select(entry, versionKey)
  for _, variant in ipairs(entry and entry.variants or {}) do
    if M.versionKey(variant) == versionKey then return variant end
  end
  return nil
end

-- Move `dir` slots from the current version and return that variant.
function M.cycle(entry, versionKey, dir)
  local keys = M.versionKeys(entry)
  if #keys == 0 then return nil end
  local index = 1
  for i, key in ipairs(keys) do
    if key == versionKey then index = i break end
  end
  index = ((index - 1 + (dir or 1)) % #keys) + 1
  return M.select(entry, keys[index])
end

return M
