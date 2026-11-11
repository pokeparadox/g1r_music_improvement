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
local tempoSongId = "Music_Gen2TempoTest"
local tempoAddress, tempoBank = 0x7FFA, 0x7D
Data.audio.songs[tempoSongId] = {
  address = tempoAddress,
  bank = tempoBank,
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
local function mockEngine(includeNoise)
  local engine = { tempo = 0x100, generation = 1, channels = {} }
  local channel = {
    engine = engine,
    hardware = 1,
    speed = 12,
    volume = 8,
    fade = 0,
    timeTicks = 0,
    ended = false,
    address = 0x100,
    eventIndex = 0,
  }
  local loopBytes = {
    [0x200] = 0xFE,
    [0x201] = 0,
    [0x202] = 0x05,
    [0x203] = 0x01,
  }
  function channel:byte()
    local value = loopBytes[self.address] or 0
    self.address = self.address + 1
    return value
  end
  function channel:word()
    local low, high = self:byte(), self:byte()
    return low + high * 0x100
  end
  function channel:frequency(note, octave)
    return 1000 + note * 2 + octave
  end
  function channel:nextEvent()
    self.eventIndex = self.eventIndex + 1
    local events = {
      { address = 0x100, speed = 12, ticks = 12 * 0x100 },
      { address = 0x102, speed = 6, ticks = 6 * 0x100, silence = true },
      { address = 0x104, speed = 6, ticks = 6 * 0x100 },
    }
    local event = events[self.eventIndex]
    if not event then
      self.ended = true
      self.address = 0x204
      return nil
    end
    self.address = event.address
    self:byte()
    self:byte()
    self.address = event.address + 2
    self.speed = event.speed
    self.timeTicks = self.timeTicks + event.ticks
    if event.silence then return { silence = true } end
    return { register = 1000, volume = 8, fade = 0, duty = 1 }
  end
  engine.channels[1] = channel
  if includeNoise then
    local noiseChannel = {
      engine = engine,
      hardware = 4,
      noise = true,
      frameTicks = 256,
      speed = 12,
      timeTicks = 0,
      ended = false,
      address = 0x300,
      eventIndex = 0,
    }
    function noiseChannel:byte()
      local value = 0
      self.address = self.address + 1
      return value
    end
    function noiseChannel:word()
      local low, high = self:byte(), self:byte()
      return low + high * 0x100
    end
    function noiseChannel:nextEvent()
      self.eventIndex = self.eventIndex + 1
      if self.eventIndex == 1 then
        self.address = 0x301
        self.timeTicks = 12 * 0x100
        return {
          noise = true,
          drum = {{
            startSample = 0,
            endSample = math.floor(
              19 * 256 * ChipSynth.SAMPLE_RATE / 15360 + 0.5),
            volume = 8,
            fade = 0,
            parameter = 51,
          }},
        }
      end
      self.ended = true
      self.address = 0x304
      return nil
    end
    engine.channels[2] = noiseChannel
  end
  return engine
end
ChipSynth.newEngine = function(data, header, options)
  if type(header) == "table" and header.address == tempoAddress
      and header.bank == tempoBank then
    local engine = { tempo = 0x100, generation = 2, channels = {} }
    local function stub(ch)
      ch.engine = engine
      ch.speed = 12
      ch.volume = 8
      ch.fade = 0
      ch.timeTicks = 0
      ch.ended = false
      ch.eventIndex = 0
      function ch:byte()
        local value = 0
        self.address = self.address + 1
        return value
      end
      function ch:word()
        local low, high = self:byte(), self:byte()
        return low + high * 0x100
      end
      function ch:frequency(note, octave)
        return 1000 + note * 2 + octave
      end
      return ch
    end
    local ch1 = stub({ hardware = 1, noteLength = 8, address = 0x100 })
    function ch1:nextEvent()
      self.eventIndex = self.eventIndex + 1
      if self.eventIndex == 1 then
        self.address = 0x101
        self:byte(); self:byte()
        self.address = 0x103
        self.timeTicks = 8 * 0x100
        return { register = 1000, volume = 8, fade = 0, duty = 1 }
      elseif self.eventIndex == 2 then
        engine.tempo = 0x86
        self.address = 0x105
        self:byte(); self:byte()
        self.address = 0x107
        self.timeTicks = 16 * 0x100
        return { register = 1000, volume = 8, fade = 0, duty = 1 }
      end
      self.ended = true
      self.address = 0x109
      return nil
    end
    engine.channels[1] = ch1
    local ch2 = stub({ hardware = 2, noteLength = 8, address = 0x200 })
    function ch2:nextEvent()
      self.eventIndex = self.eventIndex + 1
      if self.eventIndex == 1 then
        self.address = 0x201
        self:byte(); self:byte()
        self.address = 0x203
        self.timeTicks = 8 * 0x100
        return { register = 1000, volume = 8, fade = 0, duty = 1 }
      end
      self.ended = true
      self.address = 0x205
      return nil
    end
    engine.channels[2] = ch2
    return engine
  end
  if type(header) == "table" and header.address == gen2Address
      and header.bank == gen2Bank then
    gen2HeaderSeen = header
    return mockEngine()
  end
  if type(header) == "table" and header.address == gen1Address
      and header.bank == gen1Bank then
    gen1HeaderSeen = header
    return mockEngine(true)
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
local gen1CachePath = "songs/gold_" .. tostring(musicMod and musicMod.manifest
  and musicMod.manifest.version or "0")
  .. "_true_" .. gen1SongId .. ".lua"
local gen1Bytes = cache and cache:read(gen1CachePath)
local gen1Cached
if type(gen1Bytes) == "string" then
  local chunk = load(gen1Bytes)
  if chunk then gen1Cached = chunk() end
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
local generatedDrum = gen1Cached and gen1Cached.chip
  and gen1Cached.chip.drums and gen1Cached.chip.drums[1]
T.eq(generatedDrum and #generatedDrum, 2,
  "long source drum segments are split only at ChipAsm's 16-frame limit")
T.eq(generatedDrum and generatedDrum[#generatedDrum]
    and generatedDrum[#generatedDrum].endSample, 19 * 735,
  "generated drum segments preserve the source envelope duration")

if gen2Cached then
  local timingEngine = originalNewEngine(Data, gen2Cached, { allowLoops = true })
  local timingChannel = timingEngine.channels[1]
  local timing = {}
  for index = 1, 5 do
    local event = timingChannel:nextEvent()
    T.check(event ~= nil, "generated speed-change test event " .. index .. " exists")
    timing[index] = timingChannel.timeTicks
  end
  T.eq(timing[1], 12 * 0x100, "first generated note keeps its source duration")
  T.eq(timing[2], 18 * 0x100, "speed changes are applied to source rests")
  T.eq(timing[3], 24 * 0x100, "speed changes are emitted despite unchanged volume")
  T.eq(timing[4], 30 * 0x100, "generated loop starts at the source loop target")
  T.eq(timing[5], 36 * 0x100, "source loop body repeats at its own duration")
end

local improvement = assert(loadfile("mods/g1r_music_improvement/improve.lua"))()
local loopedExtra = improvement.extra({
  tempo = 0x100,
  channels = {{
    hw = 1,
    program = {
      { pitch = 0, len = 2 },
      { pitch = 1, len = 3 },
      { loop = { count = 0, to = 2 } },
    },
  }},
}, {})
local extraProgram = loopedExtra.left.channels[1].program
local extraLoop
for _, event in ipairs(extraProgram) do
  if event.loop then extraLoop = event.loop break end
end
T.eq(extraLoop and extraProgram[extraLoop.to]
    and extraProgram[extraLoop.to].octave, 6,
  "transposed harmony loops follow inserted octave and instrument events")

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

-- ------- one-shot jingles restore the map theme after label rewrite

local ChipAudioModule = require("src.core.ChipAudio")
local MusicModule = require("src.core.Music")
local realPlayMusic = ChipAudioModule.playMusic
local function fakeSource()
  return {
    isPlaying = function() return true end,
    setLooping = function() end,
    play = function() end,
    pause = function() end,
    stop = function() end,
    setVolume = function() end,
    getVolume = function() return 1 end,
    setPitch = function() end,
  }
end
MusicModule.stop()
local savedLoveAudio = love.audio
love.audio = love.audio or {}
ChipAudioModule.playMusic = function() return fakeSource() end
T.check(MusicModule.playOnce(Data, gen1SongId),
  "playOnce arms restore when select hook rewrites the jingle label")
T.check(MusicModule.oneShotPlaying(),
  "one-shot restore stays armed while the enhanced jingle plays")
MusicModule.stop()
ChipAudioModule.playMusic = realPlayMusic
love.audio = savedLoveAudio

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
-- Shared Gen2 tempo must not leak between channels during translation.
local tempoImproved = Data.audio.songs["Music_ImprovedGen2TempoTest"]
T.check(type(tempoImproved) == "table",
  "tempo test song is translated")
if type(tempoImproved) == "table" and type(tempoImproved.channels) == "table"
    and tempoImproved.channels[2] then
  local hasTempo = false
  for _, event in ipairs(tempoImproved.channels[2].program or {}) do
    if event.tempo ~= nil then hasTempo = true end
  end
  T.check(not hasTempo,
    "a plain channel does not restamp shared tempo")
end

T.finish("g1r_music_improvement")
