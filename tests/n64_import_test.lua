-- Plain Lua asserts for the bounded Stadium 2 ROM reader.
-- Run: cd <mod> && luajit tests/n64_import_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local fixture = dofile("tests/n64_fixture.lua")
local n64 = dofile("n64_import.lua")

n64.install({ imports = fixture.imports(), cache = fixture.cache() })

local status = n64.status()
assert(status.available == true)
assert(status.sequenceCount == 1 and status.songCount == 1)
assert(status.bankCount == 1 and status.sampleBankCount == 1)
assert(status.fingerprint == "1561c75d11cedf356a8ddb1a4a5f9d5d")

local songs = n64.listSongs()
assert(#songs == 1 and songs[1].index == 0 and songs[1].size == 0x40)

assert(n64.bankForSequence(0) == 0)
assert(n64.bankForSequence(1) == nil)
assert(n64.bankForSequence("bad") == nil)

local sequence = assert(n64.readSequence(0))
assert(sequence.size == 0x40 and sequence.index == 0)
assert(sequence.data:byte(1) == 0xDD and sequence.data:byte(2) == 0x78)

local bank = assert(n64.readBank(0))
assert(#bank == 1)
assert(bank[1].waveID == 0 and bank[1].waveArchiveID == 0)
assert(bank[1].keyBase > 0.99 and bank[1].keyBase < 1.01)
assert(bank[1].wave.type == "vadpcm" and bank[1].wave.sampleRate == 32000)

local sample = assert(n64.readSample(0, bank[1]))
assert(sample.format == "vadpcm")
assert(sample.sampleRate == 32000 and sample.bank == 0)
assert(#sample.data == 64, "expected 32 decoded s16 samples, got " .. #sample.data)
assert(sample.sourceSize == 18)
assert(sample.loopStart == 0 and sample.loopEnd == 32)

-- Unknown ids/tables fail cleanly instead of returning junk.
assert(n64.readSequence(99) == nil)
assert(n64.readBank(99) == nil)
assert(n64.readSample(0, {}) == nil)

print("n64_import_test: ok")
