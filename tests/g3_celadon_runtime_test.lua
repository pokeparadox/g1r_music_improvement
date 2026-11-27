-- Standalone: luajit tests/g3_celadon_runtime_test.lua
-- G3 Mix Celadon-like PCM must resolve, render, and report telemetry.
package.path = "./?.lua;./?/init.lua;" .. package.path

local previousSynth = package.loaded["src.core.ChipSynth"]
package.loaded["src.core.ChipSynth"] = { SAMPLE_RATE = 44100 }

local source = assert(io.open("extra_audio.lua", "rb")):read("*a")
local needle = "  return {\n    start = start,"
local replacement = [[  return {
    _internals = {
      pcmPrepare = pcmPrepare, pcmRender = pcmRender,
      state = state,
    },
    start = start,]]
source, count = source:gsub(needle, replacement, 1)
assert(count == 1, "extra_audio internals injection failed")
local factory = assert(load(source, "extra_audio_test", "t"))()

local function check(value, message)
  if not value then error("FAIL: " .. message, 2) end
end

local audio = factory()
local internals = audio._internals

local frames = {}
for i = 0, 255 do
  local value = i % 2 == 0 and 10000 or -10000
  frames[#frames + 1] = string.char(value % 256, math.floor(value / 256) % 256)
end
local sample = table.concat(frames)
local sampleBank = {
  gba = true, version = "firered", sampleId = 33,
  offset = 0, size = #sample, freq = 6000 * 1024,
  loopStart = 0, status = 0x4000,
}
audio.setSampleReader(function(bank)
  if bank and bank.gba and bank.sampleId == 33 then
    return { data = sample, sampleRate = 44100,
      loop = true, loopStart = 0, loopEnd = 255 }
  end
  return nil
end)

local function event(tick, key, rateHz)
  local bank = {}
  for k, v in pairs(sampleBank) do bank[k] = v end
  return {
    tick = tick, gate = 300, key = key, pitch = key, vel = 120,
    volume = 26, pan = 96, bank = bank, archive = 0, wave = 0,
    rateHz = rateHz, attack = 255, decay = 252, sustain = 0, release = 239,
  }
end

local built = internals.pcmPrepare({}, {
  pcm = {
    events = {
      event(0, 66, 18920),
      event(48, 66, 18920),
      event(96, 69, 11250),
    },
    tempoTimeline = { { tick = 0, tempo = 150 } },
    loopStartTick = 0, loopEndTick = 3456,
  },
})
check(built, "Celadon-like PCM prepare failed")
check(#built.events == 3, "expected 3 PCM events")
check(#built.active == 0, "PCM voices must start empty")
check(built.stats.ready == 3, "all Celadon-like samples must resolve")
check(built.stats.missing == 0, "no Celadon-like sample may be dropped")

local left, right = {}, {}
for i = 0, 22050 do left[i], right[i] = 0, 0 end
internals.pcmRender(built, left, right, 0, 22050, 1)
check(#built.active > 0, "Celadon-like PCM voices never started")
local peak = 0
for i = 0, 22050 do
  peak = math.max(peak, math.abs(left[i]), math.abs(right[i]))
end
check(peak > 0.05, "Celadon-like PCM peak too low: " .. tostring(peak))
check(built.stats.peak > 0.05, "PCM telemetry peak missing")
check(built.stats.active <= 16, "PCM voices exceed MAX_PCM_VOICES")

internals.state.pcms["g3_2"] = built
local t = audio.telemetry()
check(t and t.pcm and t.pcm.g3_2, "PCM telemetry missing g3_2 side")
check(t.pcm.g3_2.events == 3, "PCM telemetry event count wrong")
check(t.pcm.g3_2.ready == 3, "PCM telemetry ready count wrong")
check(t.pcm.g3_2.missing == 0, "PCM telemetry missing count wrong")
check(t.pcm.g3_2.active > 0, "PCM telemetry active count wrong")
check(t.pcm.g3_2.peak > 0.05, "PCM telemetry peak wrong")

package.loaded["src.core.ChipSynth"] = previousSynth
print("g3_celadon_runtime_test ok")
