-- Standalone: luajit tests/extra_audio_timing_test.lua
-- Verifies harmony timing pauses with the base source and queue retries do
-- not lose already-rendered samples.
package.path = "./?.lua;./?/init.lua;" .. package.path

local previousLove = love
local previousSynth = package.loaded["src.core.ChipSynth"]
local previousAudio = package.loaded["src.core.ChipAudio"]

local now = 100
local baseSource = { playing = true }
function baseSource:isPlaying() return self.playing end

local sources = {}
local initialFree = 1000
local failQueue = false
local synth = { SAMPLE_RATE = 1000, engines = {} }
function synth.newEngine()
  local engine = { samples = 0 }
  synth.engines[#synth.engines + 1] = engine
  return engine
end
function synth.soundData(engine, samples)
  engine.samples = engine.samples + samples
  return { getSample = function() return 0 end }
end
function synth.newBuffer(samples, channels)
  return {
    samples = samples,
    channels = channels,
    setSample = function() end,
  }
end

package.loaded["src.core.ChipSynth"] = synth
package.loaded["src.core.ChipAudio"] = {
  currentSource = function() return baseSource end,
}

love = {
  timer = { getTime = function() return now end },
  audio = {
    newQueueableSource = function(_, _, _, bufferCount)
      local source = {
        free = initialFree,
        bufferCount = bufferCount,
        playing = false,
        queued = 0,
      }
      function source:isPlaying() return self.playing end
      function source:play() self.playing = true end
      function source:pause() self.playing = false end
      function source:stop() self.playing = false end
      function source:getFreeBufferCount() return self.free end
      function source:queue()
        if failQueue then return false end
        if self.free < 1 then error("queue is full") end
        self.free = self.free - 1
        self.queued = self.queued + 1
        return true
      end
      sources[#sources + 1] = source
      return source
    end,
  },
}

local factory = assert(loadfile("extra_audio.lua"))()
local function newAudio()
  return factory()
end
local function newExtra(audio, looping, basePlayClock)
  audio.start({ left = { chip = {} } }, {},
    basePlayClock or now, looping)
  return synth.engines[#synth.engines]
end
local function check(value, message)
  if not value then error("FAIL: " .. message, 2) end
end
local function eq(actual, expected, message)
  if actual ~= expected then
    error(("FAIL: %s (expected %s, got %s)"):format(
      message, tostring(expected), tostring(actual)), 2)
  end
end

-- A paused base source must not accrue the pause duration as elapsed audio.
local audio = newAudio()
local engine = newExtra(audio, true)
audio.update()
now = 101
audio.update()
now = 102
audio.update()
baseSource.playing = false
now = 103
audio.update()
local beforePause = engine.samples
now = 203
audio.update()
eq(engine.samples, beforePause, "a paused base does not advance harmony")
baseSource.playing = true
audio.update()
now = 204
audio.update()
check(engine.samples < 14000, "resuming after a long pause does not fast-forward")
audio.stop()

-- A full queue prevents synthesis; a failed queue keeps its PCM for retry.
now = 300
initialFree = 0
failQueue = false
baseSource.playing = true
audio = newAudio()
engine = newExtra(audio, true)
audio.update()
eq(engine.samples, 0, "a full output queue does not render and discard samples")

sources[#sources].free = 1
failQueue = true
audio.update()
eq(engine.samples, 512, "a queue failure retains one rendered chunk")
failQueue = false
audio.update()
eq(engine.samples, 512, "retry queues retained PCM without rendering it twice")
eq(sources[#sources].queued, 1, "the retained chunk reaches the source on retry")
audio.stop()

-- A harmony start that arrives after base playback has begun aligns to the
-- source's playback cursor instead of assuming playback starts at sample zero.
now = 350
initialFree = 1000
baseSource.samples = 4096
function baseSource:tell(unit)
  if unit == "samples" then return self.samples end
  return self.samples / synth.SAMPLE_RATE
end
audio = newAudio()
engine = newExtra(audio, true)
audio.update()
eq(engine.samples, 12288, "late harmony start skips the base source's played samples")
audio.stop()
baseSource.tell = nil

-- When tell is unavailable, the supplied clock must represent the base
-- Source's actual start time, not the earlier update that queued its first
-- worker buffer.
now = 375
initialFree = 1000
audio = newAudio()
engine = newExtra(audio, true, now - 0.125)
audio.update()
eq(engine.samples, 8317,
  "fallback cursor estimate skips elapsed playback before queueing harmony")
audio.stop()

-- A non-looping one-shot uses the shorter lead; looping songs retain the
-- longer lead needed for stall tolerance.
initialFree = 1000
now = 400
audio = newAudio()
engine = newExtra(audio, false)
audio.update()
eq(engine.samples, 2048, "one-shot harmony keeps its shorter lead")
audio.stop()

now = 500
audio = newAudio()
engine = newExtra(audio, true)
audio.update()
eq(engine.samples, 8192, "looping harmony keeps its full lead")
audio.stop()

package.loaded["src.core.ChipSynth"] = previousSynth
package.loaded["src.core.ChipAudio"] = previousAudio
love = previousLove
print("extra_audio_timing_test: all checks passed")
