-- Standalone: luajit tests/gba_pcm_runtime_test.lua
-- Verifies GBA sample defs reach the reader and rateHz controls phase.
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
local factory = assert(load(source, "gba_pcm_runtime_test", "t"))()

local function check(value, message)
  if not value then error("FAIL: " .. message, 2) end
end

local audio = factory()
local seenBank, seenDef
audio.setSampleReader(function(bank, def)
  seenBank, seenDef = bank, def
  return {
    data = string.rep(string.char(0, 0), 64), sampleRate = 44100,
    loop = false, loopStart = 0, loopEnd = 63,
  }
end)

local bank = { gba = true, version = "firered", sampleId = 7,
  offset = 4, size = 8, freq = 13379 * 1024, loopStart = 0, status = 0 }
local built = audio._internals.pcmPrepare({}, {
  pcm = {
    events = { { tick = 0, gate = 5000, key = 60, pitch = 60,
      rateHz = 22050, vel = 100, volume = 100, pan = 0x40,
      bank = bank, archive = 7, wave = 0 } },
    tempoTimeline = { { tick = 0, tempo = 300, gb = 128 } },
  },
})
check(built, "GBA PCM prepare failed")
check(seenBank == bank, "reader got GBA bank")
check(seenDef == bank, "reader got GBA def")

local left, right = {}, {}
for i = 0, 7 do left[i], right[i] = 0, 0 end
audio._internals.pcmRender(built, left, right, 0, 4, 1)
check(#built.active == 1, "GBA PCM voice missing")
check(math.abs(built.active[1].phase - 2) < 1e-9,
  "rateHz must set phase step: " .. tostring(built.active[1].phase))

-- Gen3 starts gbaExtraAudio from gen3.lua, never extraAudio. Both instances
-- must be pumped or FR PCM buffers are never queued.
local main = assert(io.open("main.lua", "rb")):read("*a")
local needle = "for _, audio in ipairs({ extraAudio, gbaExtraAudio }) do"
local wired, from = 0, 1
while true do
  local at = main:find(needle, from, true)
  if not at then break end
  wired, from = wired + 1, at + 1
end
check(wired >= 2, "main.lua must drive both extra engines in frameGuard and game.update")
check(main:find("pcall(audio.update)", 1, true), "main.lua must pump the active extra engine")

if previousSynth ~= nil then
  package.loaded["src.core.ChipSynth"] = previousSynth
else
  package.loaded["src.core.ChipSynth"] = nil
end
print("gba_pcm_runtime_test: ok")
