-- Standalone: luajit tests/g3_pcm_retrigger_test.lua
-- Looping legato keeps phase across gaps/chords by track; non-loop retriggers.
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

local function note(tick, gate, track)
  return {
    tick = tick, gate = gate, track = track or 1,
    key = 74, pitch = 74, vel = 100, volume = 100, pan = 0x40,
    rateHz = 44100, attack = 255, decay = 0, sustain = 255, release = 196,
    bank = 1, archive = 0, wave = 1,
  }
end

local function prepare(audio, events)
  local built = audio._internals.pcmPrepare({}, {
    pcm = { events = events, tempoTimeline = { { tick = 0, tempo = 300 } } },
  })
  check(built, "PCM prepare failed")
  return built
end

local function render(audio, built, total)
  local start = built.pos or 0
  while start < total do
    local count = math.min(1024, total - start)
    local left, right = {}, {}
    for i = 0, count - 1 do left[i], right[i] = 0, 0 end
    audio._internals.pcmRender(built, left, right, start, count, 1)
    start = start + count
  end
end

-- Same sample, same track, phase already past loopStart: still legato.
local legato = newAudio(true)
local legatoBuilt = prepare(legato, {
  note(0, 36), note(24, 6), note(48, 6),
})
render(legato, legatoBuilt, 20480)
check(legatoBuilt.stats.events == 3, "expected 3 legato events")
check(legatoBuilt.stats.spawned == 1, "legato must spawn one voice")
check(legatoBuilt.stats.retriggered == 2, "expected two legato retunes")
check(legatoBuilt.stats.stolen == 0, "legato must not steal")

-- Released tail with a short gap re-engages instead of retriggering phase 0.
local released = newAudio(true)
local releasedBuilt = prepare(released, { note(0, 6), note(12, 6) })
render(released, releasedBuilt, 4096)
local phaseBeforeGap = releasedBuilt.active[1] and releasedBuilt.active[1].phase
check(phaseBeforeGap and phaseBeforeGap > 4000, "gap voice must advance phase")
render(released, releasedBuilt, 6144)
check(releasedBuilt.stats.spawned == 1, "short released gap must not spawn")
check(releasedBuilt.stats.retriggered == 1, "short released gap must re-engage")
check(releasedBuilt.active[1].phase > phaseBeforeGap, "re-engaged voice kept phase")

-- Same sample on another track is a different voice.
local crossTrack = newAudio(true)
local crossBuilt = prepare(crossTrack, { note(0, 6, 1), note(6, 6, 2) })
render(crossTrack, crossBuilt, 8192)
check(crossBuilt.stats.spawned == 2, "different tracks must spawn separately")
check(crossBuilt.stats.retriggered == 0, "different tracks must not retune")

-- Same-tick notes are a chord, not legato.
local chord = newAudio(true)
local chordBuilt = prepare(chord, { note(0, 6), note(0, 6) })
render(chord, chordBuilt, 1024)
check(chordBuilt.stats.spawned == 2, "same-tick notes are a chord")
check(chordBuilt.stats.retriggered == 0, "chord must not collapse")
check(#chordBuilt.active == 2, "chord needs two voices")

-- Gap beyond the release window is a fresh note.
local late = newAudio(true)
local lateBuilt = prepare(late, { note(0, 6), note(60, 6) })
render(late, lateBuilt, 24576)
check(lateBuilt.stats.spawned == 2, "long gap must spawn a new voice")
check(lateBuilt.stats.retriggered == 0, "long gap must not retune")

-- Non-loop samples always retrigger.
local nonLoop = newAudio(false)
local nonLoopBuilt = prepare(nonLoop, { note(0, 6), note(6, 6), note(12, 6) })
render(nonLoop, nonLoopBuilt, 8192)
check(nonLoopBuilt.stats.spawned == 3, "non-loop notes must retrigger")
check(nonLoopBuilt.stats.retriggered == 0, "non-loop notes must not retune")

print("pass: g3 PCM legato retrigger")
package.loaded["src.core.ChipSynth"] = previousSynth
