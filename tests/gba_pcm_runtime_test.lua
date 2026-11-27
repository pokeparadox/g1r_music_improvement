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
      attack = 255, decay = 0, sustain = 255, release = 0,
      bank = bank, archive = 7, wave = 0 } },
    tempoTimeline = { { tick = 0, tempo = 300, gb = 128 } },
  },
})
check(built, "GBA PCM prepare failed")
check(built.events[1].attack == 255 and built.events[1].decay == 0
  and built.events[1].sustain == 255 and built.events[1].release == 0,
  "MP2K ADSR must survive pcmPrepare")
check(seenBank == bank, "reader got GBA bank")
check(seenDef == bank, "reader got GBA def")

local left, right = {}, {}
for i = 0, 7 do left[i], right[i] = 0, 0 end
audio._internals.pcmRender(built, left, right, 0, 4, 1)
check(#built.active == 1, "GBA PCM voice missing")
check(math.abs(built.active[1].phase - 2) < 1e-9,
  "rateHz must set phase step: " .. tostring(built.active[1].phase))

local long = audio._internals.pcmPrepare({}, {
  pcm = {
    events = { { tick = 0, gate = 5000, key = 60, pitch = 60,
      rateHz = 22050, vel = 100, volume = 100, pan = 0x40,
      attack = 255, decay = 0, sustain = 255, release = 255,
      bank = bank, archive = 7, wave = 0 } },
    tempoTimeline = { { tick = 0, tempo = 300, gb = 128 } },
  },
})
audio._internals.pcmRender(long, left, right, 0, 4, 1)
check(long.active[1].stop > built.active[1].stop + 1000,
  "MP2K release must extend voice tail")

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
check(main:find("pcall(extraAudio.update)", 1, true),
  "main.lua must pump the active extra engine")
local gen3 = assert(io.open("gen3.lua", "rb")):read("*a")
check(gen3:find("pcall(deps.extraAudio.update)", 1, true),
  "gen3.lua must pump the injected GBA extra engine")
check(main:find("byte >= 128 then byte = byte - 256 end", 1, true),
  "GBA s8 samples must stay sign-extended")
check(main:find("string.char(0, byte % 256)", 1, true),
  "GBA s8->s16 must scale by 256 (raw byte in high byte)")
check(main:find("/ 16384) % 2 == 1", 1, true),
  "GBA loop detection must use the 0x4000 flag bit")

if previousSynth ~= nil then
  package.loaded["src.core.ChipSynth"] = previousSynth
else
  package.loaded["src.core.ChipSynth"] = nil
end
print("gba_pcm_runtime_test: ok")
