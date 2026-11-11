-- Standalone: luajit tests/gen2_live_data_test.lua
-- Gen2 keeps songs on Game2.data; src.core.Data.audio stays nil.  The mod
-- must take the dataset from game.ready, not the Gen1 singleton.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")

local songId = "Music_Gen2LiveData"
local address, bank = 0x7FFE, 0x7E
local data = T.fixtures.fresh()
data.audio = { gen2 = true, songs = {
  [songId] = { address = address, bank = bank },
} }

-- A Gold boot never fills the Gen1 singleton's audio table.
local CoreData = require("src.core.Data")
local previousAudio = CoreData.audio
CoreData.audio = nil

local ChipSynth = require("src.core.ChipSynth")
local originalNewEngine = ChipSynth.newEngine
ChipSynth.newEngine = function(_, header, options)
  if type(header) ~= "table" or header.address ~= address or header.bank ~= bank then
    return originalNewEngine(_, header, options)
  end
  local engine = { tempo = 0x100, generation = 1, channels = {} }
  local channel = {
    engine = engine, hardware = 1, speed = 12, volume = 8, fade = 0,
    timeTicks = 0, ended = false, address = 0x100, eventIndex = 0,
  }
  local loopBytes = { [0x200] = 0xFE, [0x201] = 0, [0x202] = 0x05, [0x203] = 0x01 }
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
  return engine
end

local GameVersion = require("src.core.GameVersion")
local previousVersion = GameVersion.get()
GameVersion.set("gold")
local Version = require("src.core.Version")
local previousModApi = Version.modApi
Version.modApi = math.max(Version.modApi or 0, 3)

local run = T.sdk.loadMod("mods/g1r_music_improvement", {
  data = data, generation = 2,
})
local musicMod = run.mods.g1r_music_improvement
local exports = run.loader.exports and run.loader.exports.g1r_music_improvement
T.eq(#run.errors, 0, "loads clean")
T.check(type(exports) == "table" and type(exports.prepareAll) == "function",
  "mod exports prepareAll")

-- Boot finishes only after game.ready.  The song lives on game.data, and the
-- Gen1 singleton still has no audio table.
Runtime.emit("game.ready", { game = { data = data } })
exports.prepareAll()

local improved = "Music_ImprovedGen2LiveData"
T.check(type(data.audio.songs[improved]) == "table",
  "game.ready dataset is translated and registered")
local _, cache = require("src.mods.ImportAccess").new(musicMod.manifest, run.loader.fs)
local path = "songs/gold_" .. tostring(musicMod.manifest.version)
  .. "_true_" .. songId .. ".lua"
local bytes = cache and cache:read(path)
T.check(type(bytes) == "string", "Gen2 live dataset writes its song cache")
local chunk = type(bytes) == "string" and load(bytes)
local cached = chunk and chunk()
T.check(type(cached) == "table" and type(cached.chip) == "table",
  "cached Gen2 song carries a chip program")

ChipSynth.newEngine = originalNewEngine
CoreData.audio = previousAudio
Version.modApi = previousModApi
GameVersion.set(previousVersion)
run.release()
T.finish("gen2_live_data")
