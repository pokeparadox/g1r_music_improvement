-- Plain Lua asserts for the offline GBA -> ChipAsm converter.
-- Run: cd <mod> && luajit tests/g3_mix_test.lua
package.path = "./?.lua;" .. package.path
local mix = dofile("g3_mix.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

eq(mix.clockAt(0), 0, "clock zero")
eq(mix.clockAt(1), 1, "clock one")
eq(mix.clockAt(39), 68, "clock lookup")
eq(mix.clockAt(200), 200, "clock fallback")

-- voice 1, note key 60 vel 100 gate index 4, wait 1, tempo 200, end.
local track = string.char(0xBD, 0x01, 0xD3, 60, 100, 0x81, 0xBB, 0x64, 0xB1)
local decoded = mix.decodeTrack(track)
eq(#decoded.events, 2, "event count")
eq(decoded.events[1].kind, "note", "first event kind")
eq(decoded.events[1].tick, 0, "note tick")
eq(decoded.events[1].gate, 4, "note gate")
eq(decoded.events[1].key, 60, "note key")
eq(decoded.events[2].kind, "tempo", "second event kind")
eq(decoded.events[2].tick, 1, "tempo tick")
eq(decoded.events[2].tempo, 200, "tempo value")

local wave = {}
for i = 1, 32 do wave[i] = i % 2 == 0 and 1 or -1 end
local song = {
  tracks = 5,
  trackData = {
    track, "", "", "", "",
  },
  voicegroup = 1,
}
local voicegroups = {
  [1] = {
    [1] = { type = 1, wavParam = 0 },
    [2] = { type = 3, wave = wave },
    [3] = { type = 4 },
  },
}
local specs = mix.buildSpecs(song, voicegroups, { voicegroupId = 1 })
assert(specs, "buildSpecs returned nil")
eq(#specs, 2, "engine count")
eq(#specs[1].channels, 4, "first engine channels")
eq(#specs[2].channels, 1, "second engine channels")
eq(specs[1].tempo, 256, "base tempo")
local used = {}
for _, channel in ipairs(specs[1].channels) do
  assert(channel.hw >= 1 and channel.hw <= 4, "hw range")
  assert(not used[channel.hw], "duplicate hw")
  used[channel.hw] = true
  local last = channel.program[#channel.program]
  assert(last.loop and last.loop.count == 0, "channel loop terminator")
end

print("g3_mix ok")
