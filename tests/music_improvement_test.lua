-- Standalone: luajit mods/g1r_music_improvement/tests/music_improvement_test.lua
-- Asserts the generic music improvement path no longer authors a dedicated
-- improved Pallet Town theme, cache regeneration stays scoped, and music.select
-- defers unmapped songs.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = T.fixtures.fresh()
Data.audio = Data.audio or {}
Data.audio.songs = {}
Data.audio.gen2 = true
local gen2SongId = "Music_Gen2CacheTest"
local gen2Address, gen2Bank = 0x7FFE, 0x7E
Data.audio.songs[gen2SongId] = {
  address = gen2Address,
  bank = gen2Bank,
}
local gen1SongId = "Music_Gen1CacheTest"
local gen1Address, gen1Bank = 0x7FFC, 0x7F
Data.audio.songs[gen1SongId] = {
  address = gen1Address,
  bank = gen1Bank,
  engine = "gen1",
}

local CoreData = require("src.core.Data")
local previousAudio = CoreData.audio
CoreData.audio = Data.audio

local ChipSynth = require("src.core.ChipSynth")
local originalNewEngine = ChipSynth.newEngine
local gen2HeaderSeen
local gen1HeaderSeen
local function mockEngine()
  local engine = { tempo = 0x100, channels = {} }
  local channel = {
    engine = engine,
    hardware = 1,
    speed = 12,
    timeTicks = 0,
    ended = false,
  }
  function channel:frequency(note, octave)
    return 1000 + note * 2 + octave
  end
  function channel:nextEvent()
    if self.emitted then return nil end
    self.emitted = true
    self.timeTicks = 12 * 0x100
    return { register = 1000, volume = 8, fade = 0, duty = 1 }
  end
  engine.channels[1] = channel
  return engine
end
ChipSynth.newEngine = function(data, header, options)
  if type(header) == "table" and header.address == gen2Address
      and header.bank == gen2Bank then
    gen2HeaderSeen = header
    return mockEngine()
  end
  if type(header) == "table" and header.address == gen1Address
      and header.bank == gen1Bank then
    gen1HeaderSeen = header
    return mockEngine()
  end
  return originalNewEngine(data, header, options)
end

local GameVersion = require("src.core.GameVersion")
local previousVersion = GameVersion.get()
GameVersion.set("gold")
local Version = require("src.core.Version")
local previousModApi = Version.modApi
Version.modApi = math.max(Version.modApi or 0, 3)

local run = T.sdk.loadMod("mods/g1r_music_improvement", { data = Data, generation = 2 })
T.check(#run.errors == 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local musicMod = run.mods.g1r_music_improvement
local runFs = run.loader.fs
local testCache = {}
local removed = {}
local deleted = {}
local failRemoval = false
local logRemoval = false
local fsRead, fsWrite, fsInfo = runFs.read, runFs.write, runFs.getInfo
runFs.write = function(path, body)
  removed[path] = nil
  testCache[path] = body
  return fsWrite(path, body)
end
runFs.read = function(path)
  if removed[path] then return nil end
  if testCache[path] ~= nil then return testCache[path] end
  return fsRead(path)
end
runFs.getInfo = function(path)
  if removed[path] then return nil end
  if testCache[path] ~= nil then return { type = "file" } end
  return fsInfo(path)
end
runFs.remove = function(path)
  if failRemoval then return false end
  if logRemoval then deleted[#deleted + 1] = path end
  testCache[path] = nil
  removed[path] = true
  return true
end
local exports = run.loader.exports and run.loader.exports.g1r_music_improvement
  or (musicMod and musicMod.exports)
if exports then
  exports.prepareAll()
end
local cache
if musicMod then
  local _, cacheApi = require("src.mods.ImportAccess").new(musicMod.manifest, runFs)
  cache = cacheApi
end

T.eq(gen2HeaderSeen and gen2HeaderSeen.engine, "gen2",
  "Gen2 engine selector reaches ChipSynth")
T.eq(gen1HeaderSeen and gen1HeaderSeen.engine, "gen1",
  "Gen1 engine selector reaches ChipSynth")
local gen2CachePath = "songs/gold_" .. tostring(musicMod and musicMod.manifest
  and musicMod.manifest.version or "0")
  .. "_true_Music_Gen2CacheTest.lua"
local gen2Bytes = cache and cache:read(gen2CachePath)
local gen2Cached
if type(gen2Bytes) == "string" then
  local chunk = load(gen2Bytes)
  if chunk then gen2Cached = chunk() end
end
T.eq(gen2Cached and gen2Cached.chip and gen2Cached.chip.engine, 1,
  "generated base cache uses the normalized chip-program format")
T.eq(gen2Cached and gen2Cached.generation, 1,
  "generated base cache is pinned to the Gen1 decoder")
T.eq(gen2Cached and gen2Cached.extra and gen2Cached.extra.left
    and gen2Cached.extra.left.chip and gen2Cached.extra.left.chip.engine,
  1, "generated harmony cache uses the normalized chip-program format")
T.eq(gen2Cached and gen2Cached.extra and gen2Cached.extra.left
    and gen2Cached.extra.left.generation, 1,
  "generated harmony cache is pinned to the Gen1 decoder")

-- ------- regeneration uses only the scoped mod cache API

T.check(cache and type(cache.info) == "function"
    and type(cache.delete) == "function"
    and type(cache.write) == "function",
  "mod cache exposes info, delete, and write")
if cache and exports and type(cache.delete) == "function" then
  local foreignPath = "songs/crystal_0.4.6_true_Music_Foreign.lua"
  cache:write(foreignPath, "foreign cache")

  for i = #deleted, 1, -1 do deleted[i] = nil end
  logRemoval = true
  exports.regenerateCache()
  logRemoval = false

  local deletedIndex = false
  local onlySongCache = true
  for _, path in ipairs(deleted) do
    local rel = path:match("^mod_cache/[^/]+/(.*)$") or path
    if rel == "songs/gold_index.txt" then deletedIndex = true end
    if rel:sub(1, 11) ~= "songs/gold_" then onlySongCache = false end
  end
  T.check(deletedIndex, "regeneration deletes its generated-file index")
  T.check(#deleted > 0, "regeneration deletes cached songs through mod.cache")
  T.check(onlySongCache, "regeneration leaves unrelated cache namespaces untouched")
  local deletedForeign = false
  for _, path in ipairs(deleted) do
    local rel = path:match("^mod_cache/[^/]+/(.*)$") or path
    if rel == foreignPath then deletedForeign = true end
  end
  T.check(not deletedForeign, "regeneration never deletes another game's cache")
  T.eq(cache:read(foreignPath), "foreign cache", "foreign cache survives regeneration")
  exports.prepareAll()
end

-- ------- no authored fallback remains

Data.audio = Data.audio or {}
Data.audio.songs = Data.audio.songs or {}
T.check(Data.audio.songs.Music_ImprovedPalletTown == nil,
  "no authored ImprovedPalletTown song remains")
T.check(type(Data.audio.songs.Music_ImprovedGen1CacheTest) == "table",
  "generated song reaches live Data after registries freeze")
local listed = false
for _, id in ipairs(exports.musicIds({ data = Data })) do
  if id == "Music_ImprovedGen1CacheTest" then listed = true end
end
T.check(listed, "generated song is visible to the music test list")

-- ------- the hook defers songs without an improved mapping

local function select(song_, ctx)
  return Runtime.call("music.select", function(chosen) return chosen end, song_, ctx)
end
T.eq(select("Music_PalletTown", { reason = "map", mapId = "PALLET_TOWN" }),
  "Music_PalletTown", "Pallet Town defers without an authored improvement")
T.eq(select("Music_Routes1", { reason = "map", mapId = "ROUTE_1" }),
  "Music_Routes1", "every other map defers to the vanilla choice")
T.eq(select("Music_PalletTown", nil), "Music_PalletTown",
  "a direct play with no context defers when unmapped")
T.eq(select(gen1SongId, { reason = "direct" }),
  "Music_ImprovedGen1CacheTest",
  "title and other direct cues still use their enhanced mapping")
T.eq(select(gen1SongId, { reason = "jukebox" }), gen1SongId,
  "music test keeps explicit base-song playback")
T.eq(select(gen2SongId, { reason = "map" }),
  "Music_ImprovedGen2CacheTest", "Gen2 song selection uses its enhanced mapping")
T.eq(select(gen1SongId, { reason = "map" }),
  "Music_ImprovedGen1CacheTest", "Gen1 song selection uses its enhanced mapping")

local optionRows = Runtime.call("ui.options.rows",
  function(_, rows) return rows end, { data = Data },
  { { id = "sound", label = "SOUND" }, { id = "text_speed", label = "TEXT SPEED" } })
T.eq(optionRows[2] and optionRows[2].musicImprovementId,
  "music_improvement_enabled",
  "music controls are visible immediately after the first options row")
T.eq(optionRows[3] and optionRows[3].musicImprovementId, "music_improvement_jukebox",
  "Music Test is reachable from the visible options group")
T.eq(optionRows[4] and optionRows[4].musicImprovementId, "music_improvement_regenerate",
  "cache regeneration is reachable from the visible options group")

if cache and exports and type(cache.delete) == "function" then
  local failurePath = "songs/gold_test_delete_failure.lua"
  cache:write(failurePath, "generated cache")
  cache:write("songs/gold_index.txt", failurePath .. "\n")
  failRemoval = true
  local game = {
    mods = { modOptions = { g1r_music_improvement = { enabled = false } } },
  }
  exports.regenerateCache(game)
  failRemoval = false
  T.eq(game.mods.modOptions.g1r_music_improvement.enabled, false,
    "regeneration stops before changing settings when cache deletion fails")
end

ChipSynth.newEngine = originalNewEngine
CoreData.audio = previousAudio
Version.modApi = previousModApi
GameVersion.set(previousVersion)
run.release()
T.finish("g1r_music_improvement")
