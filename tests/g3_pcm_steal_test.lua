-- Standalone: luajit tests/g3_pcm_steal_test.lua
-- Verifies dense PCM overlaps steal voices instead of dropping new notes.
package.path = "./?.lua;./?/init.lua;" .. package.path

local previousSynth = package.loaded["src.core.ChipSynth"]
package.loaded["src.core.ChipSynth"] = { SAMPLE_RATE = 44100 }

local source = assert(io.open("extra_audio.lua", "rb")):read("*a")
local needle = "  return {\n    start = start,"
local replacement = [[  return {
    _internals = {
      pcmPrepare = pcmPrepare, pcmRender = pcmRender,
    },
    start = start,]]
source, count = source:gsub(needle, replacement, 1)
assert(count == 1, "extra_audio internals injection failed")
local factory = assert(load(source, "extra_audio_test", "t"))()

local function check(value, message)
  if not value then error("FAIL: " .. message, 2) end
end

local audio = factory()
check(audio, "extra_audio factory failed")
audio.setSampleReader(function()
  return {
    data = string.rep(string.char(0xE8, 0x03), 1000),
    sampleRate = 44100, loop = true, loopStart = 0, loopEnd = 999,
  }
end)

local events = {}
for i = 1, 40 do
  events[i] = {
    tick = 0, gate = 50000, key = 60, pitch = 60, vel = 100,
    volume = 100, pan = 0x40, rateHz = 44100,
    attack = 0, decay = 0, sustain = 255, release = 0,
    bank = 1, archive = 0, wave = 1,
  }
end
local built = audio._internals.pcmPrepare({}, {
  pcm = { events = events, tempoTimeline = { { tick = 0, tempo = 300 } } },
})
check(built, "dense PCM prepare failed")
check(built.stats.events == 40, "expected 40 events, got " .. tostring(built.stats.events))
check(built.stats.ready == 40, "expected 40 resolved samples")

local left, right = {}, {}
for i = 0, 63 do left[i], right[i] = 0, 0 end
audio._internals.pcmRender(built, left, right, 0, 64, 1)
check(built.stats.spawned == 40, "all events must spawn, got " .. tostring(built.stats.spawned))
check(built.stats.stolen == 24, "expected 24 stolen voices, got " .. tostring(built.stats.stolen))
check(built.stats.active == 16, "voice cap exceeded: " .. tostring(built.stats.active))
check(built.stats.peak > 0.05, "stolen PCM voices must still render")

print("pass: g3 PCM voice stealing")
package.loaded["src.core.ChipSynth"] = previousSynth
