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
  0x94, 18, 0x00, 0x00,
  0xFF
)
local events2 = string.char(0x81, 0x00, 0x3C, 100, 48, 0xFF)
local firstOffset = 13
local secondOffset = firstOffset + #events
local blob = string.char(0xFE, 0x03, 0x00, 0x93, 0x00) .. u24le(firstOffset)
  .. string.char(0x93, 0x01) .. u24le(secondOffset) .. events .. events2

local voiceEvents = string.char(
  0xE1, 120, 0x00,
  0x81, 0x00, 0x3C, 100, 12,
  0x81, 0x01, 0x40, 100, 12,
  0xFF
)
local voiceOffset = 8
local voiceBlob = string.char(0xFE, 0x03, 0x00, 0x93, 0x00)
  .. u24le(voiceOffset) .. voiceEvents

local splitEvents = string.char(
  0xE1, 120, 0x00,
  0x81, 0x00,
  0x30, 100, 12,
  0x3C, 100, 12,
  0xFF
)
local splitOffset = 8
local splitBlob = string.char(0xFE, 0x03, 0x00, 0x93, 0x00)
  .. u24le(splitOffset) .. splitEvents

local sampleBytes = {}
for _ = 1, 64 do
  sampleBytes[#sampleBytes + 1] = string.char(0x40, 0x4E)
end
local sampleData = table.concat(sampleBytes)

local calls = {}
local g3Mix = { clockAt = realG3.clockAt }
function g3Mix.has(version, label)
  return version == "firered" and label == "MUS_PALLET"
end
function g3Mix.buildSpecs(song, voicegroups, info)
  calls[#calls + 1] = { song = song, voicegroups = voicegroups, info = info }
  return { { tempo = 160, channels = { { hw = 1, program = {} } } } }
end

local nds = {}
function nds.status() return { available = true, songCount = 3 } end
function nds.listSongs()
  return {
    { name = "SEQ_GS_TEST", index = 1, bank = 0, player = 0 },
    { name = "SEQ_GS_VOICES", index = 2, bank = 1, player = 0 },
    { name = "SEQ_GS_SPLIT", index = 3, bank = 2, player = 0 },
  }
end
function nds.readSequence(song)
  if song.name == "SEQ_GS_VOICES" then
    return { data = voiceBlob, base = 0, size = #voiceBlob }
  elseif song.name == "SEQ_GS_SPLIT" then
    return { data = splitBlob, base = 0, size = #splitBlob }
  end
  return { data = blob, base = 0, size = #blob }
end
function nds.readBank(bank)
  if bank == 1 then
    return { count = 2, instruments = {
      [1] = { type = 1, defs = {
        [0] = { type = 1, waveID_dutyCycle = 0, waveArchiveID = 0,
          pitch = 60, attack = 100, decay = 100, sustain = 100, release = 80 },
      } },
      [2] = { type = 2, defs = {
        [0] = { type = 2, waveID_dutyCycle = 2, waveArchiveID = 0,
          pitch = 60, attack = 100, decay = 100, sustain = 100, release = 80 },
      } },
    } }
  elseif bank == 2 then
    return { count = 1, instruments = { [1] = { type = 16, defs = {
      [48] = { type = 1, keyLow = 48, keyHigh = 48, waveID_dutyCycle = 0,
        waveArchiveID = 0, pitch = 48, attack = 100, decay = 100,
        sustain = 100, release = 80 },
      [60] = { type = 2, keyLow = 60, keyHigh = 60, waveID_dutyCycle = 2,
        waveArchiveID = 0, pitch = 60, attack = 100, decay = 100,
        sustain = 100, release = 80 },
    } } } }
  end
  return { count = 1, instruments = { [0] = { type = 1, defs = {
    [0] = { type = 1, waveID_dutyCycle = 0, waveArchiveID = 0,
      pitch = 60, attack = 100, decay = 100, sustain = 100, release = 80 },
  } } } }
end
function nds.readSample(bank, def)
  assert((bank == 0 or bank == 1 or bank == 2) and def.waveID_dutyCycle == 0)
  return { data = sampleData, sampleRate = 32768,
    loop = true, loopStart = 0, loopEnd = 63 }
end

local songMap = {
  BY_NAME = {
    SEQ_GS_TEST = "Music_PalletTown", SEQ_GS_VOICES = "Music_Voices",
    SEQ_GS_SPLIT = "Music_SplitBank",
  },
  BY_KEY = {
    Music_PalletTown = { "SEQ_GS_TEST" },
    Music_Voices = { "SEQ_GS_VOICES" },
    Music_SplitBank = { "SEQ_GS_SPLIT" },
  },
}
function songMap.keyFor(name) return songMap.BY_NAME[name] end
function songMap.namesFor(key) return songMap.BY_KEY[key] or {} end

assert(g4Mix.install({ g3Mix = g3Mix, nds = nds, songMap = songMap,
  versions = versions }) == true)

local function hasNote(data)
  return data:find(string.char(0xCF), 1, true) ~= nil
end

local converted, err = g4Mix.convert("firered", "MUS_PALLET")
assert(converted, err)
assert(#calls == 2, "gen3 tracks must build one spec each: " .. tostring(#calls))
assert(calls[1].voicegroups[1][1].wave)
local wave = calls[1].voicegroups[1][1].wave
assert(#wave == 32)
for i = 1, 32 do
  assert(wave[i] == 15, "SWAV samples did not become the GB wave: " .. tostring(wave[i]))
end
assert(converted.def.pcm and #converted.def.pcm.events == 1,
  "Gen3 G4 spec missing direct PCM events")
assert(converted.extra.g4_2 and converted.extra.g4_2.pcm
  and #converted.extra.g4_2.pcm.events == 1,
  "Gen3 side spec missing direct PCM events")
local event = converted.def.pcm.events[1]
assert(event.bank == 0 and event.archive == 0 and event.wave == 0
  and event.pitch == 60)
assert(converted.def.pcm.loopStartTick == 0
  and converted.def.pcm.loopEndTick == 48
  and converted.def.pcm.loopTick == 48,
  "PCM loop must cover only GOTO body, not song start")

calls = {}
local gb = assert(g4Mix.convert("gold", "Music_PalletTown"))
assert(#calls == 2, "gen2 tracks must build one spec each: " .. tostring(#calls))
assert(gb.def.converter == "g4_v23_hybrid",
  "converter version must bump for PCM")
assert(gb.def.pcm and #gb.def.pcm.events == 1,
  "GB base spec must keep PCM refs")
assert(gb.def.pcm.tempoTimeline[1].tempo == 240
  and gb.def.pcm.tempoTimeline[1].gb == 160,
  "GB PCM tempo must carry the chip tempo byte: "
    .. tostring(gb.def.pcm.tempoTimeline[1].gb))
assert(gb.extra.g4_2 and gb.extra.g4_2.pcm
  and #gb.extra.g4_2.pcm.events == 1,
  "GB side spec missing PCM refs")
assert(hasNote(calls[1].song.trackData[1]),
  "base GB spec must keep its chip note")
assert(not hasNote(calls[2].song.trackData[1]),
  "GB side note must be muted when PCM renders it")

local function capture(convertMode)
  calls = {}
  local converted = assert(g4Mix.convert("firered", "MUS_PALLET", convertMode))
  return converted, calls
end

do
  local pcmOnly, pcmCalls = capture("pcm")
  assert(pcmOnly.def.g4Mix == true and pcmOnly.def.g4Gb == false,
    "G4 Mix must be PCM-only")
  assert(pcmOnly.def.converter == "g4_v23_pcm", "G4 Mix converter suffix")
  assert(pcmOnly.def.pcm and #pcmOnly.def.pcm.events == 1,
    "G4 Mix must keep PCM events")
  for _, call in ipairs(pcmCalls) do
    assert(not hasNote(call.song.trackData[1]),
      "G4 Mix must mute every chip note")
  end
end

do
  local chipOnly, chipCalls = capture("chip")
  assert(chipOnly.def.g4Gb == true and chipOnly.def.g4Mix == false,
    "G4 GB stays a separate variant")
  assert(chipOnly.def.converter == "g4_v23_chip", "G4 GB converter suffix")
  assert(chipOnly.def.pcm and #chipOnly.def.pcm.events == 1,
    "G4 GB keeps PCM refs for sampled voices")
  assert(#chipCalls >= 2, "G4 GB must keep every decoded track")
  for _, call in ipairs(chipCalls) do
    assert(not hasNote(call.song.trackData[1]),
      "G4 GB mutes chip notes replaced by PCM")
  end
end

do
  calls = {}
  local split = assert(g4Mix.convert("gold", "Music_Voices", "chip"))
  assert(#calls == 2, "G4 GB splits one SSEQ track by instrument: "
    .. tostring(#calls))
  local noteStreams = 0
  for _, call in ipairs(calls) do
    if hasNote(call.song.trackData[1]) then noteStreams = noteStreams + 1 end
  end
  assert(noteStreams == 1, "only PSG voice keeps a GB note stream")
  assert(split.def.pcm and #split.def.pcm.events == 1,
    "G4 GB keeps PCM refs for sampled voices")
  assert(split.extra.g4_2 ~= nil, "fan-out reaches extra audio specs")
  assert(split.extra.g4_2.pcm == nil, "G4 GB PSG voice has no PCM")
  for _, spec in ipairs({ split.def, split.extra.g4_2 }) do
    assert(spec.g4Gb == true and spec.g4Mix == false, "fan-out stays GB-only")
  end
end

do
  calls = {}
  local splitBank = assert(g4Mix.convert("gold", "Music_SplitBank", "chip"))
  assert(#calls == 2, "SBNK type-16 split bank splits by note definition: "
    .. tostring(#calls))
  local noteStreams = 0
  for _, call in ipairs(calls) do
    if hasNote(call.song.trackData[1]) then noteStreams = noteStreams + 1 end
  end
  assert(noteStreams == 1, "split bank only PSG note keeps GB stream")
  assert(splitBank.def.pcm and #splitBank.def.pcm.events == 1,
    "split bank sampled note keeps PCM")
  assert(splitBank.extra.g4_2.pcm == nil, "split bank PSG note has no PCM")
end

print("g4_pcm_test: ok")
