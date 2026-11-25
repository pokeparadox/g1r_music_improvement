-- Gen2 G4 Mix sustained-wave lead fallback test. Run from mod root:
--   luajit tests/g4_lead_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path

local realG3 = require("g3_mix")
local versions = require("versions")
local g4Mix = require("g4_mix")

local function u24le(value)
  return string.char(value % 256, math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256)
end

local function note(key, duration)
  return string.char(key, 100, duration)
end

-- Program 0: sustained high wave voice. Program 1: short high wave voice.
-- Both are sampled SWAV voices on NDS; only the sustained one should gain a
-- duty/pulse fallback on gen2.
local events = string.char(0xE1, 120, 0x00, 0xC7, 0x00, 0x81, 0x00)
  -- Distinct keys: g3_mix dedups same-tick same-key notes as a single chord.
  .. note(72, 48) .. note(74, 48) .. note(76, 48)
  .. string.char(0x81, 0x01)
  .. note(80, 2) .. note(81, 2) .. note(82, 2)
  .. string.char(0xFF)
local blob = string.char(0xFE, 0x01, 0x00, 0x93, 0x00) .. u24le(8) .. events

local captured
local g3Mix = {
  clockAt = realG3.clockAt,
  has = function() return true end,
}
function g3Mix.buildSpecs(song, voicegroups, info)
  captured = { song = song, voicegroups = voicegroups, info = info }
  return realG3.buildSpecs(song, voicegroups, info)
end

local function def(waveID)
  return { [1] = {
    type = 0, waveID = waveID, waveArchiveID = 0, pitch = 60,
    attack = 100, decay = 100, sustain = 100, release = 100,
    keyLow = 0, keyHigh = 127,
  } }
end
local nds = {
  status = function() return { available = true, songCount = 1 } end,
  listSongs = function()
    return { { name = "SEQ_GS_LEAD", index = 1, bank = 0, player = 1 } }
  end,
  readSequence = function()
    return { data = blob, base = 0, start = 0, size = #blob }
  end,
  readBank = function()
    return {
      count = 2,
      instruments = {
        [1] = { type = 0, defs = def(1) },
        [2] = { type = 0, defs = def(2) },
      },
    }
  end,
}
local songMap
songMap = {
  BY_NAME = { SEQ_GS_LEAD = "Music_G4LeadTest" },
  BY_KEY = { Music_G4LeadTest = { "SEQ_GS_LEAD" } },
  keyFor = function(name) return songMap.BY_NAME[name] end,
  namesFor = function(key) return songMap.BY_KEY[key] or {} end,
}

assert(g4Mix.install({ g3Mix = g3Mix, nds = nds, songMap = songMap,
  versions = versions }) == true)

local gold, err = g4Mix.convert("gold", "Music_G4LeadTest")
assert(gold, err)
assert(gold.def.converter == "g4_v13",
  "converter version must change for gen2 lead fallback: "
    .. tostring(gold.def.converter))
assert(captured.voicegroups[1][1].leadDuty == 2,
  "sustained high wave voice must gain pulse fallback")
assert(captured.voicegroups[1][2].leadDuty == nil,
  "short high wave voice must stay on wave channel")

local hasDuty = false
for _, spec in ipairs(g3Mix.buildSpecs(captured.song, captured.voicegroups,
    captured.info)) do
  for _, channel in ipairs(spec.channels or {}) do
    for _, action in ipairs(channel.program or {}) do
      if action.duty == 2 then hasDuty = true end
    end
  end
end
assert(hasDuty, "gen2 fallback must emit duty actions")

local firered, err = g4Mix.convert("firered", "Music_G4LeadTest")
assert(firered, err)
assert(captured.voicegroups[1][1].leadDuty == nil,
  "gen3 must keep PCM refs, not pulse fallback")

print("g4_lead_test: ok")
