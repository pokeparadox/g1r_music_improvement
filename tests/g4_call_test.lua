-- G4 Mix decoder must follow repeated CALLs to the same subroutine. Global
-- visited tracking stops at the second call and drops every later section.
package.path = "./?.lua;./tests/?.lua;" .. package.path

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

local source = assert(io.open("g4_mix.lua", "rb")):read("*a")
source = source:gsub("return M%s*$",
  "return { M = M, decodeTrack = decodeTrack, trackStarts = trackStarts }")
local probe = assert(loadstring(source, "g4_call_probe.lua"))()
probe.M.install({})

-- track 8: CALL sub, rest, CALL same sub, rest, note, JUMP back to 8.
-- subroutine 40: note, RET.  Only the main frame revisits 8, so the loop ends
-- after the whole body.
local body = string.char(0xC1, 100)
  .. string.char(0x95) .. u24le(40) .. rest(12)
  .. string.char(0x95) .. u24le(40) .. rest(12)
  .. note(60, 100, 4)
  .. string.char(0x94) .. u24le(8) .. string.char(0xFF)
local sub = note(62, 100, 4) .. string.char(0xFD)
local blob = string.char(0xFE) .. u16le(1)
  .. string.char(0x93, 0x00) .. u24le(8)
  .. body .. string.rep("\0", 40 - 8 - #body) .. sub
local seq = { data = blob, base = 0, start = 0 }

local starts = probe.trackStarts(seq)
assert(#starts == 1 and starts[1].offset == 8, "fixture header wrong")

local voices = { voices = {{}} }
function voices:voice() return 1 end
function voices:markLead() end
local decoded = probe.decodeTrack(seq, 8, voices, 0)

local notes, addresses = {}, {}
for _, event in ipairs(decoded.events) do
  if event.kind == "note" then
    notes[#notes + 1] = event
    addresses[#addresses + 1] = event.address
  end
end
assert(#notes == 3, "repeated CALL notes lost: " .. tostring(#notes))
assert(addresses[1] == 40 and addresses[2] == 40 and addresses[3] == 22,
  "CALL note order wrong: " .. table.concat(addresses, ","))
assert(decoded.loopStart and decoded.loopStart.address == 8,
  "loop must target main body start, not repeated CALL target: "
    .. tostring(decoded.loopStart and decoded.loopStart.address))
assert(decoded.loopEndTick == 36,
  "loop end wrong: " .. tostring(decoded.loopEndTick))

print("g4_call_test: ok")
