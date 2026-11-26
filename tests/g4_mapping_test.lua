-- Verifies HGSS GB Sounds scores attach to their native GSC song ids instead
-- of being exposed only as raw G4:SEQ_* labels.
package.path = "./?.lua;./tests/?.lua;" .. package.path

local realG3 = require("g3_mix")
local realMap = require("g4_song_map")
local versions = require("versions")

local function u24le(value)
  return string.char(value % 256, math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256)
end
local blob = string.char(0xFE, 0x01, 0x00, 0x93, 0x00) .. u24le(8)
  .. string.char(0x81, 0x00, 60, 100, 48, 0xFF)

local captured, bankSeen
local g3Mix = {
  lastError = nil,
  clockAt = realG3.clockAt,
  has = function() return false end,
  buildSpecs = function(song)
    captured = song
    return { { tempo = 100, channels = { { hw = 1, program = {} } } } }
  end,
}
local nds = {
  status = function() return { available = true, songCount = 4 } end,
  listSongs = function()
    return {
      { name = "SEQ_CITY02_N", index = 1, bank = 1001, player = 1 },
      { name = "SEQ_GS_C_KIKYOU", index = 2, bank = 703, player = 1 },
      { name = "SEQ_GS_T_WAKABA", index = 3, bank = 702, player = 1 },
      { name = "SEQ_GS_P_C_KIKYOU", index = 4, bank = 701, player = 1 },
    }
  end,
  readSequence = function()
    return { data = blob, base = 0, start = 0, size = #blob }
  end,
  readBank = function(bankID)
    bankSeen = bankID
    assert(bankID == 1001 or bankID == 703 or bankID == 701,
      "sequence bank must be inherited: " .. tostring(bankID))
    return { count = 1, instruments = {
      [1] = { type = 1, notes = {
        [1] = { type = 1, waveID_dutyCycle = 0, waveArchiveID = 0,
          pitch = 60, attack = 100, decay = 100, sustain = 100,
          release = 80, pan = 64 },
      } },
    } }
  end,
}

local g4 = require("g4_mix")
assert(g4.install({ g3Mix = g3Mix, nds = nds, songMap = realMap,
  versions = versions }) == true)

assert(g4.has("gold", "Music_VioletCity", "pcm") == true,
  "GSC host must expose mapped Violet City G4 Mix")
assert(g4.has("gold", "Music_VioletCity", "chip") == true,
  "GSC host must expose mapped Violet City G4 GB")
assert(g4.has("red", "Music_VioletCity") == false,
  "Johto-only group must not expose G4 Mix on RBY hosts")
assert(g4.has("gold", "G4:SEQ_GS_C_KIKYOU") == true)

local labelSeen, rawSeen, pRawSeen = false, false, false
for _, label in ipairs(g4.songList()) do
  if label == "Music_VioletCity" then labelSeen = true end
  if label == "G4:SEQ_GS_C_KIKYOU" then rawSeen = true end
  if label == "G4:SEQ_GS_P_C_KIKYOU" then pRawSeen = true end
end
assert(labelSeen, "songList must use native GSC id")
assert(not rawSeen, "mapped song must not also appear as raw G4 label")
assert(not pRawSeen, "mapped P arrangement must not appear as raw G4 label")

local converted, err = g4.convert("gold", "Music_VioletCity", "pcm")
assert(converted, err)
assert(converted.def.generation == 2 and converted.def.g4Mix == true)
assert(bankSeen == 1001, "G4 Mix must use normal DS arrangement bank")
assert(captured and captured.tracks == 1, "conversion must use imported SSEQ")

local gb = assert(g4.convert("gold", "Music_VioletCity", "chip"))
assert(gb.def.g4Gb == true and gb.def.g4Mix == false)
assert(bankSeen == 701,
  "G4 GB must use PSG-only GB Sounds arrangement")

print("g4_mapping_test: ok")
