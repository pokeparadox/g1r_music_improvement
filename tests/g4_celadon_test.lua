-- G4 Mix Celadon regression: implicit main track, global tempo, per-track
-- chip specs and loop boundaries. Run from mod dir:
--   luajit tests/g4_celadon_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path

local g4Mix = require("g4_mix")
local realG3 = require("g3_mix")
local versions = require("versions")

local function u16le(value)
  return string.char(value % 256, math.floor(value / 256) % 256)
end
local function u24le(value)
  return string.char(value % 256, math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256)
end
local function varint(value)
  local out = {}
  repeat
    local part = value % 128
    value = math.floor(value / 128)
    if value > 0 then part = part + 128 end
    out[#out + 1] = string.char(part)
  until value == 0
  return table.concat(out)
end
local function note(key, vel, duration)
  return string.char(key, vel) .. varint(duration)
end
local function rest(ticks)
  return string.char(0x80) .. varint(ticks)
end
-- Real HGSS tracks start in poly mode (C7 0): notes overlap and a rest
-- supplies the loop spacing.
local function loopTrack(key, gate)
  return string.char(0xC7, 0x00, 0x81, 0x00, 0xD4, 0x00)
    .. note(key, 100, gate) .. rest(gate) .. string.char(0xFC, 0xFF)
end

-- 13 tracks in the mask, but only 12 explicit 0x93 commands: track 0 is the
-- decoder continuation at the byte after those commands. Its `C7 00` must not
-- swallow the following `E1 82 00` (130 BPM) global tempo.
local main = string.char(0xC7, 0x00, 0xE1, 0x82, 0x00) .. loopTrack(60, 48)
local bodies, offsets = {}, {}
local cursor = 63 + #main
for i = 1, 12 do
  bodies[i] = loopTrack(60 + i, 12 + i)
  offsets[i] = cursor
  cursor = cursor + #bodies[i]
end
local commands = {}
for i = 1, 12 do
  commands[i] = string.char(0x93, i) .. u24le(offsets[i])
end
local blob = string.char(0xFE) .. u16le(0x1FFF)
  .. table.concat(commands) .. main .. table.concat(bodies)

local calls = {}
local g3Mix = { clockAt = realG3.clockAt, has = function() return true end }
function g3Mix.buildSpecs(song, voicegroups, info)
  calls[#calls + 1] = { tracks = song.tracks, bytes = song.trackData[1] }
  return realG3.buildSpecs(song, voicegroups, info)
end

local name = "SEQ_GS_C_TAMAMUSHI"
local nds = {}
function nds.status() return { available = true, songCount = 1 } end
function nds.listSongs()
  return { { name = name, index = 1, bank = 715, player = 1 } }
end
function nds.readSequence(song)
  if song.name ~= name then return nil end
  return { data = blob, base = 0, start = 0, size = #blob }
end
function nds.readBank(bankID)
  assert(bankID == 715, "sequence bank must be inherited")
  return {
    count = 1,
    instruments = {
      [0] = { type = 1, defs = {
        [0] = { type = 1, waveID_dutyCycle = 0, waveArchiveID = 0,
          pitch = 60, attack = 100, decay = 100, sustain = 100,
          release = 80, pan = 64 },
      } },
    },
  }
end

local songMap = {
  BY_NAME = { [name] = "Music_Celadon" },
  BY_KEY = { Music_Celadon = { name } },
}
function songMap.keyFor(songName) return songMap.BY_NAME[songName] end
function songMap.namesFor(key) return songMap.BY_KEY[key] or {} end

assert(g4Mix.install({ g3Mix = g3Mix, nds = nds, songMap = songMap,
  versions = versions }))
local converted, err = g4Mix.convert("gold", "Music_CeladonCity")
assert(converted, err)
assert(converted.tracks == 13, "implicit main track lost: "
  .. tostring(converted.tracks))
assert(#calls == 13, "expected one chip spec per track, got " .. tostring(#calls))
for index, call in ipairs(calls) do
  assert(call.tracks == 1, "spec " .. index .. " bundled multiple tracks")
  -- 0xE1 is global; every track must carry 130 BPM, not just the main track.
  assert(call.bytes:find(string.char(0xBB, 130), 1, true),
    "track " .. index .. " missed global 130 BPM tempo")
end

local specs = { converted.def }
local extras = 0
for _, spec in pairs(converted.extra) do
  extras = extras + 1
  specs[#specs + 1] = spec
end
assert(extras == 12, "expected g4_2..g4_13, got " .. tostring(extras))

local function loopTick(spec)
  local speed, ticks = 1, 0
  for _, action in ipairs(spec.channels[1].program) do
    if action.notetype and action.notetype.speed then
      speed = action.notetype.speed
    elseif action.rest then
      ticks = ticks + speed * action.rest
    elseif action.pitch or action.drum then
      ticks = ticks + speed * (action.len or 0)
    elseif action.loop then
      return ticks
    end
  end
  return nil
end

local distinctLoops = {}
for index, spec in ipairs(specs) do
  local tick = loopTick(spec)
  assert(tick and tick > 0, "spec " .. index .. " has no loop boundary")
  distinctLoops[tick] = true
end
local count = 0
for _ in pairs(distinctLoops) do count = count + 1 end
assert(count >= 3, "tracks must loop at their own boundaries, not one global tick")

print("g4_celadon_test: ok")
