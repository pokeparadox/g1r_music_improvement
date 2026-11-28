-- Standalone: luajit tests/g3_pcm_retrigger_test.lua
-- Legato on a looping sample keeps its phase; chords and later notes do not.
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

local function newAudio(loop)
  local audio = factory()
  audio.setSampleReader(function()
    return {
      data = string.rep(string.char(0xE8, 0x03), 6000),
      sampleRate = 44100, loop = loop, loopStart = loop and 4301 or 0,
      loopEnd = 5999,
    }
  end)
  return audio
end

local function note(tick, gate)
  return {
    tick = tick, gate = gate, key = 74, pitch = 74, vel = 100,
    volume = 100, pan = 0x40, rateHz = 44100,
    attack = 0, decay = 0, sustain = 255, release = 0,
    bank = 1, archive = 0, wave = 1,
  }
end

local function mixes(count)
  local left, right = {}, {}
  for i = 0, count - 1 do left[i], right[i] = 0, 0 end
  return left, right
end

local function prepare(audio, events)
  local built = audio._internals.pcmPrepare({}, {
    pcm = { events = events, tempoTimeline = { { tick = 0, tempo = 300 } } },
  })
  check(built, "PCM prepare failed")
  return built
end

local legato = newAudio(true)
local legatoBuilt = prepare(legato, { note(0, 6), note(6, 6), note(12, 6) })
check(legatoBuilt.stats.events == 3, "expected 3 legato events")
check(legatoBuilt.stats.spawned == 0, "no voices before render")
local legatoLeft, legatoRight = mixes(4096)
legato._internals.pcmRender(legatoBuilt, legatoLeft, legatoRight, 0, 4096, 1)
check(legatoBuilt.stats.spawned == 1, "legato must spawn one voice")
check(legatoBuilt.stats.retriggered == 1, "expected first legato retune")
local phaseBeforeLast = legatoBuilt.active[1].phase
check(phaseBeforeLast > 4000, "phase advanced before last note")
local legatoLeft2, legatoRight2 = mixes(1024)
legato._internals.pcmRender(legatoBuilt, legatoLeft2, legatoRight2, 4096, 1024, 1)
check(legatoBuilt.stats.spawned == 1, "legato must not spawn more voices")
check(legatoBuilt.stats.retriggered == 2, "expected two legato retunes")
check(legatoBuilt.active[1].phase > 4000, "retuned note kept phase")
check(legatoBuilt.stats.stolen == 0, "legato must not steal")

local nonLoop = newAudio(false)
local nonLoopBuilt = prepare(nonLoop, { note(0, 6), note(6, 6), note(12, 6) })
for start = 0, 10240 - 1024, 1024 do
  local left, right = mixes(1024)
  nonLoop._internals.pcmRender(nonLoopBuilt, left, right, start, 1024, 1)
end
check(nonLoopBuilt.stats.spawned == 3, "non-loop notes must retrigger")
check(nonLoopBuilt.stats.retriggered == 0, "non-loop notes must not retune")

local chord = newAudio(true)
local chordBuilt = prepare(chord, { note(0, 6), note(0, 6) })
local chordLeft, chordRight = mixes(1024)
chord._internals.pcmRender(chordBuilt, chordLeft, chordRight, 0, 1024, 1)
check(chordBuilt.stats.spawned == 2, "same-tick notes are a chord")
check(chordBuilt.stats.retriggered == 0, "chord must not collapse")
check(#chordBuilt.active == 2, "chord needs two voices")

local late = newAudio(true)
local lateBuilt = prepare(late, { note(0, 300), note(200, 6) })
for start = 0, 81920 - 1024, 1024 do
  local left, right = mixes(1024)
  late._internals.pcmRender(lateBuilt, left, right, start, 1024, 1)
end
check(lateBuilt.stats.spawned == 2, "note after loopStart must retrigger")
check(lateBuilt.stats.retriggered == 0, "late note must not retune")

print("pass: g3 PCM legato retrigger")
package.loaded["src.core.ChipSynth"] = previousSynth
