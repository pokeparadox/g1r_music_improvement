-- Standalone: luajit tests/g3_engine_inventory_test.lua
-- Verifies G3 Mix keeps every decoded 4-track group, every chip voice kind,
-- and DirectSound notes as PCM across all emitted engines.
package.path = "./?.lua;../gen1recomp/?.lua;" .. package.path
local mix = dofile("g3_mix.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- 0xBD selects voice; 0xD3 emits a note; 0xB1 ends the track.
local function track(voice, key)
  return string.char(0xBD, voice, 0xD3, key, 100, 0xB1)
end

local wave = {}
for i = 1, 32 do wave[i] = (i % 2) * 15 end

local samples = {
  [7] = { id = 7, key = 43, freq = 13379 * 1024, offset = 0, size = 100,
    loopStart = 0, status = 0 },
}
-- Engine 1: pulse, pulse, wave, noise. Engine 2: pulse, pulse, wave, sample.
local voicegroups = {
  [1] = {
    [1] = { type = 1 }, [2] = { type = 2 },
    [3] = { type = 3, wave = wave }, [4] = { type = 4 },
    [5] = { type = 1 }, [6] = { type = 2 },
    [7] = { type = 3, wave = wave }, [8] = { type = 0, sampleId = 7 },
  },
}
local song = {
  tracks = 8,
  trackData = {
    track(1, 36), track(2, 37), track(3, 38), track(4, 39),
    track(5, 40), track(6, 41), track(7, 42), track(8, 43),
  },
  voicegroup = 1,
}
local specs = mix.buildSpecs(song, voicegroups, {
  voicegroupId = 1, samples = samples, version = "firered",
})
assert(specs and #specs == 2, "8 decoded tracks need 2 engines")
eq(specs[1].pcm, nil, "base engine stays chip-only")
assert(specs[2].pcm, "PCM carrier must be present")
eq(#specs[2].pcm.events, 1, "every sample note must become PCM")
eq(specs[2].pcm.events[1].key, 43, "PCM note key preserved")

local keys, kinds = {}, { duty = 0, wave = 0, drum = 0, onset = 0 }
for specIndex, spec in ipairs(specs) do
  eq(#spec.channels, 4, "engine " .. specIndex .. " channel count")
  assert(#spec.waves >= 4, "engine " .. specIndex .. " waves")
  eq(#spec.drums, 5, "engine " .. specIndex .. " drums")
  assert(spec.tempo > 0, "engine " .. specIndex .. " tempo")
  assert(type(spec.pan) == "number", "engine " .. specIndex .. " pan")
  for _, channel in ipairs(spec.channels) do
    local pendingOctave, waveNote = nil, false
    for i, event in ipairs(channel.program) do
      if event.notetype then
        if not channel.program[i + 1].rest then
          kinds.onset = kinds.onset + 1
        end
        waveNote = event.notetype.waveInstrument ~= nil
        if waveNote then kinds.wave = kinds.wave + 1 end
      elseif event.duty then
        kinds.duty = kinds.duty + 1
      elseif event.drum then
        kinds.drum = kinds.drum + 1
      elseif event.octave then
        pendingOctave = event.octave
      elseif event.pitch and pendingOctave then
        local key = pendingOctave * 12 + event.pitch + (waveNote and 0 or 12)
        keys[key] = true
        pendingOctave = nil
      end
    end
  end
end

-- 7 chip notes: two pulse + one wave + one noise per engine, minus the
-- DirectSound note that moved to PCM. Noise occupies the drum channel.
eq(kinds.onset, 7, "all chip notes emitted")
eq(kinds.duty, 4, "pulse voices emitted")
eq(kinds.wave, 2, "wave voices emitted")
eq(kinds.drum, 1, "noise voice emitted")
eq(count(keys), 6, "six pitched chip tracks emitted")
for _, key in ipairs({ 36, 37, 38, 40, 41, 42 }) do
  assert(keys[key], "missing chip note key " .. key)
end

print("g3_engine_inventory_test: ok")
