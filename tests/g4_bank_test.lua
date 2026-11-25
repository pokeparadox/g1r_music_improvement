-- Verifies SSEQ program banks and SBNK 1-based note definitions survive the
-- G4 conversion.  A program event with bank 0 must keep the sequence bank;
-- only a nonzero program bank may switch banks.
package.path = "/mnt/Storage/RiderProjects/g1r_music_improvement/?.lua;" .. package.path
local realG3 = require("g3_mix")

local function check(cond, message)
  if not cond then error(message, 2) end
end
local function eq(actual, expected, message)
  check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function vlq(value)
  if value < 128 then return string.char(value) end
  return string.char(0x80 + math.floor(value / 128), value % 128)
end
local function sseq(program)
  return string.char(0xFE, 0x01, 0x00, 0x93, 0x00)
    .. string.char(0x08, 0x00, 0x00)
    .. string.char(0x81) .. vlq(program)
    .. string.char(60, 100, 48, 0x80, 48, 0xFF)
end
local function sequence(name, program)
  return {
    name = name, index = 1, bank = 700, player = 1,
    blob = sseq(program),
  }
end

local songs = {
  sequence("SEQ_BANK_KEEP", 39),
  sequence("SEQ_BANK_SWITCH", 128 + 39),
}
local bankCalls = {}
local captured = {}

local nds = {
  status = function() return { available = true, songCount = #songs } end,
  listSongs = function()
    local out = {}
    for i, song in ipairs(songs) do
      out[i] = { name = song.name, index = song.index, bank = song.bank, player = song.player }
    end
    return out
  end,
  readSequence = function(song)
    for _, item in ipairs(songs) do
      if item.name == song.name then
        return { data = item.blob, base = 0, start = 0, size = #item.blob }
      end
    end
  end,
  readBank = function(bankID)
    bankCalls[#bankCalls + 1] = bankID
    local duty = bankID == 1 and 2 or 5
    return {
      count = 1,
      swarIDs = { 0, -1, -1, -1 },
      instruments = {
        [39] = { type = 2, defs = {
          [1] = { type = 2, waveID_dutyCycle = 0, waveArchiveID = 0,
            pitch = 60, attack = 100, decay = 100, sustain = 100,
            release = 80, pan = 64 },
        } },
        [40] = { type = 2, defs = {
          [1] = { type = 2, waveID_dutyCycle = duty, waveArchiveID = 0,
            pitch = 60, attack = 100, decay = 100, sustain = 100,
            release = 80, pan = 64 },
        } },
      },
    }
  end,
}
local g3Mix = { clockAt = realG3.clockAt }
function g3Mix.has() return true end
function g3Mix.buildSpecs(song, voices)
  captured[#captured + 1] = { song = song, voices = voices }
  return { { tempo = 100, channels = { { hw = 1, program = {} } } } }
end
local songMap = {
  keyFor = function() end,
  namesFor = function() return {} end,
}

local g4 = require("g4_mix")
check(g4.install({ g3Mix = g3Mix, nds = nds, songMap = songMap,
  versions = require("versions") }) == true, "install failed")

for _, name in ipairs({ "G4:SEQ_BANK_KEEP", "G4:SEQ_BANK_SWITCH" }) do
  local converted, err = g4.convert("gold", name)
  check(converted ~= nil, name .. " convert failed: " .. tostring(err))
end
eq(#captured, 2, "both songs converted")
local kept = captured[1].voices[1][1]
local switched = captured[2].voices[1][1]
eq(kept.type, 1, "single PSG instrument uses pulse channel")
eq(kept.wavParam, 3, "SBNK duty 5 maps to wide GB duty")
eq(switched.type, 1, "switched bank single PSG instrument uses pulse channel")
eq(switched.wavParam, 2, "SBNK duty 2 maps to 50% GB duty")
local saw700, saw1 = false, false
for _, bankID in ipairs(bankCalls) do
  if bankID == 700 then saw700 = true end
  if bankID == 1 then saw1 = true end
end
check(saw700 and saw1, "sequence bank and program bank override both used")

print("g4_bank_test: ok")
