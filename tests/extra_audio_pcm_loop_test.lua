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
      chipGainFor = chipGainFor,
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
  -- GBA samples share the bus with chip voices: duck PCM so the chip layer
  -- stays audible instead of being masked by full-scale DirectSound data.
  local fullSample = {
    data = string.rep(string.char(0xFF, 0x7F), 20), sampleRate = 44100,
  }
  audio.setSampleReader(function(bank)
    if bank == 3 then return fullSample end
    return loopSample
  end)
  local built = internals.pcmPrepare({}, {
    pcm = {
      events = { event(0, 200, 3) },
      tempoTimeline = { { tick = 0, tempo = 300 } },
    },
  })
  check(built, "PCM duck prepare failed")
  local left, right = {}, {}
  -- MP2K envelopes step per GBA frame (~739 samples at 44.1 kHz).
  for frame = 0, 1599 do left[frame], right[frame] = 0, 0 end
  internals.pcmRender(built, left, right, 0, 1600, 1)
  local peak = 0
  for frame = 0, 1599 do peak = math.max(peak, math.abs(left[frame] or 0)) end
  check(peak > 0.25, "PCM duck rendered silence: " .. tostring(peak))
  check(peak <= 0.61, "PCM must stay under full chip gain: " .. tostring(peak))
end

do
  -- Lead notes carry gainScale=1.4; samples must not lose that boost or the
  -- lead disappears behind the chip backing track.
  local fullSample = {
    data = string.rep(string.char(0xFF, 0x7F), 20), sampleRate = 44100,
  }
  audio.setSampleReader(function(bank)
    if bank == 4 then return fullSample end
    return loopSample
  end)
  local leadEvent = event(0, 200, 4)
  leadEvent.gainScale = 1.4
  local built = internals.pcmPrepare({}, {
    pcm = {
      events = { leadEvent },
      tempoTimeline = { { tick = 0, tempo = 300 } },
    },
  })
  check(built, "PCM lead prepare failed")
  local left, right = {}, {}
  -- MP2K envelopes step per GBA frame (~739 samples at 44.1 kHz).
  for frame = 0, 1599 do left[frame], right[frame] = 0, 0 end
  internals.pcmRender(built, left, right, 0, 1600, 1)
  local peak = 0
  for frame = 0, 1599 do peak = math.max(peak, math.abs(left[frame] or 0)) end
  -- Center pan contributes 0.75 per side, so a 1.4 lead boost peaks ~0.5.
  check(peak > 0.45, "PCM lead boost missing: " .. tostring(peak))
  check(peak <= 0.65, "PCM lead boost too high: " .. tostring(peak))
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

do
  -- PCM carrier sides must not bury chip notes when spec.gain sits at the
  -- converter floor (0.35).  Pure-chip sides keep converter balance.
  local lowGain = 0.45 * 0.354
  local lifted = internals.chipGainFor(0.354, lowGain, true)
  check(math.abs(lifted - 0.36) < 0.01, "PCM chip gain " .. tostring(lifted))
  check(internals.chipGainFor(0.354, lowGain, false) == lowGain,
    "non-PCM side adjusted")
  check(math.abs(internals.chipGainFor(1, 0.45, true) - 0.45) < 1e-9,
    "full-gain side changed")
end

package.loaded["src.core.ChipSynth"] = previousSynth
print("extra_audio_pcm_loop_test: ok")
