-- Standalone test for SWAV-aware G4 conversion.  Run from mod directory:
--   luajit tests/g4_pcm_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path

local g4Mix = require("g4_mix")
local versions = require("versions")
local realG3 = require("g3_mix")

local function u24le(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256)
end
local events = string.char(
  0xE1, 120, 0x00,
  0x81, 0x00,
  0x3C, 100, 48,
  0xFF
)
local blob = string.char(0xFE, 0x01, 0x00, 0x93, 0x00) .. u24le(8) .. events

local sampleBytes = {}
for _ = 1, 64 do
  sampleBytes[#sampleBytes + 1] = string.char(0x40, 0x4E)
end
local sampleData = table.concat(sampleBytes)

local captured
local g3Mix = { clockAt = realG3.clockAt }
function g3Mix.has(version, label)
  return version == "firered" and label == "MUS_PALLET"
end
function g3Mix.buildSpecs(song, voicegroups, info)
  captured = { song = song, voicegroups = voicegroups, info = info }
  return {
    { tempo = 160, channels = { { hw = 1, program = {} } } },
    { tempo = 160, channels = { { hw = 1, program = {} } } },
  }
end

local nds = {}
function nds.status() return { available = true, songCount = 1 } end
function nds.listSongs()
  return { { name = "SEQ_GS_TEST", index = 1, bank = 0, player = 0 } }
end
function nds.readSequence()
  return { data = blob, base = 0, size = #blob }
end
function nds.readBank()
  return { count = 1, instruments = { [0] = { type = 1, defs = {
    [0] = { type = 1, waveID_dutyCycle = 0, waveArchiveID = 0,
      pitch = 60, attack = 100, decay = 100, sustain = 100, release = 80 },
  } } } }
end
function nds.readSample(bank, def)
  assert(bank == 0 and def.waveID_dutyCycle == 0)
  return { data = sampleData, sampleRate = 32768,
    loop = true, loopStart = 0, loopEnd = 63 }
end

local songMap = {
  BY_NAME = { SEQ_GS_TEST = "Music_PalletTown" },
  BY_KEY = { Music_PalletTown = { "SEQ_GS_TEST" } },
}
function songMap.keyFor(name) return songMap.BY_NAME[name] end
function songMap.namesFor(key) return songMap.BY_KEY[key] or {} end

assert(g4Mix.install({ g3Mix = g3Mix, nds = nds, songMap = songMap,
  versions = versions }) == true)

local converted, err = g4Mix.convert("firered", "MUS_PALLET")
assert(converted, err)
assert(captured and captured.voicegroups[1][1].wave)
local wave = captured.voicegroups[1][1].wave
assert(#wave == 32)
for i = 1, 32 do
  assert(wave[i] == 15, "SWAV samples did not become the GB wave: " .. tostring(wave[i]))
end
assert(converted.def.pcm and #converted.def.pcm.events == 1,
  "Gen3 G4 spec missing direct PCM events")
local event = converted.def.pcm.events[1]
assert(event.bank == 0 and event.archive == 0 and event.wave == 0
  and event.pitch == 60)

local gb = assert(g4Mix.convert("gold", "Music_PalletTown"))
assert(gb.def.pcm == nil, "GB hosts should bake samples into wave RAM")

print("g4_pcm_test: ok")
