-- Plain Lua asserts for GBA DirectSound sample refs in G3 Mix.
-- Run: cd <mod> && luajit tests/g3_pcm_test.lua
package.path = "./?.lua;../gen1recomp/?.lua;" .. package.path
local mix = dofile("g3_mix.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

-- Voice 1, fine tuning +2, note key 60 vel 100, end.
local track = string.char(0xBD, 0x01, 0xEE, 0x02, 0xD3, 60, 100, 0xB1)
local decoded = mix.decodeTrack(track)
local note
for _, event in ipairs(decoded.events) do
  if event.kind == "note" then note = event end
end
assert(note, "note decoded")
eq(note.fine, 2, "0xEE signed fine tuning")

local samples = {
  [7] = { id = 7, key = 60, freq = 13379 * 1024, offset = 0, size = 100,
    loopStart = 0, status = 0 },
}
local voicegroups = { [1] = { [1] = { type = 0, key = 60, sampleId = 7 } } }
local song = { tracks = 1, trackData = { track }, voicegroup = 1 }
local specs = mix.buildSpecs(song, voicegroups,
  { voicegroupId = 1, samples = samples, version = "firered" })

assert(specs and #specs == 2, "PCM gets a silent extra carrier")
eq(specs[1].pcm, nil, "base spec stays chip-only")
assert(specs[2].pcm, "carrier has PCM")
local pcm = specs[2].pcm
eq(#pcm.events, 1, "one DirectSound note becomes PCM")
eq(pcm.tempoTimeline[1].gb, 256, "PCM uses integer chip tempo grid")
local event = pcm.events[1]
eq(event.bank.gba, true, "GBA sample marker")
eq(event.bank.version, "firered", "GBA sample version")
eq(event.bank.sampleId, 7, "GBA sample id")
eq(event.bank.offset, 0, "offset from samples meta")
assert(event.rateHz > 13379 and event.rateHz < 15000, "DS fine-tuned rate")
eq(event.key, 60, "PCM note key")
eq(event.gainScale, 1.4, "lead note boosts PCM")

-- Without samples.lua, the same DirectSound tone still converts to chip.
local chipOnly = mix.buildSpecs(song, voicegroups, { voicegroupId = 1 })
assert(chipOnly and chipOnly[1], "chip fallback without samples")
eq(#chipOnly, 1, "no carrier without samples")
eq(chipOnly[1].pcm, nil, "no PCM without samples")

-- Drum-kit sub-tone: type 128 points at a DirectSound sub-tone. Its sampleId
-- and ADSR must survive resolveTone instead of falling back to GB noise.
local drumTrack = string.char(0xBD, 0x01, 0xD3, 36, 100, 0xB1)
local drumSamples = {
  [9] = { id = 9, key = 36, freq = 11000 * 1024, offset = 0, size = 120,
    loopStart = 0, status = 0 },
}
local drumGroups = {
  [1] = { [1] = { type = 128, key = 36, subVgId = 2 } },
  [2] = { [36] = { type = 0, key = 36, sampleId = 9,
    attack = 255, decay = 4, sustain = 7, release = 3, pan = 0x40 } },
}
local drumSong = { tracks = 1, trackData = { drumTrack }, voicegroup = 1 }
local drumSpecs = mix.buildSpecs(drumSong, drumGroups,
  { voicegroupId = 1, samples = drumSamples, version = "firered" })
assert(drumSpecs and drumSpecs[2] and drumSpecs[2].pcm, "drum kit keeps PCM")
local drum = drumSpecs[2].pcm.events[1]
eq(drum.bank.sampleId, 9, "drum kit uses real GBA sample")
eq(drum.attack, 255, "drum kit attack copied")
eq(drum.decay, 4, "drum kit decay copied")
eq(drum.sustain, 7, "drum kit sustain copied")
eq(drum.release, 3, "drum kit release copied")

-- Low bass on a 6000 Hz sample: native DS pitch uses the note key directly,
-- ignoring tone.key. samples.lua sampleId is 1-based; no +1 adjustment.
local lowTrack = string.char(0xBD, 0x01, 0xD3, 24, 100, 0xB1)
local lowSamples = {
  [11] = { id = 11, freq = 6000 * 1024, offset = 0, size = 80,
    loopStart = 0, status = 0 },
}
local lowGroups = { [1] = { [1] = { type = 0, key = 72, sampleId = 11 } } }
local lowSong = { tracks = 1, trackData = { lowTrack }, voicegroup = 1 }
local lowSpecs = mix.buildSpecs(lowSong, lowGroups,
  { voicegroupId = 1, samples = lowSamples, version = "firered" })
assert(lowSpecs and lowSpecs[2] and lowSpecs[2].pcm, "low-rate sample kept")
local lowEvent = lowSpecs[2].pcm.events[1]
eq(lowEvent.bank.sampleId, 11, "1-based sample id unchanged")
eq(lowEvent.key, 24, "native pitch ignores tone.key")
assert(lowEvent.rateHz > 0 and lowEvent.rateHz < 1000,
  "low-rate sample rejected: " .. tostring(lowEvent.rateHz))

print("g3_pcm_test: ok")
