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
-- Gold's Music_AfterTheRivalFight loops into Music_LookRival's byte stream.
local crossSongId = "Music_Gen2CrossLoopTest"
local crossAddress, crossBank = 0x7FFA, 0x7D
Data.audio.songs[crossSongId] = {
  address = crossAddress,
  bank = crossBank,
}

local noLoopSongId = "Music_Gen2NoLoopTest"
local noLoopAddress, noLoopBank = 0x7FF8, 0x7C
Data.audio.songs[noLoopSongId] = {
  address = noLoopAddress,
  bank = noLoopBank,
}

local loopFirstSongId = "Music_Gen2LoopFirstTest"
local loopFirstAddress, loopFirstBank = 0x7FF6, 0x7B
Data.audio.songs[loopFirstSongId] = {
  address = loopFirstAddress,
  bank = loopFirstBank,
}

local CoreData = require("src.core.Data")
local previousAudio = CoreData.audio
CoreData.audio = Data.audio

local ChipSynth = require("src.core.ChipSynth")
local originalNewEngine = ChipSynth.newEngine
local ChipAsm = require("src.audio.ChipAsm")
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
local function mockCrossLoopEngine()
  local engine = { tempo = 0x100, generation = 2, channels = {} }
  local channel = {
    engine = engine,
    hardware = 1,
    noteLength = 12,
    volume = 8,
    fade = 0,
    timeTicks = 0,
    ended = false,
    address = 0x800,
    eventIndex = 0,
  }
  local loopBytes = {
    [0x802] = 0xFD, [0x803] = 0, [0x804] = 0x00, [0x805] = 0x09,
    [0x902] = 0xFD, [0x903] = 0, [0x904] = 0x00, [0x905] = 0x09,
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
    if self.eventIndex == 1 or self.eventIndex == 3 then
      self.address = self.eventIndex == 1 and 0x800 or 0x900
      self.timeTicks = self.timeTicks + 12 * 0x100
      return {
        register = self.eventIndex == 1 and 1000 or 1200,
        volume = 8, fade = 0, duty = 1,
      }
    end
    self.ended = true
    self.address = self.eventIndex == 2 and 0x806 or 0x906
    return nil
  end
  engine.channels[1] = channel
  return engine
end
local function mockNoLoopEngine()
  local engine = { tempo = 0x100, generation = 2, channels = {} }
  local channel = {
    engine = engine,
    hardware = 1,
    noteLength = 12,
    volume = 8,
    fade = 0,
    timeTicks = 0,
    ended = false,
    address = 0x600,
    eventIndex = 0,
  }
  function channel:byte()
    self.address = self.address + 1
    return 0
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
    if self.eventIndex == 1 then
      self.address = 0x600
      self.timeTicks = self.timeTicks + 12 * 0x100
      return { register = 1000, volume = 8, fade = 0, duty = 1 }
    end
    self.ended = true
    self.address = 0x606
    -- Shared Gen2 tempo register: a tempo command on one channel must not
    -- leak into the next channel's translation.
    engine.tempo = 0x80
    return nil
  end
  engine.channels[1] = channel
  local channel2 = {
    engine = engine,
    hardware = 2,
    noteLength = 12,
    volume = 8,
    fade = 0,
    timeTicks = 0,
    ended = false,
    address = 0x610,
    eventIndex = 0,
  }
  function channel2:byte()
    self.address = self.address + 1
    return 0
  end
  function channel2:word()
    local low, high = self:byte(), self:byte()
    return low + high * 0x100
  end
  function channel2:frequency(note, octave)
    return 1200 + note * 2 + octave
  end
  function channel2:nextEvent()
    self.eventIndex = self.eventIndex + 1
    if self.eventIndex == 1 then
      self.address = 0x610
      self.timeTicks = self.timeTicks + 6 * 0x100
      return { register = 1200, volume = 8, fade = 0, duty = 1 }
    end
    self.ended = true
    self.address = 0x616
    return nil
  end
  engine.channels[2] = channel2
  return engine
end
local function mockLoopFirstEngine()
  local engine = { tempo = 0x100, generation = 2, channels = {} }
  local channel = {
    engine = engine,
    hardware = 1,
    noteLength = 12,
    volume = 8,
    fade = 0,
    timeTicks = 0,
    ended = false,
    address = 0x700,
    eventIndex = 0,
  }
  local loopBytes = {
    [0x702] = 0xFD, [0x703] = 0, [0x704] = 0x00, [0x705] = 0x09,
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
    return 1300 + note * 2 + octave
  end
  function channel:nextEvent()
    self.eventIndex = self.eventIndex + 1
    if self.eventIndex == 1 then
      self.ended = true
      self.address = 0x706
      -- Tempo precedes the loop, so a loop-first channel must still own it.
      engine.tempo = 0x80
      return nil
    end
    if self.eventIndex == 2 then
      self.address = 0x900
      self.timeTicks = self.timeTicks + 12 * 0x80
      return { register = 1300, volume = 8, fade = 0, duty = 1 }
    end
    self.ended = true
    self.address = 0x902
    return nil
  end
  engine.channels[1] = channel
  local channel2 = {
    engine = engine,
    hardware = 2,
    noteLength = 12,
    volume = 8,
    fade = 0,
    timeTicks = 0,
    ended = false,
    address = 0x710,
    eventIndex = 0,
  }
  function channel2:byte()
    self.address = self.address + 1
    return 0
  end
  function channel2:word()
    local low, high = self:byte(), self:byte()
    return low + high * 0x100
  end
  function channel2:frequency(note, octave)
    return 1400 + note * 2 + octave
  end
  function channel2:nextEvent()
    self.eventIndex = self.eventIndex + 1
    if self.eventIndex == 1 then
      self.address = 0x710
      self.timeTicks = self.timeTicks + 12 * (engine.tempo or 0x100)
      return { register = 1400, volume = 8, fade = 0, duty = 1 }
    end
    self.ended = true
    self.address = 0x716
    return nil
  end
  engine.channels[2] = channel2
  return engine
end
ChipSynth.newEngine = function(data, header, options)
  if type(header) == "table" and header.address == loopFirstAddress
      and header.bank == loopFirstBank then
    return mockLoopFirstEngine()
  end
  if type(header) == "table" and header.address == crossAddress
      and header.bank == crossBank then
    return mockCrossLoopEngine()
  end
  if type(header) == "table" and header.address == noLoopAddress
      and header.bank == noLoopBank then
    return mockNoLoopEngine()
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
local function aliasPath(id)
  local aliasBytes = cache and cache:read("songs/aliases.lua")
  if type(aliasBytes) ~= "string" then return nil end
  local chunk = load(aliasBytes)
  if not chunk then return nil end
  local ok, aliases = pcall(chunk)
  if not ok or type(aliases) ~= "table" then return nil end
  return aliases[id]
end
local gen2CachePath = aliasPath(gen2SongId)
local gen2Bytes = cache and cache:read(gen2CachePath)
local gen2Cached
if type(gen2Bytes) == "string" then
  local chunk = load(gen2Bytes)
  if chunk then gen2Cached = chunk() end
end
local gen1CachePath = aliasPath(gen1SongId)
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
local crossCachePath = aliasPath(crossSongId)
local crossBytes = cache and cache:read(crossCachePath)
local crossCached
if type(crossBytes) == "string" then
  local chunk = load(crossBytes)
  if chunk then crossCached = chunk() end
end
T.check(crossCached and crossCached.chip and crossCached.chip.blob,
  "cross-song loop song is cached")
local crossRegisters = {}
if crossCached then
  local crossEngine = originalNewEngine(Data, crossCached, { allowLoops = true })
  local crossChannel = crossEngine.channels[1]
  for index = 1, 3 do
    local event = crossChannel:nextEvent()
    crossRegisters[index] = event and event.register
  end
end
T.check(crossRegisters[2] ~= nil and crossRegisters[2] ~= crossRegisters[1],
  "cross-song loop target continues decoding the foreign stream")
T.eq(crossRegisters[3], crossRegisters[2],
  "cross-song loop points at the continuation instead of the intro")
local noLoopCachePath = aliasPath(noLoopSongId)
local noLoopBytes = cache and cache:read(noLoopCachePath)
local noLoopCached
if type(noLoopBytes) == "string" then
  local chunk = load(noLoopBytes)
  if chunk then noLoopCached = chunk() end
end
local noLoopRegisters = {}
if noLoopCached then
  local noLoopEngine = originalNewEngine(Data, noLoopCached, { allowLoops = true })
  local noLoopChannel = noLoopEngine.channels[1]
  for index = 1, 3 do
    local event = noLoopChannel:nextEvent()
    noLoopRegisters[index] = event and event.register
  end
end
T.eq(noLoopRegisters[2], noLoopRegisters[1],
  "songs without a source loop still loop to their start")
local noLoopDurations = {}
if noLoopCached then
  local noLoopEngine = originalNewEngine(Data, noLoopCached,
    { allowLoops = false })
  for index, channel in ipairs(noLoopEngine.channels) do
    while channel:nextEvent() do end
    noLoopDurations[index] = channel.timeTicks
  end
end
T.eq(noLoopDurations[2], noLoopDurations[1],
  "no-source-loop channels restart together at the song length")
local noLoopFirstDurations = {}
if noLoopCached then
  local noLoopEngine = originalNewEngine(Data, noLoopCached,
    { allowLoops = true })
  for index, channel in ipairs(noLoopEngine.channels) do
    local event = channel:nextEvent()
    noLoopFirstDurations[index] = event and channel.timeTicks
  end
end
T.eq(noLoopFirstDurations[2], 12 * 0x100,
  "channel translation starts from the song tempo, not the previous channel")
local loopFirstCachePath = aliasPath(loopFirstSongId)
local loopFirstBytes = cache and cache:read(loopFirstCachePath)
local loopFirstCached
if type(loopFirstBytes) == "string" then
  local chunk = load(loopFirstBytes)
  if chunk then loopFirstCached = chunk() end
end
local loopFirstTiming = {}
if loopFirstCached then
  local loopFirstEngine = originalNewEngine(Data, loopFirstCached,
    { allowLoops = false })
  for index, channel in ipairs(loopFirstEngine.channels) do
    local event = channel:nextEvent()
    loopFirstTiming[index] = event and channel.timeTicks
  end
end
T.eq(loopFirstTiming[1], 12 * 0x80,
  "loop-first channel keeps the tempo declared before its source loop")
T.eq(loopFirstTiming[2], 12 * 0x80,
  "other channels decode against a tempo owned by a loop-first channel")
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

-- A side built from a non-lead channel has no tempo events. Its separate
-- engine must still follow the lead timeline through loop restarts.
local tempoSource = {
  tempo = 0x100,
  channels = {
    { hw = 1, program = {
      { pitch = 0, len = 2 },
      { tempo = 0x80 },
      { pitch = 1, len = 2 },
      { loop = { count = 0, to = 1 } },
    } },
    { hw = 2, program = {
      { pitch = 0, len = 2 },
      { pitch = 1, len = 2 },
      { loop = { count = 0, to = 1 } },
    } },
  },
}
local tempoSides = improvement.extra(tempoSource,
  { enabled = true, keyAware = false })
local function tempoTrace(song, channelIndex)
  local engine = originalNewEngine(Data, song, { allowLoops = true })
  local channel = engine.channels[channelIndex]
  local tempos, ticks = {}, {}
  for i = 1, 6 do
    for _, engineChannel in ipairs(engine.channels) do
      engineChannel:nextEvent()
    end
    tempos[i] = engine.tempo
    ticks[i] = channel.timeTicks
  end
  return table.concat(tempos, ","), table.concat(ticks, ",")
end
local baseTempos, baseTicks = tempoTrace(ChipAsm.song(tempoSource), 2)
local bassTempos, bassTicks = tempoTrace(ChipAsm.song(tempoSides.bassDown), 1)
T.eq(bassTempos, baseTempos,
  "bassDown harmony follows lead tempo changes across loops")
T.eq(bassTicks, baseTicks,
  "bassDown note timing matches base after lead tempo change")

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

  local keptIndex = true
  local onlySongCache = true
  for _, path in ipairs(deleted) do
    local rel = path:match("^mod_cache/[^/]+/(.*)$") or path
    if rel == "songs/index.txt" then keptIndex = false end
    if rel:sub(1, 6) ~= "songs/" then onlySongCache = false end
  end
  T.check(keptIndex, "regeneration keeps the shared cache index")
  T.check(#deleted > 0, "regeneration deletes cached songs through mod.cache")
  T.check(onlySongCache, "regeneration only deletes song cache files")
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

-- Mix variants belong in LEFT/RIGHT selection, not as separate rows.
Data.audio.songs.Music_MixGen1CacheTest_firered = {}
local mixListed = false
for _, id in ipairs(exports.musicIds({ data = Data })) do
  if id == "Music_MixGen1CacheTest_firered" then mixListed = true end
end
T.check(not mixListed, "mix variants are not separate music test rows")
Data.audio.songs.Music_MixGen1CacheTest_firered = nil
Data.audio.songs.Music_G4MixGen1CacheTest_firered = {}
local g4MixListed = false
for _, id in ipairs(exports.musicIds({ data = Data })) do
  if id == "Music_G4MixGen1CacheTest_firered" then g4MixListed = true end
end
T.check(not g4MixListed, "G4 Mix variants are not separate music test rows")
Data.audio.songs.Music_G4MixGen1CacheTest_firered = nil

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
T.eq(optionRows[5] and optionRows[5].musicImprovementId, "music_improvement_nds_import",
  "NDS import is reachable from the visible options group")
T.eq(optionRows[5] and optionRows[5].id, "sfxVol",
  "NDS import row belongs to the AUDIO options group")
T.eq(optionRows[6] and optionRows[6].musicImprovementId, "music_improvement_sources",
  "source toggles are grouped in the visible options group")
T.eq(optionRows[6] and optionRows[6].id, "musicVol",
  "source row belongs to the AUDIO options group")
local mixSongsRow
for _, row in ipairs(optionRows) do
  if row.musicImprovementId == "music_improvement_mix_songs" then
    mixSongsRow = row
    break
  end
end
T.eq(mixSongsRow, nil, "per-song G3 Mix configuration row is gone")
T.eq(run.loader.content.screens:get("MusicImprovementMixSongs"), nil,
  "per-song G3 Mix configuration screen is gone")
local okGen3Sources = pcall(function()
  optionRows[6].activate({ save = { version = "firered" } })
  pcall(require("src.ui.game3.stack").pop, "music_improvement_menu")
end)
T.eq(okGen3Sources, true, "source row opens through the GBA modal stack")
local stockToggleRow
for _, row in ipairs(optionRows) do
  if row.musicImprovementId == "music_improvement_alt_g1_stock" then
    stockToggleRow = row
    break
  end
end
T.eq(stockToggleRow, nil,
  "individual source toggles live in the source screen, not the options list")
local sourceScreen = run.loader.content.screens:get("MusicImprovementSources")
T.eq(type(sourceScreen and sourceScreen.new), "function",
  "source screen is registered")
local sourceMenu = sourceScreen.new(run.data)
T.eq(sourceMenu.rows, 5, "source menu leaves room for the footer")
local sourceLabels = {
  "SHUFFLE", "G1", "G1E", "G2", "G2E", "G3 MIX", "G4 MIX", "G4 GB", "G3",
}
for index, label in ipairs(sourceLabels) do
  T.eq(sourceMenu.items[index] and sourceMenu.items[index].label, label,
    "source toggle " .. index .. " is " .. label)
end
T.eq(sourceMenu.items[9].right, "N/A",
  "native G3 is unavailable outside GBA hosts")
local gbaSourceMenu = sourceScreen.new({ save = { version = "firered" } })
T.eq(gbaSourceMenu.items[9].right, "YES",
  "native G3 is enabled on GBA hosts")

if cache and exports and type(cache.delete) == "function" then
  local failurePath = "songs/gold_test_delete_failure.lua"
  cache:write(failurePath, "generated cache")
  cache:write("songs/index.txt", failurePath .. "\n")
  failRemoval = true
  local game = {
    mods = { modOptions = { g1r_music_improvement = { enabled = false } } },
  }
  exports.regenerateCache(game)
  failRemoval = false
  T.eq(game.mods.modOptions.g1r_music_improvement.enabled, false,
    "regeneration stops before changing settings when cache deletion fails")
end

-- ------- duplicate battle cues keep the variant that is already playing

-- Stand in for Shuffle re-rolling: make chooseVariant alternate ids for one
-- native song.  The select hook under test is the production implementation.
local function replaceOnce(source, old, new)
  local at = source:find(old, 1, true)
  if not at then error("test patch target missing: " .. old) end
  return source:sub(1, at - 1) .. new .. source:sub(at + #old)
end

local mainPath = "mods/g1r_music_improvement/main.lua"
local patchedMain = replaceOnce(assert(runFs.read(mainPath)),
  "  local variantMap = {}",
  "  local variantMap = {}\n  local cuePickCount = 0")
patchedMain = replaceOnce(patchedMain,
  "    local improved = chooseVariant(song)",
  [[    local improved
    if song == "Music_Gen2CacheTest" then
      cuePickCount = cuePickCount + 1
      improved = cuePickCount % 2 == 1
        and "Music_ImprovedGen2CacheTest" or "Music_StockGen2CacheTest"
    else
      improved = chooseVariant(song)
    end]])
runFs.write(mainPath, patchedMain)
run.release()

local cueData = T.fixtures.fresh()
cueData.audio = { songs = {}, gen2 = true }
for id, def in pairs(Data.audio.songs) do
  if not tostring(id):match("^Music_Improved")
      and not tostring(id):match("^Music_Stock") then
    cueData.audio.songs[id] = def
  end
end
CoreData.audio = cueData.audio
local cueRun = T.sdk.loadMod("mods/g1r_music_improvement", {
  data = cueData, generation = 2, fs = runFs,
})
T.check(#cueRun.errors == 0, "duplicate-cue fixture loads clean")

local cueA = select(gen2SongId, { reason = "battle" })
T.eq(cueA, "Music_ImprovedGen2CacheTest", "shuffle stand-in picks the first variant")
Runtime.emit("music.started", { song = cueA, reason = "battle" })
T.eq(select(gen2SongId, { reason = "battle" }), cueA,
  "second battle cue reuses the variant already playing")
Runtime.emit("music.stopped")
T.eq(select(gen2SongId, { reason = "battle" }), "Music_StockGen2CacheTest",
  "stopping clears the cached variant so shuffle can pick again")
Runtime.emit("music.started", { song = "Music_Other", reason = "battle" })
T.eq(select(gen2SongId, { reason = "battle" }), "Music_ImprovedGen2CacheTest",
  "a different started song clears the cached variant")

ChipSynth.newEngine = originalNewEngine
CoreData.audio = previousAudio
Version.modApi = previousModApi
GameVersion.set(previousVersion)
cueRun.release()

-- Fresh Gen3-loaded instance: the sandbox denies game3 stack modules on Gen2
-- hosts, so modal toggle state must be checked with generation = 3.
local gbaRun = T.sdk.loadMod("mods/g1r_music_improvement", {
  data = T.sdk.gen3Data(), generation = 3,
})
local gbaRows = Runtime.call("ui.options.rows",
  function(_, rows) return rows end, { data = gbaRun.data },
  { { id = "sound", label = "SOUND" } })
local gbaSourceRow
for _, row in ipairs(gbaRows) do
  if row.musicImprovementId == "music_improvement_sources" then
    gbaSourceRow = row
  end
end
T.eq(gbaSourceRow ~= nil, true, "GBA options exposes MUSIC SOURCES")
local GbaStack = require("src.ui.game3.stack")
GbaStack.clear()
gbaSourceRow.activate({ save = { version = "firered" } })
local gbaMenu = GbaStack.top() and GbaStack.top().mod
T.eq(type(gbaMenu and gbaMenu.onChoose), "function", "GBA sources modal opens")
if gbaMenu and gbaMenu.items[1] then
  local shuffleItem = gbaMenu.items[1]
  gbaMenu.onChoose(shuffleItem)
  T.eq(shuffleItem.right, "NO", "GBA source toggle status updates live")
  gbaMenu.onChoose(shuffleItem)
  T.eq(shuffleItem.right, "YES", "GBA source toggle can be restored")
end
pcall(GbaStack.pop, "music_improvement_menu")
gbaRun.release()

-- FireRed's first-run prompt waits until the boot/recap sequence is over.
local mainSource = run.loader.fs.read("mods/g1r_music_improvement/main.lua")
T.eq(type(mainSource) == "string"
  and mainSource:find('hostIsGen3(self) and self.phase == "field"', 1, true) ~= nil,
  true, "Gen3 enhance prompt is gated on the field phase")
T.eq(type(mainSource) == "string"
  and mainSource:find("elseif generation == hostGeneration then", 1, true) ~= nil
  and mainSource:find("g4Mix.has(entry.id, candidateLabel)", 1, true) ~= nil,
  true, "G4 candidates enumerate host generation (Gold gets G2 variants)")
T.eq(type(mainSource) == "string"
  and mainSource:find(
    "if g4CandidatesFor and group and versions.mixAllowed(group, hostGeneration) then",
    1, true) ~= nil
  and mainSource:find("group.gen3 or group.gen2 or group.gen1", 1, true) ~= nil,
  true, "gen2-only G4 groups use native GSC candidate keys")
T.eq(type(mainSource) == "string"
  and mainSource:find("local variantIds = {}", 1, true) ~= nil
  and mainSource:find("for _, id in ipairs(ids) do variantIds[#variantIds + 1] = id end",
    1, true) ~= nil
  and mainSource:find("isSongData(data) and data.audio.songs[id]", 1, true) ~= nil,
  true, "Gold boot buildQueue separates raw G4 ids from native data.audio ids")
T.eq(type(mainSource) == "string"
  and mainSource:find("for _, audio in ipairs({ extraAudio, gbaExtraAudio }) do",
    1, true) ~= nil
  and mainSource:find("pcall(audio.setSampleReader, readNdsSample)", 1, true) ~= nil,
  true, "GB and GBA extra engines both receive the NDS sample reader")
T.eq(type(mainSource) == "string"
  and mainSource:find("if spec.pcm then song.pcm = spec.pcm end", 1, true) ~= nil,
  true, "G4 extra songs retain PCM refs for extra_audio")

-- Gen3 right labels must use the GBA viewport, not the desktop window width.
local fontKey = "src.ui.game3.frlg_font"
local previousFont = package.loaded[fontKey]
local drawCalls = {}
package.loaded[fontKey] = {
  COLOR = { WHITE = {} },
  draw = function(text, x, y)
    drawCalls[#drawCalls + 1] = { text = tostring(text), x = x, y = y }
  end,
  measure = function(text) return #tostring(text) * 6 end,
  linePitch = function() return 15 end,
  GLYPH_HEIGHT = 14,
}
package.loaded["mods.g1r_music_improvement.gen3_ui"] = nil
local Gen3Ui = require("mods.g1r_music_improvement.gen3_ui")
GbaStack.clear()
local drawMenu = Gen3Ui.openList({}, {
  title = "MUSIC SOURCES",
  items = { { label = "SHUFFLE", right = "YES" } },
  hint = { "A TOGGLE  B BACK" },
})
package.loaded[fontKey] = previousFont
T.eq(drawMenu ~= nil, true, "stubbed Gen3 list opens")
if drawMenu then
  drawMenu.draw()
  local rightX, hintY
  for _, call in ipairs(drawCalls) do
    if call.text == "YES" then rightX = call.x end
    if call.text == "A TOGGLE  B BACK" then hintY = call.y end
  end
  T.eq(rightX, 214, "Gen3 right labels align inside the GBA viewport")
  T.eq(hintY, 142, "Gen3 hints stay above the GBA bottom edge")
end
pcall(GbaStack.pop, "music_improvement_menu")

-- Variant cycling accepts shoulder keys alongside the native arrows.
local jukeScreen = run.loader.content.screens:get("MusicImprovementJukebox")
T.eq(type(jukeScreen and jukeScreen.new), "function",
  "jukebox screen is registered")
local juke = jukeScreen and jukeScreen.new(run.data)
local cycleItem
if juke then
  for _, item in ipairs(juke.items) do
    if item.entry and item.entry.variants and #item.entry.variants > 1 then
      cycleItem = item
      break
    end
  end
end
T.eq(cycleItem ~= nil, true, "music test has a multi-variant entry")
if cycleItem then
  juke.items = { cycleItem }
  juke.index = 1
  local pressed = {}
  juke.game.input = {
    wasPressed = function(_, key) return pressed[key] == true end,
  }
  for _, key in ipairs({ "l", "r", "left", "right" }) do
    pressed[key] = true
    local before = cycleItem.right
    juke:update(0)
    T.eq(cycleItem.right ~= before, true,
      key .. " cycles the selected song variant")
    pressed[key] = nil
  end
end

-- Gen3 modal cycles on shoulders too.
local cycleDirections = {}
local cycleMenu = Gen3Ui.openList({}, {
  title = "MUSIC TEST",
  items = { { label = "ONE" } },
  onCycle = function(_, dir) cycleDirections[#cycleDirections + 1] = dir end,
})
T.eq(cycleMenu ~= nil, true, "Gen3 cycle modal opens")
if cycleMenu then
  cycleMenu.handleInput({ wasPressed = function(_, key) return key == "l" end })
  cycleMenu.handleInput({ wasPressed = function(_, key) return key == "r" end })
  T.eq(cycleDirections[1], -1, "Gen3 L shoulder cycles back")
  T.eq(cycleDirections[2], 1, "Gen3 R shoulder cycles forward")
  pcall(GbaStack.pop, "music_improvement_menu")
end

-- With Omni present, menus widen their scroll windows and shorten hints.
local omniKey = "mods.omni_ui.api.PublicApi"
local savedOmni = package.loaded[omniKey]
package.loaded[omniKey] = {
  Layout = {
    drawCard = function() end, drawSlot = function() end,
    drawText = function() end, drawHintBar = function() end,
    drawProgressBar = function() end, textWidth = function() return 42 end,
  },
  Theme = { get = function() return {} end },
  registerScreen = function() return true end,
}
local omniRun = T.sdk.loadMod("mods/g1r_music_improvement", {
  data = T.fixtures.fresh(), generation = 2,
})
local omniJuke = omniRun.loader.content.screens:get("MusicImprovementJukebox")
local omniJukeMenu = omniJuke and omniJuke.new(omniRun.data)
T.eq(omniJukeMenu and omniJukeMenu.rows, 16, "Omni jukebox widens rows")
T.eq(omniJukeMenu and omniJukeMenu.footer:match("L/R VARIANT") ~= nil, true,
  "Omni jukebox uses shoulder hint")
local omniSources = omniRun.loader.content.screens:get("MusicImprovementSources")
T.eq(omniSources and omniSources.new(omniRun.data).rows, 16,
  "Omni sources widen rows")
omniRun.release()
package.loaded[omniKey] = savedOmni

T.finish("g1r_music_improvement")
