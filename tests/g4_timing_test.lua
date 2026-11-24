-- Standalone G4 Mix timing/volume regression test.  Run from mod dir:
--   luajit tests/g4_timing_test.lua
local packagePath = package.path
package.path = "./?.lua;./tests/?.lua;" .. packagePath

local g4Mix = require("g4_mix")
local realG3 = require("g3_mix")

local function u24le(value)
  return string.char(value % 256, math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256)
end

local function varintEncode(value)
  local out = {}
  repeat
    local part = value % 128
    value = math.floor(value / 128)
    if value > 0 then part = part + 128 end
    out[#out + 1] = string.char(part)
  until value == 0
  return table.concat(out)
end

local function rest(ticks) return "\128" .. varintEncode(ticks) end
local function note(key, vel, ticks)
  return string.char(key, vel) .. varintEncode(ticks)
end

local function sseq(body, base, start)
  base = base or 0
  start = start or base
  local prefix = string.rep("\0", start)
  local header = string.char(0xFE, 0x01, 0x00, 0x93, 0x00) .. u24le(start - base + 8)
  local blob = prefix .. header .. body .. "\255"
  return { data = blob, base = base, start = start, size = #blob }
end

local captured

local function installFor(body, base, start)
  captured = nil
  local g3Mix = { clockAt = realG3.clockAt }
  function g3Mix.has() return true end
  function g3Mix.buildSpecs(song)
    captured = song
    return { { tempo = 100, channels = { { hw = 1, program = {} } } } }
  end
  local seq = sseq(body, base, start)
  local nds = {
    status = function() return { available = true, songCount = 1 } end,
    listSongs = function()
      return { { name = "SEQ_TIMING", index = 1, bank = 0, player = 0 } }
    end,
    readSequence = function() return seq end,
    readBank = function()
      return {
        count = 1,
        instruments = {
          [0] = { type = 1, defs = {
            [0] = { type = 1, waveID_dutyCycle = 0,
              attack = 120, decay = 100, sustain = 100, release = 80 },
          } },
        },
      }
    end,
  }
  local songMap = {
    BY_NAME = { SEQ_TIMING = "MUS_LEVEL_UP" },
    BY_KEY = { MUS_LEVEL_UP = { "SEQ_TIMING" } },
  }
  function songMap.keyFor(name) return songMap.BY_NAME[name] end
  function songMap.namesFor(key) return songMap.BY_KEY[key] or {} end
  assert(g4Mix.install({ g3Mix = g3Mix, nds = nds, songMap = songMap }))
  assert(g4Mix.convert("firered", "MUS_LEVEL_UP"))
  assert(captured and captured.trackData[1])
  return captured.trackData[1]
end

local function decodedNotes(bytes)
  local track = realG3.decodeTrack(bytes)
  local notes, tempo = {}
  for _, event in ipairs(track.events) do
    if event.kind == "tempo" then tempo = event.tempo end
    if event.kind == "note" then notes[#notes + 1] = event end
  end
  return notes, tempo
end

-- 120 BPM at 48 PPQN: one SSEQ tick is 1/96s.  g3_mix decodes our tempo byte
-- as 2*BPM = 240, so one M4A tick is 38400/240 = 160 GB ticks = 1/96s.
local BPM = 120
local GB_PER_TICK = 38400 / (BPM * 2)
assert(GB_PER_TICK == 160)

local body = {
  string.char(0xE1, BPM, 0x00), -- tempo
  string.char(0x81, 0x00),      -- program 0
  string.char(0xC1, 100),       -- volume 100/127
  string.char(0xD0, 64),        -- attack override 64/127
}
local starts = { 0, 7, 20, 49, 110, 206 }
local gates = { 7, 13, 29, 61, 96, 48 }
local previous = 0
for index, start in ipairs(starts) do
  if start > previous then body[#body + 1] = rest(start - previous) end
  body[#body + 1] = note(60 + index, 100, gates[index])
  previous = start
end
body[#body + 1] = rest(48)

local track = installFor(table.concat(body))
local notes, tempo = decodedNotes(track)
assert(tempo == BPM * 2, "decoded tempo must be 2*BPM, got " .. tostring(tempo))
assert(#notes == #starts, "note count " .. tostring(#notes))
for index, event in ipairs(notes) do
  assert(event.tick == starts[index], string.format(
    "note %d tick drift: got %d want %d", index, event.tick, starts[index]))
  assert(event.tick * GB_PER_TICK == starts[index] * 160, "GB start tick drift")
  local speed, length = realG3.noteTiming(event.gate)
  assert(speed * length <= event.gate, "note overruns gate")
  assert(event.gate - speed * length <= 1, "GB note length rounding drift")
end

-- SSEQ defaults to 120 BPM; explicit 0xE1 is optional.  Without it the first
-- note must still decode at 240, not M4A's 150 default.
local plain = installFor(string.char(0x81, 0x00, 0xC1, 100)
  .. note(60, 100, 48) .. rest(48))
local plainNotes, plainTempo = decodedNotes(plain)
assert(plainTempo == 240, "default SSEQ tempo must be 240, got "
  .. tostring(plainTempo))
assert(#plainNotes == 1 and plainNotes[1].tick == 0,
  "default-tempo note timing drift")

-- NDS SSEQ uses backward 0x94 JUMP for loops.  It must become a chip GOTO,
-- otherwise side tracks end after one pass while the lead keeps playing.
local loopBytes = installFor(string.char(0x81, 0x00)
  .. note(60, 100, 48) .. rest(48)
  .. string.char(0x94) .. u24le(10))
local loopTrack = realG3.decodeTrack(loopBytes)
assert(loopBytes:find(string.char(0xB2), 1, true), "missing loop GOTO")
assert(loopTrack.loopTick == 0, "loop GOTO must target tick 0, got "
  .. tostring(loopTrack.loopTick))
-- All wall-clock note times must be exact integer GB ticks at 15360 Hz.
assert(notes[2].tick - notes[1].tick == 7)
assert((notes[6].tick - notes[1].tick) * 160 == 206 * 160)

-- Volume scaling: 100/127 -> round(100*255/127) = 201, not floor(100/2)=50.
assert(track:find(string.char(0xBE, 201), 1, true),
  "M4A volume must scale 0..127 to 0..255")
-- Envelope override: round(64*15/127) = 8, not floor(64/8)=8 by luck; check a
-- second value that differs to catch the old divide-by-8 behaviour.
do
  local extra = {
    string.char(0xE1, BPM, 0x00), string.char(0x81, 0x00),
    string.char(0xD0, 100), note(60, 100, 12), rest(12),
  }
  local bytes = installFor(table.concat(extra))
  assert(bytes:find(string.char(0xCD, 4, 12), 1, true),
    "envelope 100/127 must round to GB envelope 12")
end

-- Practical case: consecutive 16th notes (every 12 SSEQ ticks) over two bars
-- at 120 BPM.  Each note is 1/8s; GB starts must stay exact for all 32 notes.
do
  local pattern = {
    string.char(0xE1, BPM, 0x00), string.char(0x81, 0x00),
  }
  for i = 1, 32 do
    pattern[#pattern + 1] = note(60 + (i % 5), 100, 12)
    pattern[#pattern + 1] = rest(12)
  end
  local bytes = installFor(table.concat(pattern))
  local patternNotes, patternTempo = decodedNotes(bytes)
  assert(patternTempo == BPM * 2)
  assert(#patternNotes == 32, "practical pattern lost notes")
  for index, event in ipairs(patternNotes) do
    assert(event.tick == (index - 1) * 12, string.format(
      "16th note %d drift: %d", index, event.tick))
    assert(event.gate == 12)
    assert(event.tick * 160 == (index - 1) * 12 * 160)
  end
end

-- Standalone SSEQ files return the whole blob with a dataOffset base.  Jump
-- destinations are relative to that base; without translation the loop marker
-- lands in the header and side tracks stop early.
do
  local base = 12
  local body = string.char(0x81, 0x00) .. note(60, 100, 48) .. rest(48)
    .. string.char(0x94, 0x08, 0x00, 0x00)
  local bytes = installFor(body, base)
  local loopTrack = realG3.decodeTrack(bytes)
  assert(bytes:find(string.char(0xB2), 1, true),
    "based jump must emit GOTO")
  assert(loopTrack.loopTick == 0,
    "based jump loopTick wrong: " .. tostring(loopTrack.loopTick))
end

-- SSAR sub-songs share an events blob: base 0, header at `first`.  Both the
-- header offsets and jump destinations stay relative to base 0.
do
  local start = 12
  local body = string.char(0x81, 0x00) .. note(60, 100, 48) .. rest(48)
    .. string.char(0x94, start + 8, 0x00, 0x00)
  local bytes = installFor(body, 0, start)
  local loopTrack = realG3.decodeTrack(bytes)
  assert(#loopTrack.events >= 2, "SSAR header offset missed the track")
  assert(bytes:find(string.char(0xB2), 1, true),
    "SSAR jump must emit GOTO")
  assert(loopTrack.loopTick == 0,
    "SSAR jump loopTick wrong: " .. tostring(loopTrack.loopTick))
end

package.path = packagePath
print("g4_timing_test: ok")
