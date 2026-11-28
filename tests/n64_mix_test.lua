-- PCM conversion checks for the Stadium 2 EAD sequence parser.
-- Run: cd <mod> && luajit tests/n64_mix_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
-- LÖVE hosts on Lua 5.1 do not accept >> / << / goto; LuaJIT tests do.
local sourceFile = assert(io.open("n64_mix.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
assert(not source:find(">>") and not source:find("<<")
  and not source:find("goto%s"),
  "n64_mix.lua must stay Lua 5.1 compatible")
local fixture = dofile("tests/n64_fixture.lua")
local g3 = dofile("g3_mix.lua")
local map = dofile("n64_song_map.lua")
local n64 = dofile("n64_import.lua")
local n64Mix = dofile("n64_mix.lua")

n64.install({ imports = fixture.imports(), cache = fixture.cache() })

local capturedSong, capturedOptions
local fakeG3 = {
  buildSpecs = function(song, options)
    capturedSong, capturedOptions = song, options
    return { { tempo = 240, channels = { { hw = 1, program = {} } } } }
  end,
}
n64Mix.install({ g3Mix = fakeG3, n64 = n64, songMap = map })

assert(n64Mix.available() == true)
assert(n64Mix.has("red", "SEQ_N64_00") == true)
assert(n64Mix.has("red", "SEQ_N64_41") == false)
assert(n64Mix.has("red", "not-a-song") == false)

local converted, err = n64Mix.convert("red", "SEQ_N64_00", "pcm")
assert(converted, err)
assert(converted.def.n64Mix == true)
assert(converted.def.converter == "n64_v2_pcm_pcm")
assert(converted.def.key == "SEQ_N64_00" and converted.def.version == "red")
assert(converted.tempo == 120)
assert(capturedSong and capturedSong.tracks == 1)
assert(capturedOptions and capturedOptions.voicegroupId == 1)

local spec = converted.specs[#converted.specs]
assert(spec.pcm and #spec.pcm.events == 1)
assert(spec.pcm.tempoTimeline[1].tempo == 240,
  "120 BPM must map to legacy grid tempo 240")
local event = spec.pcm.events[1]
assert(event.tick == 48 and event.gate == 48)
assert(event.key == 66 and event.pitch == 60)
assert(event.bank == "n64:0" and event.wave == 0)
assert(event.vel == 0x7F)
assert(event.attack == 127 and event.release == 127)

assert(n64Mix.convert("red", "SEQ_N64_41", "pcm") == nil,
  "unmapped sequences must not silently convert sequence 0")
assert(g3.buildSpecs ~= nil, "real g3_mix must stay loadable alongside fake")

local oldDeps = n64Mix.deps
n64Mix.install({
  available = function() return true end,
  n64 = { available = function() return false end },
})
assert(n64Mix.available() == true,
  "injected status callback wins over stale n64.available")
n64Mix.deps = oldDeps

print("n64_mix_test: ok")
