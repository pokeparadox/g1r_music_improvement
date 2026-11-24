-- Standalone G4 Mix converter test.  Run from the mod directory:
--   luajit tests/g4_mix_test.lua
local packagePath = package.path
package.path = "./?.lua;./tests/?.lua;" .. packagePath

local g4Mix = require("g4_mix")
local versions = require("versions")
local realG3 = require("g3_mix")
local realSongMap = require("g4_song_map")

-- Prefer the normal BGM sequence over the GB Sounds arrangement when both
-- exist; GB Sounds remains available as a raw G4 song.
for _, pair in ipairs({
  { "Music_BikeRiding", "SEQ_BICYCLE" },
  { "Music_Surfing", "SEQ_NAMINORI" },
  { "Music_Gym", "SEQ_GYM" },
  { "Music_GameCorner", "SEQ_BLD_GAME" },
  { "Music_SafariZone", "SEQ_D_SAFARI" },
}) do
  local names = realSongMap.namesFor(pair[1])
  assert(names and names[1] == pair[2], pair[1] .. " must prefer normal BGM")
end

local function u24le(value)
  return string.char(value % 256, math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256)
end

-- One track, program 0, envelope + volume overrides, a note, a rest, then a
-- two-pass loop.
local events = string.char(
  0xE1, 120, 0x00, -- tempo 120 BPM
  0x81, 0x00,      -- instrument 0
  0xD0, 64,        -- attack override 64 (should map to GB envelope 8)
  0xC1, 100,       -- volume 100 (should map to M4A 201)
  0x3C, 100, 48,   -- C4, velocity 100, 48 SSEQ ticks
  0x80, 48,        -- rest
  0xD4, 0x00,      -- infinite loop start
  0x3E, 100, 48,   -- D4 inside loop
  0xFC,            -- loop end
  0xFF             -- track end
)
local blob = string.char(0xFE, 0x01, 0x00, 0x93, 0x00) .. u24le(8) .. events

local captured
local g3Mix = {
  lastError = nil,
  clockAt = realG3.clockAt,
}
function g3Mix.has(version, label)
  return version == "firered" and label == "MUS_PALLET"
end
function g3Mix.buildSpecs(song, voicegroups, info)
  captured = { song = song, voicegroups = voicegroups, info = info }
  return {
    { tempo = 100, channels = { { hw = 1, program = {} } } },
    { tempo = 100, channels = { { hw = 1, program = {} } } },
  }
end

local nds = {}
function nds.status() return { available = true, songCount = 1 } end
function nds.listSongs()
  return {
    { name = "SEQ_GS_TEST", index = 1, bank = 0, player = 0 },
    { name = "SEQ_TOWN99_D", index = 2, bank = 0, player = 1 },
  }
end
function nds.readSequence(song)
  if song.name ~= "SEQ_GS_TEST" and song.name ~= "SEQ_TOWN99_D" then return nil end
  return { data = blob, base = 0, size = #blob }
end
function nds.readBank(bankID)
  assert(bankID == 0)
  return {
    count = 1,
    instruments = {
      [0] = { type = 1, defs = {
        [0] = { type = 1, waveID_dutyCycle = 0, waveArchiveID = 0,
          pitch = 60, attack = 120, decay = 100, sustain = 100,
          release = 80, pan = 64 },
      } },
    },
  }
end

-- song-map keys are version-independent groups, not GBA labels.
local songMap = {
  BY_NAME = { SEQ_GS_TEST = "Music_PalletTown" },
  BY_KEY = { Music_PalletTown = { "SEQ_GS_TEST" } },
}
function songMap.keyFor(name) return songMap.BY_NAME[name] end
function songMap.namesFor(key) return songMap.BY_KEY[key] or {} end

assert(g4Mix.install({ g3Mix = g3Mix, nds = nds, songMap = songMap,
  versions = versions }) == true)
assert(g4Mix.available() == true)
assert(g4Mix.has("firered", "MUS_PALLET") == true)
assert(g4Mix.has("firered", "Music_PalletTown") == true, "gen1 label resolves group")
assert(g4Mix.has("red", "Music_PalletTown") == true, "RBY generation")
assert(g4Mix.has("gold", "Music_PalletTown") == true, "GSC generation")
assert(g4Mix.has("ruby", "MUS_PALLET") == false)
assert(g4Mix.has("firered", "MUS_TITLE") == false)

local list = g4Mix.songList()
assert(#list == 2 and list[1] == "G4:SEQ_TOWN99_D"
  and list[2] == "MUS_PALLET", "unmapped songs must be exposed as raw G4 labels")
local all = g4Mix.allSongs()
assert(#all == 2 and all[1].name == "SEQ_GS_TEST"
  and all[2].label == "G4:SEQ_TOWN99_D", "allSongs must label raw songs")
assert(g4Mix.has("gold", "G4:SEQ_TOWN99_D") == true,
  "raw song must be available on GSC hosts")

local converted, err = g4Mix.convert("firered", "MUS_PALLET")
assert(converted, err)
assert(converted.def.g4Mix == true)
assert(converted.def.converter == "g4_mix_v1" or
  tostring(converted.def.converter):match("^g4"), "missing converter version")
assert(converted.def.generation == 3)
assert(converted.def.g3Mix == nil)
assert(converted.extra.g4_2 and converted.extra.g4_2.g4Mix == true)
assert(converted.extra.g4_2.g3Mix == nil)
assert(converted.extra.g4_2.generation == 3)
assert(converted.tracks == 1)

local red = g4Mix.convert("red", "Music_PalletTown")
assert(red and red.def.generation == 1)
local gold = g4Mix.convert("gold", "Music_PalletTown")
assert(gold and gold.def.generation == 2)
local raw = g4Mix.convert("gold", "G4:SEQ_TOWN99_D")
assert(raw and raw.def.generation == 2 and raw.def.g4Mix == true,
  "raw unmapped song must convert on GSC hosts")

assert(captured and captured.song.tracks == 1)
assert(captured.info.voicegroupId == 1)
assert(captured.voicegroups[1][1] ~= nil)
-- Bank attack 120/127 rounds to GB envelope 14 (not floor(120/8)=15).
assert(captured.voicegroups[1][1].attack == 14,
  "bank envelope scaling wrong: " .. tostring(captured.voicegroups[1][1].attack))
local track = captured.song.trackData[1]
assert(track:find(string.char(0xBB), 1, true), "missing tempo command")
assert(track:find(string.char(0xBB, 120), 1, true), "tempo byte must be SSEQ BPM")
assert(track:find(string.char(0xBD), 1, true), "missing voice command")
assert(track:find(string.char(0xCD, 4, 8), 1, true), "envelope scaling wrong")
assert(track:find(string.char(0xBE, 201), 1, true), "M4A volume scaling wrong")
assert(track:find(string.char(0xCF), 1, true), "missing note command")
assert(track:find(string.char(0xB2), 1, true), "missing loop-back command")
assert(track:sub(-1):byte() == 0xB1, "missing end command")

-- Premix guard: 80 synthetic tracks must collapse under 64, i.e. under the
-- 16-spec limit of extra_audio, while keeping every note/instrument.
local decoded, rawData = {}, {}
for i = 1, 80 do
  decoded[i] = {
    events = {
      { kind = "tempo", tick = 0, bpm = 120 },
      { kind = "note", tick = i, gate = 12, key = 60, vel = 100,
        voice = (i - 1) % 4, pan = ({ 0, 64, 127 })[i % 3 + 1], volume = 127 },
    },
    ticks = i + 12,
  }
  rawData[i] = "raw" .. tostring(i)
end
local voicegroups = { [1] = {
  [0] = { type = 1 }, [1] = { type = 1 }, [2] = { type = 2 },
  [3] = { type = 3 },
} }
local premixed = g4Mix.premixDecoded(decoded, voicegroups, rawData)
assert(premixed and #premixed <= 64, "premix did not cap track count")
assert(#premixed < #decoded, "premix did not group tracks")
local specCount = math.ceil(#premixed / 4)
assert(specCount <= 16 and specCount - 1 <= 15,
  "premix must fit 16 side engines, got " .. tostring(specCount))
local noteCount = 0
for _, bytes in ipairs(premixed) do
  for _, event in ipairs(realG3.decodeTrack(bytes).events) do
    if event.kind == "note" then noteCount = noteCount + 1 end
  end
end
assert(noteCount == #decoded, "premix dropped notes: " .. tostring(noteCount))

local ok = g3Mix.buildSpecs
g3Mix.buildSpecs = function() return nil end
local failed, failErr = g4Mix.convert("firered", "MUS_PALLET")
assert(failed == nil and type(failErr) == "string")
g3Mix.buildSpecs = ok

package.path = packagePath
print("g4_mix_test: ok")
