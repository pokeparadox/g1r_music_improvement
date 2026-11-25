-- Standalone: luajit tests/extra_audio_pcm_loop_test.lua
-- Verifies SWAV sample wrapping returns to loopStart and score loop wraps to
-- firstLoopEvent instead of replaying intro events.
package.path = "./?.lua;./?/init.lua;" .. package.path

local previousSynth = package.loaded["src.core.ChipSynth"]
package.loaded["src.core.ChipSynth"] = { SAMPLE_RATE = 44100 }

local source = assert(io.open("extra_audio.lua", "rb")):read("*a")
local needle = "  return {\n    start = start,"
local replacement = [[  return {
    _internals = {
      pcmPrepare = pcmPrepare, pcmRender = pcmRender,
      pcmSeek = pcmSeek, pcmTickToSample = pcmTickToSample,
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
local internals = audio._internals

local function sampleData()
  return string.rep(string.char(0xE8, 0x03), 20)
end

local loopSample = {
  data = sampleData(), sampleRate = 44100,
  loop = true, loopStart = 2, loopEnd = 5,
}
audio.setSampleReader(function(bank)
  if bank == 1 then return loopSample end
  local intro = {
    data = sampleData(), sampleRate = 44100,
    loop = true, loopStart = 2, loopEnd = 5,
  }
  return intro
end)

local function event(tick, gate, bank)
  return {
    tick = tick, gate = gate, key = 60, pitch = 60, vel = 100,
    volume = 100, pan = 0x40, bank = bank, archive = 0, wave = 1,
  }
end

do
  local built = internals.pcmPrepare({}, {
    pcm = {
      events = { event(0, 200, 1) },
      tempoTimeline = { { tick = 0, tempo = 300 } },
    },
  })
  check(built, "sample-loop PCM prepare failed")
  local left, right = {}, {}
  for i = 0, 8 do left[i], right[i] = 0, 0 end
  internals.pcmRender(built, left, right, 0, 9, 1)
  check(#built.active == 1, "sample-loop voice missing")
  local phase = built.active[1].phase
  -- loop frames 2..4 (end=5): after 9 samples phase is 3, never reset to 0.
  check(phase == 3, "sample loop must return to loopStart: " .. tostring(phase))
end

do
  local introSample = {
    data = sampleData(), sampleRate = 44100,
    loop = true, loopStart = 2, loopEnd = 5,
  }
  audio.setSampleReader(function(bank)
    if bank == 2 then return loopSample end
    return introSample
  end)
  local built = internals.pcmPrepare({}, {
    pcm = {
      events = { event(0, 1, 1), event(48, 1, 2) },
      tempoTimeline = { { tick = 0, tempo = 300 } },
      loopStartTick = 48, loopEndTick = 96, loopTick = 48,
    },
  })
  check(built, "score-loop PCM prepare failed")
  check(built.firstLoopEvent == 2,
    "firstLoopEvent wrong: " .. tostring(built.firstLoopEvent))
  check(built.loopSamples > 0, "score loop length missing")
  built.active = {}
  built.pos = built.loopEndSamples
  built.cycle = 0
  built.nextEvent = 3
  local left, right = { [0] = 0 }, { [0] = 0 }
  internals.pcmRender(built, left, right, built.loopEndSamples, 1, 1)
  check(#built.active == 1, "score-loop voice missing")
  check(built.active[1].data == loopSample.data,
    "score loop replayed intro sample")
  check(built.active[1].start == built.loopEndSamples,
    "score-loop event time wrong")
  check(built.nextEvent == 2,
    "score loop must resume at firstLoopEvent: " .. tostring(built.nextEvent))
end

do
  local ticks = 3456
  local gbExpected = math.floor(ticks * 44100 * 148 / 15360 + 0.5)
  check(internals.pcmTickToSample({
    { tick = 0, tempo = 260, gb = 148 },
  }, ticks) == gbExpected, "G4 PCM must follow chip tempo byte")
  local legacyExpected = math.floor(ticks * 44100 * 2.5 / 260 + 0.5)
  check(internals.pcmTickToSample({
    { tick = 0, tempo = 260 },
  }, ticks) == legacyExpected, "G3 PCM must keep exact score rate")
  check(gbExpected ~= legacyExpected, "tempo drift fixture too short")
end

package.loaded["src.core.ChipSynth"] = previousSynth
print("extra_audio_pcm_loop_test: ok")
