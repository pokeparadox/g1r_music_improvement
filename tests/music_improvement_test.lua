-- Standalone: luajit mods/g1r_music_improvement/tests/music_improvement_test.lua
-- Asserts the generic music improvement path no longer authors a dedicated
-- improved Pallet Town theme, cache regeneration stays scoped, and music.select
-- defers unmapped songs.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = T.fixtures.load()
Data.audio = Data.audio or {}
Data.audio.songs = Data.audio.songs or {}
Data.audio.songs.Music_CacheCleanupTest = {}

local run = T.sdk.loadMod("mods/g1r_music_improvement", { data = Data })
T.check(#run.errors == 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local musicMod = run.mods.g1r_music_improvement
if musicMod and musicMod.exports then
  musicMod.exports.prepareAll()
end
local cache
if musicMod then
  local _, cacheApi = require("src.mods.ImportAccess").new(musicMod.manifest, run.loader.fs)
  cache = cacheApi
end
local exports = musicMod and musicMod.exports

-- ------- regeneration uses only the scoped mod cache API

T.check(cache and type(cache.info) == "function"
    and type(cache.delete) == "function"
    and type(cache.write) == "function",
  "mod cache exposes info, delete, and write")
if cache and exports and type(cache.delete) == "function" then
  local legacyId
  for id in pairs(Data.audio and Data.audio.songs or {}) do
    if not tostring(id):match("^Music_Improved") then
      legacyId = id
      break
    end
  end
  local legacyPath
  if legacyId then
    legacyPath = "songs/0.4.6_true_"
      .. tostring(legacyId):gsub("[^%w_]", "_") .. ".lua"
    cache:write(legacyPath, "legacy cache")
    cache:write("songs/index.txt", "")
  end

  local deleted = {}
  local originalDelete = cache.delete
  cache.delete = function(self, path)
    deleted[#deleted + 1] = path
    return originalDelete(self, path)
  end
  exports.regenerateCache()
  cache.delete = originalDelete

  local deletedIndex = false
  local onlySongCache = true
  for _, path in ipairs(deleted) do
    if path == "songs/index.txt" then deletedIndex = true end
    if path:sub(1, 6) ~= "songs/" then onlySongCache = false end
  end
  T.check(deletedIndex, "regeneration deletes its generated-file index")
  T.check(#deleted > 0, "regeneration deletes cached songs through mod.cache")
  T.check(onlySongCache, "regeneration leaves unrelated cache namespaces untouched")
  if legacyPath then
    local deletedLegacy = false
    for _, path in ipairs(deleted) do
      if path == legacyPath then deletedLegacy = true end
    end
    T.check(deletedLegacy, "regeneration deletes known legacy cache filenames")
  end
  exports.prepareAll()
end

-- ------- no authored fallback remains

Data.audio = Data.audio or {}
Data.audio.songs = Data.audio.songs or {}
T.check(Data.audio.songs.Music_ImprovedPalletTown == nil,
  "no authored ImprovedPalletTown song remains")

-- ------- the hook defers songs without an improved mapping

local function select(song_, ctx)
  return Runtime.call("music.select", function(chosen) return chosen end, song_, ctx)
end
T.eq(select("Music_PalletTown", { reason = "map", mapId = "PALLET_TOWN" }),
  "Music_PalletTown", "Pallet Town defers without an authored improvement")
T.eq(select("Music_Routes1", { reason = "map", mapId = "ROUTE_1" }),
  "Music_Routes1", "every other map defers to the vanilla choice")
T.eq(select("Music_PalletTown", nil), "Music_PalletTown",
  "a direct play with no context defers")

if cache and exports and type(cache.delete) == "function" then
  local failurePath = "songs/test_delete_failure.lua"
  cache:write(failurePath, "generated cache")
  cache:write("songs/index.txt", failurePath .. "\n")
  local originalDelete = cache.delete
  cache.delete = function() return false end
  local game = {
    mods = { modOptions = { g1r_music_improvement = { enabled = false } } },
  }
  exports.regenerateCache(game)
  cache.delete = originalDelete
  T.eq(game.mods.modOptions.g1r_music_improvement.enabled, false,
    "regeneration stops before changing settings when cache deletion fails")
end

run.release()
T.finish("g1r_music_improvement")
